# 02_mesh_helpers.R
# Helper functions for reading FVCOM mesh variables and preparing plot data.
# No sf-dependent code.

# -------------------------------------------------------------------
# Longitude helper
# -------------------------------------------------------------------

wrap_lon <- function(lon) {
  ((lon + 180) %% 360) - 180
}

# -------------------------------------------------------------------
# NetCDF dimension helpers
# -------------------------------------------------------------------

var_dim_names <- function(nc, varname) {
  sapply(nc$var[[varname]]$dim, function(x) x$name)
}

orient_array <- function(nc, varname, desired_dims) {
  arr <- ncdf4::ncvar_get(
    nc,
    varname,
    collapse_degen = FALSE
  )

  current_dims <- var_dim_names(nc, varname)

  if (!all(desired_dims %in% current_dims)) {
    stop(sprintf(
      "Variable '%s' does not contain desired dims: %s. Actual dims: %s",
      varname,
      paste(desired_dims, collapse = ", "),
      paste(current_dims, collapse = ", ")
    ))
  }

  perm <- match(desired_dims, current_dims)

  if (length(dim(arr)) != length(current_dims)) {
    stop(sprintf(
      "Unexpected number of dimensions for variable '%s'. Expected %d, got %d.",
      varname,
      length(current_dims),
      length(dim(arr))
    ))
  }

  aperm(arr, perm)
}

get_2d_time_node <- function(nc, varname, time_index = 1) {
  arr <- orient_array(nc, varname, c("time", "node"))
  as.numeric(arr[time_index, ])
}

get_3d_time_siglay_node <- function(nc, varname, time_index = 1) {
  arr <- orient_array(nc, varname, c("time", "siglay", "node"))
  arr[time_index, , ]
}

get_3d_time_siglay_nele <- function(nc, varname, time_index = 1) {
  arr <- orient_array(nc, varname, c("time", "siglay", "nele"))
  arr[time_index, , ]
}


get_siglay_matrix <- function(nc, n_nodes) {
  # Robustly read FVCOM sigma-layer coordinates.
  #
  # Goal: return a matrix with shape:
  #   nsiglay x node
  #
  # FVCOM/GLOFS files may store siglay as:
  #   1. a vector of length nsiglay
  #   2. a matrix siglay x node
  #   3. a matrix node x siglay
  #   4. a dimension variable rather than a normal nc$var entry

  siglay_raw <- ncdf4::ncvar_get(
    nc,
    "siglay",
    collapse_degen = FALSE
  )

  raw_dim <- dim(siglay_raw)

  # Try to get nsiglay length from the NetCDF dimensions
  if ("siglay" %in% names(nc$dim)) {
    nsiglay_from_dim <- nc$dim[["siglay"]]$len
  } else {
    nsiglay_from_dim <- NA_integer_
  }

  # Case 1: siglay is a vector
  if (is.null(raw_dim)) {
    siglay_vec <- as.numeric(siglay_raw)

    siglay_mat <- matrix(
      siglay_vec,
      nrow = length(siglay_vec),
      ncol = n_nodes,
      byrow = FALSE
    )

    return(siglay_mat)
  }

  # Remove length-1 dimensions if present
  squeezed <- drop(siglay_raw)
  squeezed_dim <- dim(squeezed)

  # Case 2: after dropping singleton dims, siglay becomes a vector
  if (is.null(squeezed_dim)) {
    siglay_vec <- as.numeric(squeezed)

    siglay_mat <- matrix(
      siglay_vec,
      nrow = length(siglay_vec),
      ncol = n_nodes,
      byrow = FALSE
    )

    return(siglay_mat)
  }

  # Case 3: siglay is a matrix
  if (length(squeezed_dim) == 2) {
    nr <- squeezed_dim[1]
    nc2 <- squeezed_dim[2]

    # If one dimension is node, the other is siglay
    if (nc2 == n_nodes) {
      # Already nsiglay x node
      siglay_mat <- squeezed
    } else if (nr == n_nodes) {
      # node x nsiglay; transpose to nsiglay x node
      siglay_mat <- t(squeezed)
    } else if (!is.na(nsiglay_from_dim) && nr == nsiglay_from_dim) {
      # likely nsiglay x something
      siglay_mat <- squeezed
    } else if (!is.na(nsiglay_from_dim) && nc2 == nsiglay_from_dim) {
      # likely something x nsiglay
      siglay_mat <- t(squeezed)
    } else {
      stop(
        paste0(
          "Could not interpret siglay matrix dimensions. ",
          "Read dimensions were: ",
          paste(squeezed_dim, collapse = " x "),
          ". n_nodes = ",
          n_nodes,
          ", nsiglay dimension length = ",
          nsiglay_from_dim
        )
      )
    }

    # If siglay is only nsiglay x 1, repeat across nodes
    if (ncol(siglay_mat) == 1 && n_nodes > 1) {
      siglay_mat <- matrix(
        siglay_mat[, 1],
        nrow = nrow(siglay_mat),
        ncol = n_nodes,
        byrow = FALSE
      )
    }

    return(siglay_mat)
  }

  stop(
    paste0(
      "Could not interpret siglay. Raw dimensions were: ",
      paste(raw_dim, collapse = " x ")
    )
  )
}


# -------------------------------------------------------------------
# Read core mesh variables
# -------------------------------------------------------------------

lon_node <- wrap_lon(ncdf4::ncvar_get(nc, "lon"))
lat_node <- ncdf4::ncvar_get(nc, "lat")

lonc <- wrap_lon(ncdf4::ncvar_get(nc, "lonc"))
latc <- ncdf4::ncvar_get(nc, "latc")

# FVCOM connectivity.
# In Python, nv was converted from 1-based to 0-based.
# R is already 1-based, so we keep the node IDs as-is.
nv_raw <- ncdf4::ncvar_get(nc, "nv")
nv_dims <- var_dim_names(nc, "nv")

if (all(c("three", "nele") %in% nv_dims)) {
  nv_oriented <- orient_array(nc, "nv", c("three", "nele"))
  triangles <- t(nv_oriented)
} else {
  # Fallback assumption: rows or columns contain the three node IDs.
  if (nrow(nv_raw) == 3) {
    triangles <- t(nv_raw)
  } else if (ncol(nv_raw) == 3) {
    triangles <- nv_raw
  } else {
    stop("Could not interpret nv connectivity array.")
  }
}

triangles <- round(triangles)
storage.mode(triangles) <- "integer"

n_nodes <- length(lon_node)
n_elements <- nrow(triangles)

cat("Number of nodes:", n_nodes, "\n")
cat("Number of elements:", n_elements, "\n")

# -------------------------------------------------------------------
# Triangle polygon helpers
# -------------------------------------------------------------------

make_triangle_polygon_df <- function(lon, lat, triangles, tri_value = NULL) {
  ntri <- nrow(triangles)

  if (is.null(tri_value)) {
    tri_value <- rep(NA_real_, ntri)
  }

  out <- vector("list", ntri)

  for (i in seq_len(ntri)) {
    node_ids <- triangles[i, ]

    out[[i]] <- data.frame(
      element = i,
      vertex = 1:3,
      lon = lon[node_ids],
      lat = lat[node_ids],
      value = tri_value[i]
    )
  }

  dplyr::bind_rows(out)
}

node_values_to_triangle_values <- function(node_values, triangles) {
  apply(triangles, 1, function(idx) {
    mean(node_values[idx], na.rm = TRUE)
  })
}
