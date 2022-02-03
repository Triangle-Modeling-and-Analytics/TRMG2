library(tidyverse)

# Remote I/O -------------------------------------------------------------------
private_dir <- "data/_PRIVATE/"
output_dir <- "data/output/"

input_ee_filename <- paste0(private_dir, "ee_trips.csv")
input_ie_filename <- paste0(private_dir, "ie_trips.csv")
output_filename <- paste0(output_dir, "ieei/ieei_demand.RDS")

# Data Reads -------------------------------------------------------------------
ee_df <- read_csv(input_ee_filename, col_types = cols(.default = col_double(),
                                                      ORIG = col_integer(),
                                                      DEST = col_integer()))

ie_df <- read_csv(input_ie_filename, col_types = cols(.default = col_double(),
                                                      ORIG = col_integer(),
                                                      DEST = col_integer()))

ee_work_df <- ee_df %>%
  pivot_longer(., cols = c(-ORIG, -DEST)) %>%
  filter(value > 0.0) %>%
  group_by(ORIG, DEST) %>%
  summarise(estimated = sum(value), .groups = "drop")

ie_work_df <- ie_df %>%
  pivot_longer(., cols = c(-ORIG, -DEST)) %>%
  filter(value > 0.0) %>%
  group_by(ORIG, DEST) %>%
  summarise(estimated = sum(value), .groups = "drop")

output_df <- bind_rows(ee_work_df, ie_work_df) %>%
  rename(orig_taz = ORIG, dest_taz = DEST)

saveRDS(output_df, file = output_filename)