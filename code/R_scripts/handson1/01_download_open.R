# 01_download_open.R
# Download NOAA GLOFS NetCDF file and inspect contents.

# NOAA public S3 bucket can be accessed directly over HTTPS.
bucket_url <- "https://noaa-nos-ofs-pds.s3.amazonaws.com"

key <- sprintf(
  "%s/netcdf/%s/%s/%s/%s",
  systemname, yearstr, monstr, daystr, filename
)

file_url <- sprintf("%s/%s", bucket_url, key)

cat("NOAA file URL:\n", file_url, "\n\n")
cat("Local save path:\n", save_path, "\n\n")

if (!file.exists(save_path)) {
  cat("Downloading file...\n")

  tryCatch(
    {
      download.file(file_url, save_path, mode = "wb")
      cat("Download complete.\n\n")
    },
    error = function(e) {
      stop(
        paste0(
          "Download failed. Please check that the date/system exists on NOAA S3.\n",
          "URL attempted:\n",
          file_url,
          "\n\nOriginal error:\n",
          e$message
        )
      )
    }
  )

} else {
  cat("File already exists locally. Skipping download.\n\n")
}

# Open NetCDF file
nc <- ncdf4::nc_open(save_path)

cat("------------------------------------\n")

# Helper to safely get a variable
get_nc_var <- function(nc, varname) {
  if (!varname %in% names(nc$var)) {
    stop(sprintf("Variable '%s' not found in NetCDF file.", varname))
  }
  ncdf4::ncvar_get(nc, varname)
}

# Print initial time if available
if ("time" %in% names(nc$var)) {
  time_vals <- ncdf4::ncvar_get(nc, "time")
  time_units <- ncdf4::ncatt_get(nc, "time", "units")$value

  cat("initial time raw value:", time_vals[1], "\n")
  cat("time units:", time_units, "\n")
}

# Print selected variable dimensions
for (v in c("zeta", "u", "temp")) {
  if (v %in% names(nc$var)) {
    dims <- sapply(nc$var[[v]]$dim, function(x) x$name)
    lens <- sapply(nc$var[[v]]$dim, function(x) x$len)

    cat(sprintf(
      "%s: dims = %s; shape = %s\n",
      v,
      paste(dims, collapse = ", "),
      paste(lens, collapse = " x ")
    ))
  }
}

cat("------------------------------------\n\n")

# Print long names of all variables
all_var_names <- names(nc$var)

for (var in all_var_names) {
  dims <- sapply(nc$var[[var]]$dim, function(x) x$name)
  long_name <- ncdf4::ncatt_get(nc, var, "long_name")$value

  if (is.null(long_name) || is.na(long_name)) {
    long_name <- "No long_name attribute"
  }

  cat(sprintf(
    "%-20s dims: %-35s long_name: %s\n",
    var,
    paste(dims, collapse = ", "),
    long_name
  ))
}

