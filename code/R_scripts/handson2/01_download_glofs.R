# 01_download_glofs.R
# Download multiple hourly GLOFS/LEOFS NetCDF files from NOAA public S3.

bucket_url <- "https://noaa-nos-ofs-pds.s3.amazonaws.com"

download_one_glofs_file <- function(systemname, date, cycle, hour, glofs_dir) {
  yearstr <- format(date, "%Y")
  monstr  <- format(date, "%m")
  daystr  <- format(date, "%d")
  ymdstr  <- format(date, "%Y%m%d")

  filename <- sprintf(
    "%s.t%02dz.%s.fields.n%03d.nc",
    systemname,
    cycle,
    ymdstr,
    hour
  )

  key <- sprintf(
    "%s/netcdf/%s/%s/%s/%s",
    systemname,
    yearstr,
    monstr,
    daystr,
    filename
  )

  url <- sprintf("%s/%s", bucket_url, key)
  local_path <- file.path(glofs_dir, filename)

  if (file.exists(local_path)) {
    cat("Already exists, skipping:", filename, "\n")
    return(local_path)
  }

  cat("Downloading:", key, "\n")

  ok <- tryCatch(
    {
      download.file(url, local_path, mode = "wb", quiet = TRUE)
      TRUE
    },
    error = function(e) {
      warning(
        paste0(
          "Failed to download: ", filename, "\n",
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

# Download 7-day period, hourly files:
# cycles 00, 06, 12, 18 and nowcast hours n000-n005.
dates <- seq(start_date, end_date, by = "day")

downloaded_files <- c()

for (i_date in seq_along(dates)) {
  date <- dates[i_date]

  for (cycle in seq(0, 18, by = 6)) {
    for (hour in 0:5) {
      f <- download_one_glofs_file(
        systemname = systemname,
        date = date,
        cycle = cycle,
        hour = hour,
        glofs_dir = glofs_dir
      )

      downloaded_files <- c(downloaded_files, f)
    }
  }
}

downloaded_files <- downloaded_files[!is.na(downloaded_files)]

cat("\nDownloaded/found", length(downloaded_files), "GLOFS files.\n")
cat("GLOFS directory:", glofs_dir, "\n\n")

# List files
glofs_files_on_disk <- list.files(
  glofs_dir,
  pattern = paste0("^", systemname, "\\.t[0-9]{2}z\\.[0-9]{8}\\.fields\\.n[0-9]{3}\\.nc$"),
  full.names = TRUE
)

cat("Files currently in GLOFS directory:", length(glofs_files_on_disk), "\n")
print(head(basename(glofs_files_on_disk)))

