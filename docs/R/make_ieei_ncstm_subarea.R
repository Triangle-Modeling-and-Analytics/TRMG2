# Packages ---------------------------------------------------------------------
packages_vector <- c("tidyverse",
                     "devtools",
                     "sf")

need_to_install <- packages_vector[!(packages_vector %in% installed.packages()[,"Package"])]

if (length(need_to_install)) install.packages(need_to_install)

for (package in packages_vector) {
  library(package, character.only = TRUE)
}

devtools::install_github("gregmacfarlane/omxr")

library(omxr)

# Remote I/O -------------------------------------------------------------------
data_dir <- "data/input/ieei/"
master_dir <- "../master/"

input_omx_matrices_df <- tibble(file = c("sub_od_auto", "sub_od_mut", "sub_od_sut"),
                                name = c("auto", "mut", "sut"))

input_node_shape_filename <- paste0(data_dir, "ncstm/ncstm_nodes.shp")
taz_shape_filename <- paste0(master_dir, "tazs/master_tazs.shp")
ext_nodes_shape_filename <- paste0(data_dir, "ext_nodes.shp")

output_filename <- paste0(data_dir, "ncstm-demand.rds")

# Parameters -------------------------------------------------------------------
LAT_LNG_EPSG <- 4326
LOOKUP_NAME <- "Subarea Nodes"

taz_node_override_df <- tibble(node = c(661273, 
                                        661274, 
                                        661252, 
                                        667386, 
                                        667388,
                                        666253,
                                        666282,
                                        665320),
                               override_taz = c(3252, 
                                                3252, 
                                                3252, 
                                                3273, 
                                                3273,
                                                3273,
                                                3273,
                                                3237)) 

nodes_box <- st_bbox(c(xmin = -82.0, xmax = -77.0, ymax = 38.0, ymin = 33.0), 
                     crs = st_crs(LAT_LNG_EPSG)) %>%
  st_as_sfc(.)

# Data Reads -------------------------------------------------------------------
demand_df <- tibble()
for (segment in input_omx_matrices_df$name) {
  
  filename <- filter(input_omx_matrices_df, name == segment) %>%
    pull(file)
  
  filename <- paste0(data_dir, "ncstm/", filename, ".omx")

  indices_vector <- read_lookup(filename, LOOKUP_NAME)
  index_df <- tibble(index = indices_vector$Lookup,
                     orig_dest = c(seq(from = 1, to = length(indices_vector$Lookup))))
  
  df <- read_all_omx(filename) %>%
    mutate(vehicle_type = segment) %>%
    left_join(., index_df, by = c("origin" = "orig_dest")) %>%
    rename(orig_node = index) %>%
    left_join(., index_df, by = c("destination" = "orig_dest")) %>%
    rename(dest_node = index) %>%
    filter(Demand > 0.0)
  
  demand_df <- bind_rows(demand_df, df)
  
}

taz_sf <- st_read(taz_shape_filename) %>%
  st_transform(LAT_LNG_EPSG)

ext_nodes_sf <- st_read(ext_nodes_shape_filename) %>%
  st_transform(LAT_LNG_EPSG)

state_nodes_sf <- st_read(input_node_shape_filename) %>%
  st_transform(LAT_LNG_EPSG)

# Nearest Zone to Statewide Nodes ----------------------------------------------
external_centroids_df <- as_tibble(st_coordinates(ext_nodes_sf)) %>%
  bind_cols(tibble(taz = ext_nodes_sf$ID)) %>%
  rename(lat = Y, lng = X)

centroids_sf <- select(taz_sf, taz = ID, geometry) %>%
  st_centroid()

internal_centroids_df <- as_tibble(st_coordinates(centroids_sf)) %>%
  bind_cols(., tibble(taz = centroids_sf$taz)) %>%
  rename(lat = Y, lng = X)

zones_df <- bind_rows(external_centroids_df, internal_centroids_df)

nodes_df <- as_tibble(st_coordinates(state_nodes_sf)) %>%
  bind_cols(tibble(node = state_nodes_sf$ID)) %>%
  rename(node_lat = Y, node_lng = X) %>%
  bind_cols(tibble(in_box = st_within(state_nodes_sf, nodes_box))) %>%
  filter(lengths(in_box) == 1) %>%
  select(-in_box)

working_df <- zones_df %>%
  full_join(., nodes_df, by = character()) %>%
  mutate(distance = sqrt((lat - node_lat)**2 + (lng - node_lng)**2))

closest_df <- working_df %>%
  group_by(node) %>%
  summarise(min_dist = min(distance), .groups = "drop") %>%
  left_join(., working_df, by = c("node")) %>%
  filter(distance <= min_dist) %>%
  select(node, taz, distance) %>%
  left_join(., taz_node_override_df, by = c("node")) %>%
  mutate(taz = if_else(is.na(override_taz), taz, override_taz)) %>%
  select(-override_taz)

# Make Demand ------------------------------------------------------------------
max_internal_zone <- max(taz_sf$ID)

output_df <- demand_df %>%
  left_join(., select(closest_df, taz, orig_node = node), by = c("orig_node")) %>%
  rename(orig_taz = taz) %>%
  left_join(., select(closest_df, taz, dest_node = node), by = c("dest_node")) %>%
  rename(dest_taz = taz) %>%
  group_by(orig_taz, dest_taz, vehicle_type) %>%
  summarise(flow = sum(Demand), .groups = "drop") %>%
  mutate(purpose = "II") %>%
  mutate(purpose = if_else(orig_taz > max_internal_zone & dest_taz > max_internal_zone, "XX", purpose)) %>%
  mutate(purpose = if_else(orig_taz > max_internal_zone & dest_taz <= max_internal_zone, "XI", purpose)) %>%
  mutate(purpose = if_else(orig_taz <= max_internal_zone & dest_taz > max_internal_zone, "IX", purpose)) 
  
sum(output_df$flow)
sum(demand_df$Demand)

summary_df <- output_df %>%
  group_by(purpose) %>%
  summarise(trips = sum(flow), .groups = "drop")

summary_df

# Write ------------------------------------------------------------------------
saveRDS(output_df, file = output_filename)
