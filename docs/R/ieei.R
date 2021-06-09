# Remote I/O -------------------------------------------------------------------
private_dir <- "data/_PRIVATE/"
data_dir <- "data/input/"
master_dir <- "../master/"

clean_ie_streetlight_filename <- paste0(private_dir, "clean-streetlight.rds")
clean_ee_streetlight_filename <- paste0(private_dir, "clean-itre-streetlight.rds")
socec_filename <- paste0(data_dir, "ieei/se_2016.csv")
taz_shape_filename <- paste0(master_dir, "tazs/master_tazs.shp")
ext_nodes_shape_filename <- paste0(data_dir, "ieei/ext_nodes.shp")
distance_skim_filename <- paste0(data_dir, "ieei/distance-skim.RDS")

campo_sl_shape <- paste0(private_dir, "streetlight/161428_TRM20test5_2016/Shapefile/161428_TRM20test5_2016_origin/161428_TRM20test5_2016_origin.shp")
durham_sl_shape <- paste0(private_dir, "streetlight/164792_TRM20_2016_All/Shapefile/164792_TRM20_2016_All_origin/164792_TRM20_2016_All_origin.shp")

output_filename <- paste0(data_dir, "ieei/streetlight-flows.csv")

# Parameters -------------------------------------------------------------------
LAT_LNG_EPSG <- 4326

# Data Reads -------------------------------------------------------------------
sl_ie_df <- readRDS(clean_ie_streetlight_filename)
sl_ee_df <- readRDS(clean_ee_streetlight_filename)
dist_df <- readRDS(distance_skim_filename)

socec_df <- read_csv(socec_filename, col_types = cols(.default = col_double(),
                                                      TAZ = col_integer(),
                                                      Type = col_character()))

taz_sf <- st_read(taz_shape_filename) %>%
  st_transform(LAT_LNG_EPSG)

ext_nodes_sf <- st_read(ext_nodes_shape_filename) %>%
  st_transform(LAT_LNG_EPSG)

campo_sf <- st_read(campo_sl_shape, crs = LAT_LNG_EPSG)
durham_sf <- st_read(durham_sl_shape, crs = LAT_LNG_EPSG)

# Resolve geographies ----------------------------------------------------------
number_of_external <- socec_df %>%
  filter(Type == "External") %>%
  nrow(.)

centroids_sf <- select(taz_sf, taz = ID, geometry) %>%
  st_centroid()

centroids_df <- as_tibble(st_coordinates(centroids_sf)) %>%
  bind_cols(., tibble(taz = centroids_sf$taz)) %>%
  rename(lat = Y, lng = X)

c_sf <- campo_sf %>%
  filter(is_pass == 0) %>%
  select(id, geometry) %>%
  st_centroid(.)

d_sf <- durham_sf %>%
  filter(is_pass == 0) %>%
  select(id, geometry) %>%
  st_centroid(.)

sl_centroids_df <- bind_rows(
  mutate(
    bind_cols(as_tibble(st_coordinates(c_sf)),
              tibble(zone = c_sf$id)),
    source = "campo"),
  mutate(
    bind_cols(as_tibble(st_coordinates(d_sf)),
              tibble(zone = d_sf$id)),
    source = "durham")) %>%
  mutate(zone = as.integer(zone)) %>%
  rename(lat = Y, lng = X)

remove(c_sf, d_sf)

internal_taz_vector <- socec_df %>%
  filter(Type == "Internal") %>%
  .$TAZ

working_df <- centroids_df %>%
  select(master_taz = taz, master_lat = lat, master_lng = lng) %>%
  full_join(., sl_centroids_df, by = character()) %>%
  mutate(distance = sqrt((master_lat - lat)**2 + (master_lng - lng)**2))

closest_df <- working_df %>%
  group_by(zone, source) %>%
  summarise(min_dist = min(distance), .groups = "drop") %>%
  left_join(working_df, ., by = c("zone", "source")) %>%
  filter(distance <= min_dist) %>%
  select(taz = master_taz,
         sl_zone = zone,
         sl_source = source) %>%
  mutate(taz = as.integer(taz)) %>%
  filter(taz %in% internal_taz_vector) 

external_centroids_df <- as_tibble(st_coordinates(ext_nodes_sf)) %>%
  bind_cols(tibble(taz = ext_nodes_sf$ID)) %>%
  rename(lat = Y, lng = X)

working_df <- external_centroids_df %>%
  select(master_taz = taz, master_lat = lat, master_lng = lng) %>%
  full_join(., sl_centroids_df, by = character()) %>%
  mutate(distance = sqrt((master_lat - lat)**2 + (master_lng - lng)**2))

closest_ext_df <- working_df %>%
  group_by(zone, source) %>%
  summarise(min_dist = min(distance), .groups = "drop") %>%
  left_join(working_df, ., by = c("zone", "source")) %>%
  filter(distance <= min_dist) %>%
  select(taz = master_taz,
         sl_zone = zone,
         sl_source = source) %>%
  mutate(taz = as.integer(taz))

# Create single data frame -----------------------------------------------------
working_ie_df <- sl_ie_df %>%
  filter(type == "Personal") %>%
  filter(day_type == "1: Weekday (M-Th)") %>%
  filter(flow > 0) %>%
  filter(orig_pass_through == "yes" | dest_pass_through == "yes") %>%
  filter(orig_zone != dest_zone) %>%
  mutate(purpose = "Missing") %>%
  mutate(purpose = if_else(orig_pass_through == "yes" & dest_pass_through == "yes", "XX", purpose)) %>%
  mutate(purpose = if_else(orig_pass_through == "yes" & dest_pass_through == "no", "IX", purpose)) %>%
  mutate(purpose = if_else(orig_pass_through == "no" & dest_pass_through == "yes", "XI", purpose)) %>%
  left_join(., closest_df, by = c("orig_zone" = "sl_zone", "source" = "sl_source")) %>%
  mutate(orig_taz = if_else(purpose == "IX", taz, as.integer(NA))) %>%
  select(-taz) %>%
  left_join(., closest_df, by = c("dest_zone" = "sl_zone", "source" = "sl_source")) %>%
  mutate(dest_taz = if_else(purpose == "XI", taz, as.integer(NA))) %>%
  select(-taz) %>%
  left_join(., closest_ext_df, by = c("orig_zone" = "sl_zone", "source" = "sl_source")) %>%
  mutate(orig_taz = if_else(purpose %in% c("XX", "XI"), taz, orig_taz)) %>%
  select(-taz) %>%
  left_join(., closest_ext_df, by = c("dest_zone" = "sl_zone", "source" = "sl_source")) %>%
  mutate(dest_taz = if_else(purpose %in% c("XX", "IX"), taz, dest_taz)) %>%
  select(-taz)

working_df <- working_ie_df %>%
  filter(day_part == "0: All Day (12am-12am)") %>%
  select(-orig_zone, -dest_zone) %>%
  filter(!is.na(orig_taz)) %>%
  filter(!is.na(dest_taz)) %>%
  filter(purpose %in% c("IX", "XI"))

bind_ee_df <- sl_ee_df %>%
  mutate(source = "itre") %>%
  mutate(purpose = "XX")

combined_df <- bind_rows(working_df, bind_ee_df) %>%
  left_join(., centroids_df, by = c("orig_taz" = "taz")) %>%
  mutate(orig_lat = if_else(purpose == "IX", lat, as.double(NA))) %>%
  mutate(orig_lng = if_else(purpose == "IX", lng, as.double(NA))) %>%
  select(-lat, -lng) %>%
  left_join(., centroids_df, by = c("dest_taz" = "taz")) %>%
  mutate(dest_lat = if_else(purpose == "XI", lat, as.double(NA))) %>%
  mutate(dest_lng = if_else(purpose == "XI", lng, as.double(NA))) %>%
  select(-lat, -lng) %>%
  left_join(., external_centroids_df, by = c("orig_taz" = "taz")) %>%
  mutate(orig_lat = if_else(purpose %in% c("XI", "XX"), lat, orig_lat)) %>%
  mutate(orig_lng = if_else(purpose %in% c("XI", "XX"), lng, orig_lng)) %>%
  select(-lat, -lng) %>%
  left_join(., external_centroids_df, by = c("dest_taz" = "taz")) %>%
  mutate(dest_lat = if_else(purpose %in% c("IX", "XX"), lat, dest_lat)) %>%
  mutate(dest_lng = if_else(purpose %in% c("IX", "XX"), lng, dest_lng)) %>%
  select(-lat, -lng) %>%
  mutate(prod_taz = if_else(purpose %in% c("IX", "XX"), dest_taz, orig_taz)) %>%
  mutate(attr_taz = if_else(purpose %in% c("IX", "XX"), orig_taz, dest_taz)) %>%
  mutate(prod_lat = if_else(purpose %in% c("IX", "XX"), dest_lat, orig_lat)) %>%
  mutate(prod_lng = if_else(purpose %in% c("IX", "XX"), dest_lng, orig_lng)) %>%
  mutate(attr_lat = if_else(purpose %in% c("IX", "XX"), orig_lat, dest_lat)) %>%
  mutate(attr_lng = if_else(purpose %in% c("IX", "XX"), orig_lng, dest_lng))

write_csv(combined_df, output_filename)

remove(working_df, working_ie_df, bind_ee_df)

# External station shares ------------------------------------------------------
working_df <- combined_df %>%
  filter(purpose == "XX" & source == "itre") %>%
  filter(orig_taz != dest_taz) 

temp_orig_df <- working_df %>%
  group_by(orig_name, orig_taz, day_type, day_part) %>%
  summarise(orig_flow = sum(flow), .groups = "drop") %>%
  select(ext_station = orig_taz, station_name = orig_name, day_type, day_part, orig_flow)

ext_shares_df <- working_df %>%
  group_by(dest_name, dest_taz, day_type, day_part) %>%
  summarise(dest_flow = sum(flow), .groups = "drop") %>%
  select(ext_station = dest_taz, station_name = dest_name, day_type, day_part, dest_flow) %>%
  left_join(., temp_orig_df, by = c("ext_station", "station_name", "day_type", "day_part")) %>%
  left_join(., select(socec_df, ext_station = TAZ, ADT, PCTAUTOEE), by = c("ext_station")) %>%
  mutate(ee_flow = orig_flow + dest_flow) %>%
  mutate(pct_auto_ee = 100.0 * ee_flow / ADT) %>%
  select(-orig_flow, -dest_flow, -day_type, -day_part)

remove(working_df, temp_orig_df)

# Internal attraction model ----------------------------------------------------
join_taz_df <- tibble(taz = taz_sf$ID, district = taz_sf$DISTRICT2)

join_socec_df <- socec_df %>%
  mutate(emp = Industry + Office + Service_RateLow + Service_RateHigh + Retail) %>%
  select(taz = TAZ, emp, pop = Total_POP) %>%
  left_join(., join_taz_df, by = c("taz")) %>%
  group_by(district) %>%
  summarise(pop = sum(pop), emp = sum(emp), .groups = "drop")

estimation_df <- combined_df %>%
  filter(purpose %in% c("IX", "XI")) %>%
  left_join(., select(join_taz_df, orig_taz = taz, orig_district = district), by = c("orig_taz")) %>%
  left_join(., select(join_taz_df, dest_taz = taz, dest_district = district), by = c("dest_taz")) %>%
  mutate(district = if_else(purpose == "IX", orig_district, dest_district)) %>%
  group_by(source, type, district) %>%
  summarize(trips = sum(flow), .groups = "drop") %>%
  left_join(., join_socec_df, by = c("district"))

correlations_df <- estimation_df %>%
  select(trips, pop, emp) %>%
  correlate()

# START HERE. Trips are negatively correlated with population and employment. 
# Try with 21 districts to see if that's better
# Then move to markdown and make documentation

model_01 <- lm(trips ~ pop + emp, data = estimation_df)

summary(model_01) 

model_02 <- lm(trips ~ pop, data = estimation_df)

summary(model_02)
