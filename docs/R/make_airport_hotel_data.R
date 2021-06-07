# Packages ---------------------------------------------------------------------
packages_vector <- c("tidyverse",
                     "sf")

need_to_install <- packages_vector[!(packages_vector %in% installed.packages()[,"Package"])]

if (length(need_to_install)) install.packages(need_to_install)

for (package in packages_vector) {
  library(package, character.only = TRUE)
}

# Remote I/O -------------------------------------------------------------------
private_dir <- "data/_PRIVATE/"
data_dir <- "data/input/"

input_filename <- paste0(private_dir, "info-usa/hotels.shp")
output_filename <- paste0(private_dir, "hotels.RDS")

# Parameters -------------------------------------------------------------------

# Data Reads -------------------------------------------------------------------
hotels_sf <- st_read(input_filename)

output_df <- tibble(TAZ = hotels_sf$TAZ, hotel_rooms = hotels_sf$NUMBER_ROO) %>%
  filter(!is.na(hotel_rooms)) %>%
  filter(hotel_rooms > 0) %>%
  filter(TAZ > 0)

# Data Writes ------------------------------------------------------------------
saveRDS(output_df, file = output_filename)