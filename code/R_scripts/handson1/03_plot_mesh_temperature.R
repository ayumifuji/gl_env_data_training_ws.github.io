# 03_plot_mesh_temperature.R
# Plot FVCOM triangular mesh and lake surface temperature.
# No sf, no ggspatial, no basemap.

# -------------------------------------------------------------------
# 3.1 Plot triangular mesh
# -------------------------------------------------------------------

mesh_df <- make_triangle_polygon_df(lon_node, lat_node, triangles)

p_mesh <- ggplot(mesh_df, aes(x = lon, y = lat, group = element)) +
  geom_polygon(fill = NA, color = "black", linewidth = 0.15) +
  coord_equal() +
  labs(
    x = "Longitude",
    y = "Latitude",
    title = "FVCOM triangular mesh, node-based"
  ) +
  theme_minimal()

print(p_mesh)

# -------------------------------------------------------------------
# Zoomed western Lake Erie mesh
# -------------------------------------------------------------------

p_mesh_zoom <- ggplot(mesh_df, aes(x = lon, y = lat, group = element)) +
  geom_polygon(fill = NA, color = "black", linewidth = 0.12, alpha = 0.8) +
  coord_equal(
    xlim = c(bbox_ll["minlon"], bbox_ll["maxlon"]),
    ylim = c(bbox_ll["minlat"], bbox_ll["maxlat"]),
    expand = FALSE
  ) +
  labs(
    x = "Longitude",
    y = "Latitude",
    title = "FVCOM triangular mesh, western Lake Erie"
  ) +
  theme_minimal()

print(p_mesh_zoom)

# -------------------------------------------------------------------
# 3.2 Plot lake surface temperature
# -------------------------------------------------------------------

temp_time_sig_node <- get_3d_time_siglay_node(nc, "temp", time_index = nindex)

# Surface layer.
# Python used siglay = 0, which corresponds to R index 1.
temp_surface <- as.numeric(temp_time_sig_node[1, ])

temp_tri <- node_values_to_triangle_values(temp_surface, triangles)

temp_df <- make_triangle_polygon_df(
  lon = lon_node,
  lat = lat_node,
  triangles = triangles,
  tri_value = temp_tri
)

# Simple full-domain temperature plot
p_temp_simple <- ggplot(
  temp_df,
  aes(x = lon, y = lat, group = element, fill = value)
) +
  geom_polygon(color = NA) +
  coord_equal() +
  scale_fill_viridis_c(option = "turbo", name = "Temperature\n°C") +
  labs(
    x = "Longitude",
    y = "Latitude",
    title = "FVCOM lake surface temperature"
  ) +
  theme_minimal()

print(p_temp_simple)

# Zoomed western Lake Erie temperature plot
p_temp_zoom <- ggplot() +
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
    alpha = 0.6
  ) +
  coord_equal(
    xlim = c(bbox_ll["minlon"], bbox_ll["maxlon"]),
    ylim = c(bbox_ll["minlat"], bbox_ll["maxlat"]),
    expand = FALSE
  ) +
  scale_fill_viridis_c(option = "turbo", name = "Temperature\n°C") +
  labs(
    x = "Longitude",
    y = "Latitude",
    title = "FVCOM lake surface temperature, western Lake Erie"
  ) +
  theme_minimal() +
  theme(
    legend.position = "right",
    plot.title = element_text(face = "bold")
  )

print(p_temp_zoom)


# Save figures
ggsave(
  file.path(fig_dir, "mesh_full_domain.png"),
  plot = p_mesh,
  width = 8,
  height = 6,
  dpi = 300
)

ggsave(
  file.path(fig_dir, "mesh_western_lake_erie.png"),
  plot = p_mesh_zoom,
  width = 8,
  height = 6,
  dpi = 300
)

ggsave(
  file.path(fig_dir, "surface_temperature_full_domain.png"),
  plot = p_temp_simple,
  width = 8,
  height = 6,
  dpi = 300
)

ggsave(
  file.path(fig_dir, "surface_temperature_western_lake_erie.png"),
  plot = p_temp_zoom,
  width = 8,
  height = 6,
  dpi = 300
)
