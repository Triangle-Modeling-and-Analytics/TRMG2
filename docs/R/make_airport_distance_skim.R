# Packages ---------------------------------------------------------------------
packages_vector <- c("tidyverse")

need_to_install <- packages_vector[!(packages_vector %in% installed.packages()[,"Package"])]

if (length(need_to_install)) install.packages(need_to_install)

for (package in packages_vector) {
  library(package, character.only = TRUE)
}

# Remote I/O -------------------------------------------------------------------
private_dir <- "data/_PRIVATE/"
output_dir <- "data/input/"

input_filename <- paste0(private_dir, "AMSOVDistanceSkim.csv")
output_filename <- paste0(output_dir, "airport/distance-skim.RDS")

# Parameters -------------------------------------------------------------------
AIRPORT_TAZ <- 2369

# Data Reads -------------------------------------------------------------------
skim_df <- read_csv(input_filename, 
                    col_names = c("orig", "dest", "distance"),
                    col_types = "iid")

output_df <- skim_df %>%
  filter(dest == AIRPORT_TAZ)

saveRDS(output_df, file = output_filename)