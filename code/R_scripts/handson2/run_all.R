# run_all.R
# Main driver script for Hands-on Session 2.

source("00_setup.R")
source("01_download_glofs.R")
source("02_buoy_observations.R")
source("03_extract_leofs_timeseries.R")
source("04_compare_model_buoy.R")

# Optional GLSEA comparison
if (isTRUE(run_glsea_optional)) {
  source("05_optional_glsea.R")
}


