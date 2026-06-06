# 00_setup.R
# Package setup, configuration, and user parameters.
# No sf, no ggspatial, no web basemap dependencies.

required_packages <- c(
  "ncdf4",
  "ggplot2",
  "dplyr",
  "viridis",
  "interp",
  "FNN",
  "geosphere",
  "grid"
)

installed <- rownames(installed.packages())
to_install <- setdiff(required_packages, installed)

if (length(to_install) > 0) {
  install.packages(to_install)
}

library(ncdf4)
library(ggplot2)
library(dplyr)
library(viridis)
library(interp)
library(FNN)
library(geosphere)
library(grid)

# -------------------------------------------------------------------
# User settings
# -------------------------------------------------------------------

# Local folder for downloaded NOAA files
save_dir <- file.path(getwd(), "GL_env_data", "handson1")

if (!dir.exists(save_dir)) {
  dir.create(save_dir, recursive = TRUE)
}

cat("Files will be saved in:", save_dir, "\n")


fig_dir <- file.path(getwd(), "figures")

if (!dir.exists(fig_dir)) {
  dir.create(fig_dir, recursive = TRUE)
}


cat("Figures will be saved in:", fig_dir, "\n")

# GLOFS / LEOFS file settings
year <- 2026
month <- 5
day <- 1
systemname <- "leofs"

yearstr <- sprintf("%04d", year)
monstr  <- sprintf("%02d", month)
daystr  <- sprintf("%02d", day)

filename <- sprintf(
  "%s.t00z.%s%s%s.fields.n000.nc",
  systemname, yearstr, monstr, daystr
)

save_path <- file.path(save_dir, filename)

# Python notebook used nindex = 0.
# R uses one-based indexing, so use 1 for the first time step.
nindex <- 1

# Western Lake Erie bounding box:
# min longitude, min latitude, max longitude, max latitude
bbox_ll <- c(-83.6, 41.3, -82.2, 42.2)
names(bbox_ll) <- c("minlon", "minlat", "maxlon", "maxlat")

