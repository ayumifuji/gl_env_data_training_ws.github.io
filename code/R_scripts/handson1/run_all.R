# run_all.R
# Main driver script for the no-sf R translation of the GLOFS / LEOFS notebook.

source("00_setup.R")
source("01_download_open.R")
source("02_mesh_helpers.R")
source("03_plot_mesh_temperature.R")
source("04_plot_velocity.R")
source("05_vertical_transect.R")

# Close NetCDF file when finished
ncdf4::nc_close(nc)


