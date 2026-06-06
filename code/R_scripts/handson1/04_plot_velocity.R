# 04_plot_velocity.R
# Overlay surface velocity vectors on surface temperature.
# No sf, no ggspatial, no basemap.

# This script assumes temp_df and mesh_df were created by:
# source("03_plot_mesh_temperature.R")

u_time_sig_nele <- get_3d_time_siglay_nele(nc, "u", time_index = nindex)
v_time_sig_nele <- get_3d_time_siglay_nele(nc, "v", time_index = nindex)

# Surface layer
u_surf <- as.numeric(u_time_sig_nele[1, ])
v_surf <- as.numeric(v_time_sig_nele[1, ])

minlon <- bbox_ll["minlon"]
minlat <- bbox_ll["minlat"]
maxlon <- bbox_ll["maxlon"]
maxlat <- bbox_ll["maxlat"]

mask <- lonc >= minlon &
  lonc <= maxlon &
  latc >= minlat &
  latc <= maxlat &
  is.finite(u_surf) &
  is.finite(v_surf)

idx <- which(mask)

# Thin vectors so the plot is not too crowded.
# Increase skip for fewer arrows; decrease for more arrows.
skip <- 5

if (length(idx) > 0) {
  idx <- idx[seq(1, length(idx), by = skip)]
} else {
  warning("No velocity vectors found inside the selected bounding box.")
}

velocity_df <- data.frame(
  lon = lonc[idx],
  lat = latc[idx],
  u = u_surf[idx],
  v = v_surf[idx]
)

# Visual scaling factor for arrows in lon/lat coordinates.
# Adjust if arrows look too long or too short.
arrow_scale <- 0.15

velocity_df <- velocity_df %>%
  mutate(
    lon_end = lon + u * arrow_scale,
    lat_end = lat + v * arrow_scale
  )

p_velocity <- ggplot() +
  geom_polygon(
    data = temp_df,
    aes(x = lon, y = lat, group = element, fill = value),
    color = NA,
    alpha = 0.95
  ) +
  geom_polygon(
    data = mesh_df,
    aes(x = lon, y = lat, group = element),
    fill = NA,
    color = "white",
    linewidth = 0.10,
    alpha = 0.5
  ) +
  geom_segment(
    data = velocity_df,
    aes(x = lon, y = lat, xend = lon_end, yend = lat_end),
    color = "cyan4",
    linewidth = 0.35,
    alpha = 0.9,
    arrow = arrow(length = unit(0.08, "inches"))
  ) +
  coord_equal(
    xlim = c(minlon, maxlon),
    ylim = c(minlat, maxlat),
    expand = FALSE
  ) +
  scale_fill_viridis_c(option = "turbo", name = "Temperature\n°C") +
  labs(
    x = "Longitude",
    y = "Latitude",
    title = "FVCOM lake surface temperature and surface current"
  ) +
  theme_minimal() +
  theme(
    legend.position = "right",
    plot.title = element_text(face = "bold")
  )

print(p_velocity)

# Save figure
ggsave(
  file.path(fig_dir, "surface_temperature_velocity.png"),
  plot = p_velocity,
  width = 8,
  height = 6,
  dpi = 300
)


