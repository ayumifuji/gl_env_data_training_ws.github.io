# 00_setup.R
# Setup script for Hands-on Session 2.
# No sf dependency.

required_packages <- c(
  "ncdf4",
  "ggplot2",
  "dplyr",
  "lubridate",
  "grid"
)

installed <- rownames(installed.packages())
to_install <- setdiff(required_packages, installed)

if (length(to_install) > 0) {
  install.packages(to_install)
}

library(ncdf4)
library(ggplot2)
library(dplyr)
library(lubridate)
library(grid)

# -------------------------------------------------------------------
# User settings
# -------------------------------------------------------------------

# Main output directory
save_dir <- file.path(getwd(), "GL_env_data", "handson2")

glofs_dir <- file.path(save_dir, "glofs")
buoy_dir <- file.path(save_dir, "buoy")
glsea_dir <- file.path(save_dir, "glsea")
fig_dir <- file.path(save_dir, "figures")
output_dir <- file.path(save_dir, "outputs")

dirs <- c(save_dir, glofs_dir, buoy_dir, glsea_dir, fig_dir, output_dir)

for (d in dirs) {
  if (!dir.exists(d)) {
    dir.create(d, recursive = TRUE)
  }
}

cat("Files will be saved in:", save_dir, "\n")

# -------------------------------------------------------------------
# GLOFS/LEOFS settings
# -------------------------------------------------------------------

systemname <- "leofs"

# Original notebook period: June 1-7, 2025
start_date <- as.Date("2025-06-01")
end_date   <- as.Date("2025-06-07")

# Set this to TRUE to download and compare GLSEA data.
# You can set FALSE if you only want LEOFS + buoy.
run_glsea_optional <- TRUE

# -------------------------------------------------------------------
# Buoy settings
# -------------------------------------------------------------------

buoy_id <- "45005"
buoy_year <- 2025

# Buoy 45005 location:
# 41.677 N, 82.398 W
target_lon <- -82.398
target_lat <- 41.677

# -------------------------------------------------------------------
# Plot settings
# -------------------------------------------------------------------

comparison_ylim <- c(12, 19)

# -------------------------------------------------------------------
# Helper functions
# -------------------------------------------------------------------

wrap_lon <- function(lon) {
  ((lon + 180) %% 360) - 180
}

convert_target_lon_for_model <- function(model_lon, target_lon) {
  if (max(model_lon, na.rm = TRUE) > 180 && target_lon < 0) {
    return(target_lon %% 360)
  } else {
    return(target_lon)
  }
}

parse_cf_time <- function(time_values, units) {
  # Parse CF-style time units such as:
  # "seconds since 2015-01-01 00:00:00"
  # "hours since 2025-06-01 00:00:00"
  # Returns POSIXct in UTC.

  if (is.null(units) || is.na(units)) {
    return(rep(as.POSIXct(NA, tz = "UTC"), length(time_values)))
  }

  units_lower <- tolower(units)

  if (grepl("^seconds since", units_lower)) {
    multiplier <- 1
  } else if (grepl("^minutes since", units_lower)) {
    multiplier <- 60
  } else if (grepl("^hours since", units_lower)) {
    multiplier <- 3600
  } else if (grepl("^days since", units_lower)) {
    multiplier <- 86400
  } else {
    warning("Unrecognized time units: ", units)
    return(rep(as.POSIXct(NA, tz = "UTC"), length(time_values)))
  }

  # Extract origin from the original, not lower-cased, units string
  origin_string <- sub(".* since ", "", units)

  # Clean common timezone/format suffixes
  origin_string <- gsub("T", " ", origin_string)
  origin_string <- gsub("Z", "", origin_string)
  origin_string <- gsub("UTC", "", origin_string, ignore.case = TRUE)
  origin_string <- trimws(origin_string)

  origin <- as.POSIXct(
    origin_string,
    tz = "UTC",
    tryFormats = c(
      "%Y-%m-%d %H:%M:%OS",
      "%Y-%m-%d %H:%M:%S",
      "%Y-%m-%d %H:%M",
      "%Y-%m-%d"
    )
  )

  if (is.na(origin)) {
    warning("Could not parse time origin from units: ", units)
    return(rep(as.POSIXct(NA, tz = "UTC"), length(time_values)))
  }

  origin + as.numeric(time_values) * multiplier
}

read_leofs_time_from_numeric_time <- function(nc) {
  if (!"time" %in% names(nc$var)) {
    return(as.POSIXct(NA, tz = "UTC"))
  }

  time_raw <- ncdf4::ncvar_get(
    nc,
    "time",
    collapse_degen = FALSE
  )

  time_units <- ncdf4::ncatt_get(nc, "time", "units")$value

  parse_cf_time(
    time_values = as.numeric(time_raw),
    units = time_units
  )[1]
}

extract_array_value <- function(arr, dims, selectors) {
  # arr: NetCDF array
  # dims: character vector of dimension names in arr order
  # selectors: named list of dimension selections, e.g.
  #   list(time = 1, siglay = 1, node = 100)
  #
  # Returns selected value/vector.

  idx <- vector("list", length(dims))

  for (i in seq_along(dims)) {
    dn <- dims[i]

    if (dn %in% names(selectors)) {
      idx[[i]] <- selectors[[dn]]
    } else {
      idx[[i]] <- seq_len(dim(arr)[i])
    }
  }

  do.call(`[`, c(list(arr), idx, list(drop = TRUE)))
}

parse_leofs_filename_time <- function(path) {
  # Parses filenames like:
  # leofs.t00z.20250601.fields.n000.nc
  # Valid time = YYYYMMDD + cycle hour + n hour.

  b <- basename(path)

  m <- regexec(
    "^([A-Za-z0-9]+)\\.t([0-9]{2})z\\.([0-9]{8})\\.fields\\.n([0-9]{3})\\.nc$",
    b
  )

  parts <- regmatches(b, m)[[1]]

  if (length(parts) == 0) {
    return(as.POSIXct(NA, tz = "UTC"))
  }

  cycle_hour <- as.integer(parts[3])
  yyyymmdd <- parts[4]
  n_hour <- as.integer(parts[5])

  base_time <- as.POSIXct(
    yyyymmdd,
    format = "%Y%m%d",
    tz = "UTC"
  )

  base_time + lubridate::hours(cycle_hour + n_hour)
}


