# 05_optional_glsea.R
# Optional: Download GLSEA satellite-derived SST and compare with LEOFS and buoy.
# No sf dependency.
#
# This script assumes the following scripts have already been run:
#   source("00_setup.R")
#   source("02_buoy_observations.R")
#   source("03_extract_leofs_timeseries.R")
#   source("04_compare_model_buoy.R")
#
# It can also reload model_ts from CSV if needed.

# -------------------------------------------------------------------
# Local fallback helper functions
# -------------------------------------------------------------------

if (!exists("wrap_lon")) {
  wrap_lon <- function(lon) {
    ((lon + 180) %% 360) - 180
  }
}

if (!exists("convert_target_lon_for_model")) {
  convert_target_lon_for_model <- function(model_lon, target_lon) {
    if (max(model_lon, na.rm = TRUE) > 180 && target_lon < 0) {
      return(target_lon %% 360)
    } else {
      return(target_lon)
    }
  }
}

if (!exists("var_dim_names")) {
  var_dim_names <- function(nc, varname) {
    sapply(nc$var[[varname]]$dim, function(x) x$name)
  }
}

# Robust CF-style time parser.
# This is included here so GLSEA can parse its own numeric time variable.
glsea_parse_cf_time <- function(time_values, units) {
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
    warning("Unrecognized GLSEA time units: ", units)
    return(rep(as.POSIXct(NA, tz = "UTC"), length(time_values)))
  }

  origin_string <- sub(".* since ", "", units)
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
    warning("Could not parse GLSEA time origin from units: ", units)
    return(rep(as.POSIXct(NA, tz = "UTC"), length(time_values)))
  }

  origin + as.numeric(time_values) * multiplier
}

# -------------------------------------------------------------------
# GLSEA download settings
# -------------------------------------------------------------------

url_glsea_base <- "https://apps.glerl.noaa.gov/thredds/fileServer/glsea_nc_3"

download_one_glsea_file <- function(date, glsea_dir) {
  # Important: preserve Date behavior
  date <- as.Date(date)

  yearstr <- format(date, "%Y")
  monstr <- format(date, "%m")
  doystr <- format(date, "%j")

  fname <- sprintf("%s_%s_glsea_sst.nc", yearstr, doystr)
  url <- sprintf("%s/%s/%s/%s", url_glsea_base, yearstr, monstr, fname)
  local_path <- file.path(glsea_dir, fname)

  if (file.exists(local_path)) {
    cat("Already exists, skipping:", fname, "\n")
    return(local_path)
  }

  cat("Downloading GLSEA:", fname, "\n")

  ok <- tryCatch(
    {
      download.file(url, local_path, mode = "wb", quiet = TRUE)
      TRUE
    },
    error = function(e) {
      warning(
        paste0(
          "Failed to download GLSEA file: ", fname, "\n",
          "URL: ", url, "\n",
          "Error: ", e$message
        )
      )
      FALSE
    }
  )

  if (ok) {
    return(local_path)
  } else {
    return(NA_character_)
  }
}

# -------------------------------------------------------------------
# Download GLSEA files
# -------------------------------------------------------------------

glsea_dates <- seq(start_date, end_date, by = "day")
glsea_files <- c()

# Use seq_along() to avoid R dropping Date class in for-loops.
for (i_date in seq_along(glsea_dates)) {
  date <- glsea_dates[i_date]

  glsea_files <- c(
    glsea_files,
    download_one_glsea_file(
      date = date,
      glsea_dir = glsea_dir
    )
  )
}

glsea_files <- glsea_files[!is.na(glsea_files)]

if (length(glsea_files) == 0) {
  stop("No GLSEA files were downloaded or found.")
}

# Sort files by filename date
glsea_files <- sort(glsea_files)

cat("\nGLSEA files available:", length(glsea_files), "\n")
print(basename(glsea_files))

# -------------------------------------------------------------------
# GLSEA helper functions
# -------------------------------------------------------------------

parse_glsea_filename_date <- function(path) {
  # Filename example:
  # 2025_152_glsea_sst.nc

  b <- basename(path)

  m <- regexec("^([0-9]{4})_([0-9]{3})_glsea_sst\\.nc$", b)
  parts <- regmatches(b, m)[[1]]

  if (length(parts) == 0) {
    return(as.POSIXct(NA, tz = "UTC"))
  }

  year <- as.integer(parts[2])
  doy <- as.integer(parts[3])

  as.POSIXct(
    as.Date(doy - 1, origin = sprintf("%04d-01-01", year)),
    tz = "UTC"
  )
}

get_nc_coord <- function(nc, coord_name_options) {
  # Try to read coordinate from nc$var first, then nc$dim.
  # coord_name_options is a character vector, e.g. c("lon", "longitude")

  for (nm in coord_name_options) {
    if (nm %in% names(nc$var)) {
      return(list(
        name = nm,
        values = as.numeric(ncdf4::ncvar_get(nc, nm))
      ))
    }

    if (nm %in% names(nc$dim)) {
      return(list(
        name = nm,
        values = as.numeric(nc$dim[[nm]]$vals)
      ))
    }
  }

  stop(
    "Could not find coordinate. Tried: ",
    paste(coord_name_options, collapse = ", ")
  )
}

read_glsea_valid_time <- function(nc, nc_path = NULL) {
  # Prefer numeric NetCDF time if available.
  # Fall back to date parsed from filename.

  t_numeric <- tryCatch(
    {
      if (!"time" %in% names(nc$var) && !"time" %in% names(nc$dim)) {
        as.POSIXct(NA, tz = "UTC")
      } else {
        if ("time" %in% names(nc$var)) {
          time_raw <- ncdf4::ncvar_get(nc, "time", collapse_degen = FALSE)
          time_units <- ncdf4::ncatt_get(nc, "time", "units")$value
        } else {
          time_raw <- nc$dim[["time"]]$vals
          time_units <- nc$dim[["time"]]$units
        }

        glsea_parse_cf_time(
          time_values = as.numeric(time_raw)[1],
          units = time_units
        )[1]
      }
    },
    error = function(e) {
      as.POSIXct(NA, tz = "UTC")
    }
  )

  if (!is.na(t_numeric)) {
    return(t_numeric)
  }

  if (!is.null(nc_path)) {
    return(parse_glsea_filename_date(nc_path))
  }

  as.POSIXct(NA, tz = "UTC")
}

extract_glsea_point <- function(nc_path, target_lon, target_lat) {
  nc <- NULL

  result <- tryCatch(
    {
      nc <- ncdf4::nc_open(nc_path)

      # Identify SST variable
      sst_name <- if ("sst" %in% names(nc$var)) {
        "sst"
      } else if ("SST" %in% names(nc$var)) {
        "SST"
      } else {
        stop("Could not find sst/SST variable in GLSEA file: ", basename(nc_path))
      }

      # Identify coordinates
      lon_info <- get_nc_coord(nc, c("lon", "longitude", "x"))
      lat_info <- get_nc_coord(nc, c("lat", "latitude", "y"))

      lon_name <- lon_info$name
      lat_name <- lat_info$name
      lon <- lon_info$values
      lat <- lat_info$values

      target_lon_glsea <- convert_target_lon_for_model(lon, target_lon)

      lon_idx <- which.min(abs(lon - target_lon_glsea))
      lat_idx <- which.min(abs(lat - target_lat))

      sst_dims <- var_dim_names(nc, sst_name)

      # Build start/count in variable dimension order.
      # We set all dimensions to one point.
      start <- rep(1, length(sst_dims))
      count <- rep(1, length(sst_dims))

      names(start) <- sst_dims
      names(count) <- sst_dims

      # Time dimension, if present
      if ("time" %in% sst_dims) {
        start["time"] <- 1
        count["time"] <- 1
      }

      # Longitude dimension
      if (lon_name %in% sst_dims) {
        start[lon_name] <- lon_idx
        count[lon_name] <- 1
      } else if ("lon" %in% sst_dims) {
        start["lon"] <- lon_idx
        count["lon"] <- 1
      } else if ("longitude" %in% sst_dims) {
        start["longitude"] <- lon_idx
        count["longitude"] <- 1
      } else if ("x" %in% sst_dims) {
        start["x"] <- lon_idx
        count["x"] <- 1
      } else {
        stop(
          "Could not match longitude coordinate to SST dimensions. SST dims: ",
          paste(sst_dims, collapse = ", ")
        )
      }

      # Latitude dimension
      if (lat_name %in% sst_dims) {
        start[lat_name] <- lat_idx
        count[lat_name] <- 1
      } else if ("lat" %in% sst_dims) {
        start["lat"] <- lat_idx
        count["lat"] <- 1
      } else if ("latitude" %in% sst_dims) {
        start["latitude"] <- lat_idx
        count["latitude"] <- 1
      } else if ("y" %in% sst_dims) {
        start["y"] <- lat_idx
        count["y"] <- 1
      } else {
        stop(
          "Could not match latitude coordinate to SST dimensions. SST dims: ",
          paste(sst_dims, collapse = ", ")
        )
      }

      sst_value <- ncdf4::ncvar_get(
        nc,
        sst_name,
        start = as.integer(start),
        count = as.integer(count)
      )

      sst_value <- as.numeric(sst_value)[1]

      datetime_value <- read_glsea_valid_time(nc, nc_path)

      data.frame(
        datetime = as.POSIXct(datetime_value, tz = "UTC"),
        sst = sst_value,
        glsea_lon = wrap_lon(lon[lon_idx]),
        glsea_lat = lat[lat_idx],
        file = basename(nc_path),
        stringsAsFactors = FALSE
      )
    },
    error = function(e) {
      warning(
        paste0(
          "Failed to process GLSEA file: ",
          basename(nc_path),
          "\nError: ",
          e$message
        )
      )

      data.frame(
        datetime = as.POSIXct(parse_glsea_filename_date(nc_path), tz = "UTC"),
        sst = NA_real_,
        glsea_lon = NA_real_,
        glsea_lat = NA_real_,
        file = basename(nc_path),
        stringsAsFactors = FALSE
      )
    },
    finally = {
      if (!is.null(nc)) {
        try(ncdf4::nc_close(nc), silent = TRUE)
      }
    }
  )

  result
}

# -------------------------------------------------------------------
# Extract GLSEA time series nearest to buoy
# -------------------------------------------------------------------

cat("\nExtracting GLSEA SST nearest to buoy location...\n")

glsea_list <- vector("list", length(glsea_files))

for (i in seq_along(glsea_files)) {
  cat(
    "Processing GLSEA file",
    i,
    "of",
    length(glsea_files),
    ":",
    basename(glsea_files[i]),
    "\n"
  )

  glsea_list[[i]] <- extract_glsea_point(
    nc_path = glsea_files[i],
    target_lon = target_lon,
    target_lat = target_lat
  )
}

bad_items <- !vapply(glsea_list, is.data.frame, logical(1))

if (any(bad_items)) {
  warning(
    "Some GLSEA entries are not data frames. Bad entries: ",
    paste(which(bad_items), collapse = ", ")
  )

  glsea_list <- glsea_list[!bad_items]
}

glsea_ts <- dplyr::bind_rows(glsea_list) %>%
  arrange(datetime)

cat("\nGLSEA point time series:\n")
print(glsea_ts)

cat("\nSummary of GLSEA SST:\n")
print(summary(glsea_ts$sst))

write.csv(
  glsea_ts,
  file.path(output_dir, paste0("glsea_sst_buoy_", buoy_id, ".csv")),
  row.names = FALSE
)

# -------------------------------------------------------------------
# Quick GLSEA-only plot
# -------------------------------------------------------------------

p_glsea <- ggplot(glsea_ts, aes(x = datetime, y = sst)) +
  geom_point(color = "darkgreen", size = 2, na.rm = TRUE) +
  geom_line(color = "darkgreen", linewidth = 0.4, na.rm = TRUE) +
  scale_x_datetime(
    timezone = "UTC",
    date_labels = "%b %d\n%H:%M UTC"
  ) +
  labs(
    x = "Date/time, UTC",
    y = "GLSEA SST (°C)",
    title = paste("GLSEA SST nearest to buoy", buoy_id)
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold")
  )

print(p_glsea)

ggsave(
  filename = file.path(fig_dir, paste0("glsea_sst_buoy_", buoy_id, ".png")),
  plot = p_glsea,
  width = 9,
  height = 4.5,
  dpi = 300
)

# -------------------------------------------------------------------
# Load model and buoy data if needed
# -------------------------------------------------------------------

if (!exists("model_ts")) {
  model_csv <- file.path(
    output_dir,
    paste0(systemname, "_surface_temp_buoy_", buoy_id, ".csv")
  )

  if (!file.exists(model_csv)) {
    stop(
      "model_ts not found and model CSV does not exist. ",
      "Run 03_extract_leofs_timeseries.R first."
    )
  }

  model_ts <- read.csv(model_csv)
  model_ts$datetime <- as.POSIXct(model_ts$datetime, tz = "UTC")
}

if (!exists("buoy_df")) {
  stop("buoy_df not found. Run 02_buoy_observations.R first.")
}

# -------------------------------------------------------------------
# Add GLSEA to model-buoy comparison
# -------------------------------------------------------------------

plot_start <- min(model_ts$datetime, na.rm = TRUE)
plot_end <- max(model_ts$datetime, na.rm = TRUE)

buoy_plot_df <- buoy_df %>%
  filter(datetime >= plot_start, datetime <= plot_end)

buoy_label <- paste0("Buoy ", buoy_id)

model_plot_df <- model_ts %>%
  transmute(
    datetime = datetime,
    temperature = temp_surface_point,
    dataset = "LEOFS"
  )

buoy_plot_df2 <- buoy_plot_df %>%
  transmute(
    datetime = datetime,
    temperature = WTMP,
    dataset = buoy_label
  )

glsea_plot_df <- glsea_ts %>%
  transmute(
    datetime = datetime,
    temperature = sst,
    dataset = "GLSEA"
  )

comparison_glsea_df <- dplyr::bind_rows(
  model_plot_df,
  buoy_plot_df2,
  glsea_plot_df
)

comparison_glsea_colors <- setNames(
  c("firebrick", "steelblue", "darkgreen"),
  c("LEOFS", buoy_label, "GLSEA")
)

p_model_buoy_glsea <- ggplot(
  comparison_glsea_df,
  aes(x = datetime, y = temperature, color = dataset)
) +
  geom_line(
    data = comparison_glsea_df %>% filter(dataset != "GLSEA"),
    linewidth = 0.6,
    na.rm = TRUE
  ) +
  geom_point(
    data = comparison_glsea_df %>% filter(dataset == "GLSEA"),
    size = 2,
    na.rm = TRUE
  ) +
  coord_cartesian(
    xlim = c(plot_start, plot_end),
    ylim = comparison_ylim
  ) +
  scale_x_datetime(
    timezone = "UTC",
    date_labels = "%b %d\n%H:%M UTC"
  ) +
  scale_color_manual(values = comparison_glsea_colors) +
  labs(
    x = "Date/time, UTC",
    y = "Water temperature / SST (°C)",
    color = NULL,
    title = paste("LEOFS, NDBC buoy", buoy_id, "and GLSEA temperature comparison")
  ) +
  theme_minimal() +
  theme(
    legend.position = "bottom",
    plot.title = element_text(face = "bold")
  )

print(p_model_buoy_glsea)

ggsave(
  filename = file.path(
    fig_dir,
    paste0("comparison_", systemname, "_buoy_", buoy_id, "_glsea.png")
  ),
  plot = p_model_buoy_glsea,
  width = 10,
  height = 5,
  dpi = 300
)

# -------------------------------------------------------------------
# Optional: write combined comparison data
# -------------------------------------------------------------------

#write.csv(
#  comparison_glsea_df,
#  file.path(output_dir, paste0("comparison_", systemname, "_buoy_", buoy_id, "_glsea.csv")),
#  row.names = FALSE
#)

#cat("\nSaved GLSEA outputs to:\n")
#cat("CSV:", file.path(output_dir, paste0("glsea_sst_buoy_", buoy_id, ".csv")), "\n")
#cat("Figure:", file.path(fig_dir, paste0("comparison_", systemname, "_buoy_", buoy_id, "_glsea.png")), "\n")


