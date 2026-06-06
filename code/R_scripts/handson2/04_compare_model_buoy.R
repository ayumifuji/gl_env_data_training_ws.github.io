# 04_compare_model_buoy.R
# Compare LEOFS model output with buoy observations.

if (!exists("model_ts")) {
  model_csv <- file.path(
    output_dir,
    paste0(systemname, "_surface_temp_buoy_", buoy_id, ".csv")
  )

  if (!file.exists(model_csv)) {
    stop("model_ts not found and model CSV does not exist. Run 03_extract_leofs_timeseries.R first.")
  }

  model_ts <- read.csv(model_csv)
  model_ts$datetime <- as.POSIXct(model_ts$datetime, tz = "UTC")
}

if (!exists("buoy_df")) {
  stop("buoy_df not found. Run 02_buoy_observations.R first.")
}

plot_start <- min(model_ts$datetime, na.rm = TRUE)
plot_end <- max(model_ts$datetime, na.rm = TRUE)

# Restrict buoy data to model period for plotting
buoy_plot_df <- buoy_df %>%
  filter(datetime >= plot_start, datetime <= plot_end)

model_plot_df <- model_ts %>%
  transmute(
    datetime = datetime,
    temperature = temp_surface_point,
    dataset = "LEOFS"
  )

buoy_label <- paste0("Buoy ", buoy_id)

buoy_plot_df2 <- buoy_plot_df %>%
  transmute(
    datetime = datetime,
    temperature = WTMP,
    dataset = buoy_label
  )

comparison_df <- bind_rows(model_plot_df, buoy_plot_df2)

# Named color vector.
# Use setNames() because dynamic names like paste0(...) cannot be used
# directly on the left side of "=" inside c().
comparison_colors <- setNames(
  c("firebrick", "steelblue"),
  c("LEOFS", buoy_label)
)

p_model_buoy <- ggplot(
  comparison_df,
  aes(x = datetime, y = temperature, color = dataset)
) +
  geom_line(linewidth = 0.6, na.rm = TRUE) +
  coord_cartesian(
    xlim = c(plot_start, plot_end),
    ylim = comparison_ylim
  ) +
    scale_x_datetime(
    timezone = "UTC",
    date_labels = "%b %d\n%H:%M UTC"
  ) +		       
  scale_color_manual(values = comparison_colors) +
  labs(
    x = "Date/time, UTC",
    y = "Water temperature (°C)",
    color = NULL,
    title = paste("LEOFS vs. NDBC buoy", buoy_id, "water temperature")
  ) +
  theme_minimal() +
  theme(
    legend.position = "bottom",
    plot.title = element_text(face = "bold")
  )

print(p_model_buoy)

ggsave(
  filename = file.path(
    fig_dir,
    paste0("comparison_", systemname, "_buoy_", buoy_id, ".png")
  ),
  plot = p_model_buoy,
  width = 10,
  height = 5,
  dpi = 300
)

# -------------------------------------------------------------------
# Optional simple difference calculation
# -------------------------------------------------------------------
# Match buoy observations to nearest model hour by rounding buoy time
# to the nearest hour. This is not in the original notebook, but useful
# for quick bias/error diagnostics.

buoy_hourly <- buoy_plot_df %>%
  mutate(datetime_hour = lubridate::round_date(datetime, unit = "hour")) %>%
  group_by(datetime_hour) %>%
  summarize(
    buoy_wtmp = mean(WTMP, na.rm = TRUE),
    .groups = "drop"
  )

model_hourly <- model_ts %>%
  mutate(datetime_hour = lubridate::round_date(datetime, unit = "hour")) %>%
  group_by(datetime_hour) %>%
  summarize(
    model_temp = mean(temp_surface_point, na.rm = TRUE),
    .groups = "drop"
  )

matched_df <- inner_join(model_hourly, buoy_hourly, by = "datetime_hour") %>%
  mutate(
    model_minus_buoy = model_temp - buoy_wtmp
  )

if (nrow(matched_df) > 0) {
  cat("\nSimple model-minus-buoy diagnostics, matched to nearest hour:\n")
  cat("Mean bias, model - buoy:", mean(matched_df$model_minus_buoy, na.rm = TRUE), "°C\n")
  cat("RMSE:", sqrt(mean(matched_df$model_minus_buoy^2, na.rm = TRUE)), "°C\n")

  write.csv(
    matched_df,
    file.path(output_dir, paste0("matched_model_buoy_", buoy_id, ".csv")),
    row.names = FALSE
  )
}



