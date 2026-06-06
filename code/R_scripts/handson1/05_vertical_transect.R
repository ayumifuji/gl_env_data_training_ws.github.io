# 05_vertical_transect.R
# Optional vertical transect of temperature.
# No sf dependency.

# -------------------------------------------------------------------
# User-defined transect settings
# -------------------------------------------------------------------

start_lon <- -83.2
start_lat <- 42.1

end_lon <- -78.9
end_lat <- 42.9

ntransect <- 300
nlevels <- 30

# -------------------------------------------------------------------
# Interpolation helper
# -------------------------------------------------------------------

interp_with_nearest_fallback <- function(points, values, xi) {
  # points: n x 2 matrix of source lon/lat
  # values: length n vector of source values
  # xi: m x 2 matrix of target lon/lat

  ok <- is.finite(points[, 1]) &
    is.finite(points[, 2]) &
    is.finite(values)

  points_ok <- points[ok, , drop = FALSE]
  values_ok <- values[ok]

  # Linear interpolation
  lin <- interp::interpp(
    x = points_ok[, 1],
    y = points_ok[, 2],
    z = values_ok,
    xo = xi[, 1],
    yo = xi[, 2],
    linear = TRUE,
    extrap = FALSE,
    duplicate = "mean"
  )$z

  out <- lin

  # Nearest-neighbor fallback where linear interpolation gives NA
  bad <- !is.finite(out)

  if (any(bad)) {
    nn <- FNN::get.knnx(
      data = points_ok,
      query = xi[bad, , drop = FALSE],
      k = 1
    )$nn.index[, 1]

    out[bad] <- values_ok[nn]
  }

  out
}

# -------------------------------------------------------------------
# Create transect points
# -------------------------------------------------------------------

transect_lon <- seq(start_lon, end_lon, length.out = ntransect)
transect_lat <- seq(start_lat, end_lat, length.out = ntransect)

node_points <- cbind(lon_node, lat_node)
transect_points <- cbind(transect_lon, transect_lat)

# Distance along transect, km
dist_m <- numeric(ntransect)

for (i in 2:ntransect) {
  dist_m[i] <- dist_m[i - 1] + geosphere::distGeo(
    p1 = c(transect_lon[i - 1], transect_lat[i - 1]),
    p2 = c(transect_lon[i], transect_lat[i])
  )
}

dist_km <- dist_m / 1000

# -------------------------------------------------------------------
# Extract variables
# -------------------------------------------------------------------

temp <- get_3d_time_siglay_node(nc, "temp", time_index = nindex)
temp <- matrix(as.numeric(temp), nrow = nrow(temp), ncol = ncol(temp))

h <- as.numeric(ncdf4::ncvar_get(nc, "h"))
zeta <- get_2d_time_node(nc, "zeta", time_index = nindex)

nsiglay <- nrow(temp)

siglay_mat <- get_siglay_matrix(nc, n_nodes)

# Compute vertical coordinate at nodes for every sigma layer.
# z_node has shape nsiglay x node.
z_node <- sweep(siglay_mat, 2, h + zeta, `*`)
z_node <- sweep(z_node, 2, zeta, `+`)

# Interpolate bathymetry and free surface along transect
h_transect <- interp_with_nearest_fallback(node_points, h, transect_points)
zeta_transect <- interp_with_nearest_fallback(node_points, zeta, transect_points)

# Interpolate temperature and vertical coordinate onto transect
temp_transect <- matrix(NA_real_, nrow = nsiglay, ncol = ntransect)
z_transect <- matrix(NA_real_, nrow = nsiglay, ncol = ntransect)

for (k in seq_len(nsiglay)) {
  temp_transect[k, ] <- interp_with_nearest_fallback(
    node_points,
    temp[k, ],
    transect_points
  )

  z_transect[k, ] <- interp_with_nearest_fallback(
    node_points,
    z_node[k, ],
    transect_points
  )
}

# Add surface and bottom rows, matching the Python notebook.
z_surface <- matrix(zeta_transect, nrow = 1)
z_bottom <- matrix(-1 * h_transect, nrow = 1)

z_plot <- rbind(
  z_surface,
  z_transect,
  z_bottom
)

temp_plot <- rbind(
  temp_transect[1, , drop = FALSE],
  temp_transect,
  temp_transect[nsiglay, , drop = FALSE]
)

cat("z_plot dimensions:", dim(z_plot), "\n")
cat("temp_plot dimensions:", dim(temp_plot), "\n")


# -------------------------------------------------------------------
# Plot vertical transect using sigma-layer polygons
# -------------------------------------------------------------------
# This approach is more faithful to the FVCOM sigma-coordinate structure
# than interpolating onto a regular distance-depth grid.

n_z <- nrow(z_plot)
n_x <- ncol(z_plot)

polygon_list <- list()
counter <- 1

for (i in seq_len(n_x - 1)) {
  for (k in seq_len(n_z - 1)) {

    x1 <- dist_km[i]
    x2 <- dist_km[i + 1]

    z11 <- z_plot[k, i]
    z12 <- z_plot[k, i + 1]
    z22 <- z_plot[k + 1, i + 1]
    z21 <- z_plot[k + 1, i]

    t11 <- temp_plot[k, i]
    t12 <- temp_plot[k, i + 1]
    t22 <- temp_plot[k + 1, i + 1]
    t21 <- temp_plot[k + 1, i]

    if (
      all(is.finite(c(x1, x2, z11, z12, z22, z21, t11, t12, t22, t21))) &&
      abs(mean(c(z11, z12)) - mean(c(z21, z22))) > 1e-6
    ) {

      polygon_list[[counter]] <- data.frame(
        cell_id = counter,
        dist_km = c(x1, x2, x2, x1),
        z = c(z11, z12, z22, z21),
        temp = mean(c(t11, t12, t22, t21), na.rm = TRUE)
      )

      counter <- counter + 1
    }
  }
}

transect_poly_df <- dplyr::bind_rows(polygon_list)

surface_df <- data.frame(
  dist_km = dist_km,
  zeta = zeta_transect
)

bottom_df <- data.frame(
  dist_km = dist_km,
  bottom = -h_transect
)

p_transect <- ggplot() +
  geom_polygon(
    data = transect_poly_df,
    aes(
      x = dist_km,
      y = z,
      group = cell_id,
      fill = temp
    ),
    color = NA
  ) +
  geom_line(
    data = surface_df,
    aes(x = dist_km, y = zeta),
    color = "black",
    linewidth = 0.5,
    linetype = "dashed"
  ) +
  geom_line(
    data = bottom_df,
    aes(x = dist_km, y = bottom),
    color = "black",
    linewidth = 0.7
  ) +
  scale_fill_viridis_c(
    option = "turbo",
    name = "Water\ntemperature"
  ) +
  labs(
    x = "Distance along transect [km]",
    y = "Elevation [m]",
    title = "Vertical transect of water temperature"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold")
  )

print(p_transect)


# Save a figure
ggsave(
  file.path(fig_dir, "vertical_temperature_transect.png"),
  plot = p_transect,
  width = 10,
  height = 5,
  dpi = 300
)



