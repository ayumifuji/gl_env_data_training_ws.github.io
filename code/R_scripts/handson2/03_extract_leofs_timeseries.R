# 03_extract_leofs_timeseries.R
# Find nearest LEOFS model node to buoy and extract model surface temperature time series.
# Robust no-sf version.

# This script assumes 00_setup.R has already been sourced.
# Required objects from 00_setup.R:
#   glofs_dir, output_dir, fig_dir, systemname
#   buoy_id, target_lon, target_lat
#   ncdf4, ggplot2, dplyr, lubridate

# -------------------------------------------------------------------
# Fallback helper functions
# -------------------------------------------------------------------
# These are included here to make this script more robust in case
# the helper versions in 00_setup.R were not updated.

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

# Robust CF-style time parser
parse_cf_time_robust <- function(time_values, units) {
  # Parse common CF-style time units such as:
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

  # Extract origin from original units string
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

# Filename-derived fallback time.
# This is no longer treated as authoritative for LEOFS valid time,
# but it is useful for sorting and as a final fallback.
parse_leofs_filename_time_local <- function(path) {
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

# Use parse_leofs_filename_time from 00_setup.R if it exists;
# otherwise use local fallback.
if (!exists("parse_leofs_filename_time")) {
  parse_leofs_filename_time <- parse_leofs_filename_time_local
}

# -------------------------------------------------------------------
# Helper: read Times character variable, if needed
# -------------------------------------------------------------------

read_times_char_variable <- function(nc) {
  # Reads FVCOM-style Times(time, DateStrLen), e.g.
  # "2025-06-03T20:00:00.000000"
  #
  # This is used as a fallback/diagnostic. Numeric time is preferred.

  if (!"Times" %in% names(nc$var)) {
    return(as.POSIXct(NA, tz = "UTC"))
  }

  out <- tryCatch(
    {
      raw_times <- ncdf4::ncvar_get(
        nc,
        "Times",
        collapse_degen = FALSE
      )

      dims <- var_dim_names(nc, "Times")
      raw_dim <- dim(raw_times)

      if (is.null(raw_dim)) {
        times_string <- paste0(as.vector(raw_times), collapse = "")
      } else if (length(raw_dim) == 2) {
        # Try to orient to time x DateStrLen
        if (all(c("time", "DateStrLen") %in% dims)) {
          perm <- match(c("time", "DateStrLen"), dims)
          raw2 <- aperm(raw_times, perm)
          times_string <- apply(raw2, 1, paste0, collapse = "")[1]
        } else {
          # Fallback: DateStrLen is commonly 26
          if (raw_dim[1] == 26 && raw_dim[2] >= 1) {
            raw2 <- t(raw_times)
            times_string <- apply(raw2, 1, paste0, collapse = "")[1]
          } else if (raw_dim[2] == 26 && raw_dim[1] >= 1) {
            raw2 <- raw_times
            times_string <- apply(raw2, 1, paste0, collapse = "")[1]
          } else {
            times_string <- paste0(as.vector(raw_times), collapse = "")
          }
        }
      } else {
        squeezed <- drop(raw_times)
        times_string <- paste0(as.vector(squeezed), collapse = "")
      }

      #times_string <- gsub("\0", "", times_string, fixed = TRUE)
      times_string <- gsub("[[:cntrl:]]", "", times_string)
      times_string <- trimws(times_string)

      as.POSIXct(
        times_string,
        format = "%Y-%m-%dT%H:%M:%OS",
        tz = "UTC"
      )
    },
    error = function(e) {
      as.POSIXct(NA, tz = "UTC")
    }
  )

  out
}

# -------------------------------------------------------------------
# Helper: read valid time from open NetCDF file
# -------------------------------------------------------------------

read_valid_time_from_open_nc <- function(nc, nc_path = NULL) {
  # Priority:
  # 1. Numeric NetCDF time variable + units
  # 2. FVCOM Times character variable
  # 3. Filename-derived fallback

  # 1. Preferred: numeric time
  numeric_time <- tryCatch(
    {
      if (!"time" %in% names(nc$var)) {
        as.POSIXct(NA, tz = "UTC")
      } else {
        time_raw <- ncdf4::ncvar_get(
          nc,
          "time",
          collapse_degen = FALSE
        )

        time_units <- ncdf4::ncatt_get(nc, "time", "units")$value

        parse_cf_time_robust(
          time_values = as.numeric(time_raw)[1],
          units = time_units
        )[1]
      }
    },
    error = function(e) {
      as.POSIXct(NA, tz = "UTC")
    }
  )

  if (!is.na(numeric_time)) {
    return(numeric_time)
  }

  # 2. Fallback: Times
  times_time <- read_times_char_variable(nc)

  if (!is.na(times_time)) {
    return(times_time)
  }

  # 3. Last fallback: filename convention
  if (!is.null(nc_path)) {
    return(parse_leofs_filename_time(nc_path))
  }

  as.POSIXct(NA, tz = "UTC")
}

# -------------------------------------------------------------------
# Find and sort LEOFS files
# -------------------------------------------------------------------

glofs_files <- list.files(
  glofs_dir,
  pattern = paste0(
    "^",
    systemname,
    "\\.t[0-9]{2}z\\.[0-9]{8}\\.fields\\.n[0-9]{3}\\.nc$"
  ),
  full.names = TRUE
)

if (length(glofs_files) == 0) {
  stop("No GLOFS files found in: ", glofs_dir)
}

# Sort initially by filename-derived time.
# Later, model_ts is arranged by actual NetCDF time.
glofs_times_from_name <- as.POSIXct(
  vapply(
    glofs_files,
    function(f) as.numeric(parse_leofs_filename_time(f)),
    numeric(1)
  ),
  origin = "1970-01-01",
  tz = "UTC"
)

ord <- order(glofs_times_from_name)
glofs_files <- glofs_files[ord]
glofs_times_from_name <- glofs_times_from_name[ord]

cat("Found", length(glofs_files), "LEOFS files.\n")
cat("First file:", basename(glofs_files[1]), "\n")
cat("Last file:", basename(glofs_files[length(glofs_files)]), "\n\n")

# Check file sizes
file_sizes <- file.info(glofs_files)$size

if (any(is.na(file_sizes) | file_sizes == 0)) {
  bad_files <- glofs_files[is.na(file_sizes) | file_sizes == 0]

  warning(
    "Some GLOFS files appear to be missing or zero bytes:\n",
    paste(basename(bad_files), collapse = "\n")
  )
}

valid_file_idx <- which(!is.na(file_sizes) & file_sizes > 0)

if (length(valid_file_idx) == 0) {
  stop("No valid non-empty GLOFS files found.")
}

# -------------------------------------------------------------------
# Find nearest node using the first valid file
# -------------------------------------------------------------------

first_file <- glofs_files[valid_file_idx[1]]

cat("Using file to identify mesh:", basename(first_file), "\n")

nc0 <- NULL

mesh_info <- tryCatch(
  {
    nc0 <- ncdf4::nc_open(first_file)

    lon_model <- ncdf4::ncvar_get(
      nc0,
      "lon",
      collapse_degen = FALSE
    )

    lat_model <- ncdf4::ncvar_get(
      nc0,
      "lat",
      collapse_degen = FALSE
    )

    list(
      lon_model = as.numeric(lon_model),
      lat_model = as.numeric(lat_model)
    )
  },
  error = function(e) {
    stop(
      paste0(
        "Could not read lon/lat from first GLOFS file: ",
        basename(first_file),
        "\nOriginal error: ",
        e$message
      )
    )
  },
  finally = {
    if (!is.null(nc0)) {
      try(ncdf4::nc_close(nc0), silent = TRUE)
    }
  }
)

lon_model <- mesh_info$lon_model
lat_model <- mesh_info$lat_model

target_lon_model <- convert_target_lon_for_model(lon_model, target_lon)

# Approximate nearest-node distance in lon/lat space
dist2 <- ((lon_model - target_lon_model) * cos(target_lat * pi / 180))^2 +
  (lat_model - target_lat)^2

nearest_node <- which.min(dist2)

cat("Nearest node index in R, 1-based:", nearest_node, "\n")
cat("Nearest node index in Python, 0-based:", nearest_node - 1, "\n")
cat("Nearest model lon:", wrap_lon(lon_model[nearest_node]), "\n")
cat("Nearest model lat:", lat_model[nearest_node], "\n\n")

nearest_node_df <- data.frame(
  buoy_id = buoy_id,
  target_lon = target_lon,
  target_lat = target_lat,
  nearest_node_r_index = nearest_node,
  nearest_node_python_index = nearest_node - 1,
  model_lon = wrap_lon(lon_model[nearest_node]),
  model_lat = lat_model[nearest_node],
  stringsAsFactors = FALSE
)

write.csv(
  nearest_node_df,
  file.path(output_dir, paste0("nearest_node_buoy_", buoy_id, ".csv")),
  row.names = FALSE
)

# -------------------------------------------------------------------
# Helper: extract surface temp at nearest node from one file
# -------------------------------------------------------------------

extract_surface_temp_point <- function(nc_path, nearest_node) {
  nc <- NULL

  result <- tryCatch(
    {
      nc <- ncdf4::nc_open(nc_path)

      if (!"temp" %in% names(nc$var)) {
        stop("Variable 'temp' not found.")
      }

      temp_dims <- var_dim_names(nc, "temp")

      # Build start/count vectors in NetCDF variable dimension order.
      # For LEOFS temp(time, siglay, node), this becomes:
      #   start = c(1, 1, nearest_node)
      #   count = c(1, 1, 1)
      start <- rep(1, length(temp_dims))
      count <- rep(1, length(temp_dims))

      names(start) <- temp_dims
      names(count) <- temp_dims

      # Select first time index
      if ("time" %in% temp_dims) {
        start["time"] <- 1
        count["time"] <- 1
      }

      # Select surface layer
      if ("siglay" %in% temp_dims) {
        start["siglay"] <- 1
        count["siglay"] <- 1
      } else if ("z" %in% temp_dims) {
        start["z"] <- 1
        count["z"] <- 1
      } else if ("depth" %in% temp_dims) {
        start["depth"] <- 1
        count["depth"] <- 1
      }

      # Select nearest node
      if ("node" %in% temp_dims) {
        start["node"] <- nearest_node
        count["node"] <- 1
      } else if ("nodes" %in% temp_dims) {
        start["nodes"] <- nearest_node
        count["nodes"] <- 1
      } else {
        stop("Could not find node/nodes dimension in temp variable.")
      }

      # Read only one value rather than the full temp array.
      temp_value <- ncdf4::ncvar_get(
        nc,
        "temp",
        start = as.integer(start),
        count = as.integer(count)
      )

      temp_value <- as.numeric(temp_value)[1]

      # Read actual valid time from numeric NetCDF time variable.
      datetime_value <- read_valid_time_from_open_nc(nc, nc_path)

      # Optional diagnostics
      filename_time <- parse_leofs_filename_time(nc_path)
      times_time <- read_times_char_variable(nc)

      data.frame(
        datetime = as.POSIXct(datetime_value, tz = "UTC"),
        temp_surface_point = temp_value,
        file = basename(nc_path),
        filename_time = as.POSIXct(filename_time, tz = "UTC"),
        times_char_time = as.POSIXct(times_time, tz = "UTC"),
        filename_minus_datetime_hours = as.numeric(
          difftime(filename_time, datetime_value, units = "hours")
        ),
        stringsAsFactors = FALSE
      )
    },
    error = function(e) {
      warning(
        paste0(
          "Failed to process file: ",
          basename(nc_path),
          "\nError: ",
          e$message
        )
      )

      data.frame(
        datetime = as.POSIXct(parse_leofs_filename_time(nc_path), tz = "UTC"),
        temp_surface_point = NA_real_,
        file = basename(nc_path),
        filename_time = as.POSIXct(parse_leofs_filename_time(nc_path), tz = "UTC"),
        times_char_time = as.POSIXct(NA, tz = "UTC"),
        filename_minus_datetime_hours = NA_real_,
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
# Extract model time series
# -------------------------------------------------------------------

cat("Extracting surface temperature at nearest node from all files...\n")

model_list <- vector("list", length(glofs_files))

for (i in seq_along(glofs_files)) {
  if (i %% 20 == 0 || i == 1 || i == length(glofs_files)) {
    cat(
      "Processing file",
      i,
      "of",
      length(glofs_files),
      ":",
      basename(glofs_files[i]),
      "\n"
    )
  }

  model_list[[i]] <- extract_surface_temp_point(
    nc_path = glofs_files[i],
    nearest_node = nearest_node
  )
}

# Safety check before binding
bad_items <- !vapply(model_list, is.data.frame, logical(1))

if (any(bad_items)) {
  warning(
    "Some model_list entries are not data frames. Bad entries: ",
    paste(which(bad_items), collapse = ", ")
  )

  model_list <- model_list[!bad_items]
}

model_ts <- dplyr::bind_rows(model_list) %>%
  arrange(datetime)

cat("\nModel time series preview:\n")
print(head(model_ts))
cat("\n")
print(tail(model_ts))

cat("\nSummary of extracted surface temperature:\n")
print(summary(model_ts$temp_surface_point))

if (all(is.na(model_ts$temp_surface_point))) {
  warning(
    "All extracted temp_surface_point values are NA. ",
    "Check warnings(), nearest node, and NetCDF variable metadata."
  )
}

cat("\nSummary of filename-derived time minus NetCDF datetime, hours:\n")
print(summary(model_ts$filename_minus_datetime_hours))

# -------------------------------------------------------------------
# Save extracted model time series
# -------------------------------------------------------------------

write.csv(
  model_ts,
  file.path(output_dir, paste0(systemname, "_surface_temp_buoy_", buoy_id, ".csv")),
  row.names = FALSE
)

# -------------------------------------------------------------------
# Quick plot of extracted model time series
# -------------------------------------------------------------------

p_model_temp <- ggplot(model_ts, aes(x = datetime, y = temp_surface_point)) +
  geom_line(color = "firebrick", linewidth = 0.5, na.rm = TRUE) +
  scale_x_datetime(
    timezone = "UTC",
    date_labels = "%b %d\n%H:%M UTC"
  ) +
  labs(
    x = "Date/time, UTC",
    y = "Water temperature (°C)",
    title = paste("LEOFS surface temperature at nearest node to buoy", buoy_id)
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold")
  )

print(p_model_temp)

ggsave(
  filename = file.path(
    fig_dir,
    paste0(systemname, "_surface_temp_nearest_buoy_", buoy_id, ".png")
  ),
  plot = p_model_temp,
  width = 9,
  height = 4.5,
  dpi = 300
)

# -------------------------------------------------------------------
# Optional one-file diagnostic
# -------------------------------------------------------------------
# Uncomment these lines if you want to inspect one file manually.
#
# test_file <- file.path(
#   glofs_dir,
#   "leofs.t00z.20250604.fields.n002.nc"
# )
#
# if (file.exists(test_file)) {
#   test_result <- extract_surface_temp_point(
#     nc_path = test_file,
#     nearest_node = nearest_node
#   )
#   print(test_result)
# }


