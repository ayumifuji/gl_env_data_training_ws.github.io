# 02_buoy_observations.R
# Download, read, and plot NDBC buoy observations.

# -------------------------------------------------------------------
# Download buoy file
# -------------------------------------------------------------------

buoy_filename_txt <- sprintf("%sh%d.txt", buoy_id, buoy_year)
buoy_filename_gz  <- paste0(buoy_filename_txt, ".gz")

buoy_url <- sprintf(
  "https://www.ndbc.noaa.gov/data/historical/stdmet/%s",
  buoy_filename_gz
)

buoy_gz_path <- file.path(buoy_dir, buoy_filename_gz)
buoy_txt_path <- file.path(buoy_dir, buoy_filename_txt)

if (!file.exists(buoy_gz_path) && !file.exists(buoy_txt_path)) {
  cat("Downloading buoy data:\n", buoy_url, "\n")

  download.file(
    buoy_url,
    buoy_gz_path,
    mode = "wb",
    quiet = FALSE
  )
} else {
  cat("Buoy file already exists locally. Skipping download.\n")
}

# -------------------------------------------------------------------
# Read buoy data
# -------------------------------------------------------------------

cols <- c(
  "YY", "MM", "DD", "hh", "mm",
  "WDIR", "WSPD", "GST", "WVHT", "DPD", "APD", "MWD",
  "PRES", "ATMP", "WTMP", "DEWP", "VIS", "TIDE"
)

# Read directly from gz if needed
if (file.exists(buoy_txt_path)) {
  buoy_connection <- buoy_txt_path
} else {
  buoy_connection <- gzfile(buoy_gz_path, open = "rt")
}

buoy_raw <- read.table(
  buoy_connection,
  comment.char = "#",
  header = FALSE,
  col.names = cols,
  na.strings = c("99", "99.0", "999", "999.0", "9999", "9999.0"),
  fill = TRUE
)

if (inherits(buoy_connection, "connection")) {
  close(buoy_connection)
}

cat("Below is the original buoy data frame:\n")
print(head(buoy_raw))
cat("\n")

# Build datetime column in UTC
buoy_df <- buoy_raw %>%
  mutate(
    datetime = as.POSIXct(
      sprintf(
        "%04d-%02d-%02d %02d:%02d:00",
        YY, MM, DD, hh, mm
      ),
      tz = "UTC"
    )
  ) %>%
  select(datetime, everything(), -YY, -MM, -DD, -hh, -mm)

cat("Below is the buoy data frame with datetime column:\n")
print(head(buoy_df))

# -------------------------------------------------------------------
# Plot buoy water temperature
# -------------------------------------------------------------------

p_buoy_wtmp <- ggplot(buoy_df, aes(x = datetime, y = WTMP)) +
  geom_line(color = "steelblue", linewidth = 0.4) +
  labs(
    x = "Date/time, UTC",
    y = "Water temperature (°C)",
    title = paste("NDBC buoy", buoy_id, "water temperature")
  ) +
  theme_minimal()

print(p_buoy_wtmp)

ggsave(
  filename = file.path(fig_dir, paste0("buoy_", buoy_id, "_WTMP_timeseries.png")),
  plot = p_buoy_wtmp,
  width = 9,
  height = 4.5,
  dpi = 300
)
