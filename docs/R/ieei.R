# Remote I/O -------------------------------------------------------------------
private_dir <- "data/_PRIVATE/"
data_dir <- "data/input/ieei/"
output_dir <- "data/output/ieei/"
master_dir <- "../master/"


taz_shape_filename <- paste0(master_dir, "tazs/master_tazs.shp")
socec_filename <- paste0(data_dir, "se_2016.csv")
consolidated_streetlight_filename <- paste0(private_dir, "streetlight-ieei-flows.RDS")
ncstm_filename <- paste0(data_dir, "ncstm-demand.rds")
distance_filename <- paste0(data_dir, "distance-skim.RDS")

output_ee_seed_filename <- paste0(output_dir, "ee-seed.csv")
output_ei_attractions_filename <- paste0(output_dir, "ei-attractions.csv")
output_ei_distance_filename <- paste0(output_dir, "ei-distance.csv")

# Parameters -------------------------------------------------------------------
LAT_LNG_EPSG <- 4326

freeway_station_vector <- c(3298, 3252, 3305, 3277, 3308, 3281, 3273, 3313)

# Data Reads -------------------------------------------------------------------
sl_df <- readRDS(consolidated_streetlight_filename)
state_df <- readRDS(ncstm_filename)

socec_df <- read_csv(socec_filename, col_types = cols(.default = col_double(),
                                                      TAZ = col_integer(),
                                                      Type = col_character()))

taz_sf <- st_read(taz_shape_filename) %>%
  st_transform(LAT_LNG_EPSG)

distance_df <- readRDS(distance_filename)

# StreetLight: External station shares -----------------------------------------
working_df <- sl_df %>%
  filter(purpose == "XX" & source == "itre") %>%
  filter(orig_taz != dest_taz) 

temp_orig_df <- working_df %>%
  group_by(orig_name, orig_taz, day_type, day_part) %>%
  summarise(orig_flow = sum(flow), .groups = "drop") %>%
  select(ext_station = orig_taz, station_name = orig_name, day_type, day_part, orig_flow)

ext_shares_sl_df <- working_df %>%
  group_by(dest_name, dest_taz, day_type, day_part) %>%
  summarise(dest_flow = sum(flow), .groups = "drop") %>%
  select(ext_station = dest_taz, station_name = dest_name, day_type, day_part, dest_flow) %>%
  left_join(., temp_orig_df, by = c("ext_station", "station_name", "day_type", "day_part")) %>%
  left_join(., select(socec_df, ext_station = TAZ, ADT, PCTCV, PCTAUTOEE), by = c("ext_station")) %>%
  mutate(auto_adt = ADT * (1.00 - PCTCV/100.0)) %>%
  mutate(sl_ee_flow = orig_flow + dest_flow) %>%
  mutate(pct_auto_ee = 100.0 * sl_ee_flow / auto_adt) %>%
  select(-orig_flow, -dest_flow, -day_type, -day_part)

remove(working_df, temp_orig_df)

# NCSTM: External station shares -----------------------------------------------
max_internal_zone <- max(filter(socec_df, Type == "Internal")$TAZ)

working_df <- state_df %>%
  filter(purpose != "II")

temp_orig_df <- working_df %>%
  group_by(orig_taz, purpose, vehicle_type) %>%
  summarise(orig_flow = sum(flow), .groups = "drop") %>%
  select(ext_station = orig_taz, vehicle_type, purpose, orig_flow)

temp_both_df <- working_df %>%
  group_by(dest_taz, purpose, vehicle_type) %>%
  summarise(dest_flow = sum(flow), .groups = "drop") %>%
  select(ext_station = dest_taz, vehicle_type, purpose, dest_flow) %>%
  left_join(., temp_orig_df, by = c("ext_station", "vehicle_type", "purpose")) %>%
  mutate(orig_flow = replace_na(orig_flow, 0.0)) %>%
  mutate(flow = orig_flow + dest_flow) %>%
  select(-orig_flow, -dest_flow) %>%
  filter(ext_station > max_internal_zone)

adt_df <- temp_both_df %>%
  group_by(ext_station, vehicle_type) %>%
  summarise(flow = sum(flow), .groups = "drop") %>%
  pivot_wider(., id_cols = c("ext_station"), 
              names_from = vehicle_type, 
              values_from = flow, 
              values_fill = 0.0,
              names_prefix = "total_")

ext_shares_ncstm_df <- temp_both_df %>%
  filter(purpose == "XX") %>%
  select(-purpose) %>%
  pivot_wider(., id_cols = c("ext_station"), 
              names_from = vehicle_type, 
              values_from = flow, 
              values_fill = 0.0,
              names_prefix = "flow_") %>%
  left_join(., select(socec_df, ext_station = TAZ, ADT, PCTCV, PCTAUTOEE), by = c("ext_station")) %>%
  left_join(., adt_df, by = c("ext_station")) %>%
  mutate(adt = total_auto + total_mut + total_sut) %>%
  mutate(pctcv = 100.0 * (total_mut + total_sut) / adt) %>%
  mutate(pct_auto_ee = if_else(total_auto > 0.0, 100.0 * flow_auto / total_auto, 0.0)) %>%
  mutate(pctcv_mut = 100.0 * total_mut / adt) %>%
  mutate(pctcv_sut = 100.0 * total_sut / adt) %>%
  select(-contains("flow_")) %>%
  select(-contains("total_"))

remove(working_df, adt_df, temp_both_df, temp_orig_df)

# External station shares (blended) --------------------------------------------
ext_shares_df <- select(ext_shares_sl_df, ext_station, station_name, ADT, PCTCV, PCTAUTOEE,
                     sl_pct_auto_ee = pct_auto_ee) %>%
  left_join(., 
            select(ext_shares_ncstm_df, ext_station, adt, pctcv, pctcv_mut, pctcv_sut, ncstm_pct_auto_ee = pct_auto_ee), 
            by = c("ext_station")) %>%
  mutate(pct_auto_ee = if_else(is.na(ncstm_pct_auto_ee), 
                               sl_pct_auto_ee,
                               (sl_pct_auto_ee + ncstm_pct_auto_ee) / 2.0)) %>%
  select(ext_station,
         station_name,
         ADT, 
         adt = adt,
         PCTCV,
         pctcv,
         pctcv_mut,
         pctcv_sut,
         PCTAUTOEE,
         pct_auto_ee)

# Make EE Seed -----------------------------------------------------------------
external_zones_vector <- filter(socec_df, Type == "External")$TAZ
number_of_external <- length(external_zones_vector)

join_df <- sl_df %>%
  filter(purpose == "XX" & source == "itre") %>%
  filter(orig_taz != dest_taz) %>%
  select(orig_taz, dest_taz, sl_auto_flow = flow)

combine_df <- state_df %>%
  filter(purpose == "XX") %>%
  select(-purpose) %>%
  pivot_wider(., id_cols = c("orig_taz", "dest_taz"), 
              names_from = vehicle_type, 
              values_from = flow, 
              values_fill = 0.0,
              names_prefix = "ncstm_") %>%
  full_join(., join_df, by = c("orig_taz", "dest_taz")) %>%
  replace_na(list(ncstm_auto = 0.25, 
                  ncstm_sut = 0.25,
                  ncstm_mut = 0.25,
                  sl_auto_flow = 1.0)) %>%
  mutate(sl_adj_auto = sl_auto_flow * sum(.$ncstm_auto)/sum(.$sl_auto_flow)) %>%
  mutate(auto = (ncstm_auto + sl_adj_auto) / 2.0) %>%
  select(orig_taz, dest_taz, auto, cv_sut = ncstm_sut, cv_mut = ncstm_mut)
  
seed_df <- expand_grid(orig_taz = external_zones_vector, dest_taz = external_zones_vector) %>%
  filter(orig_taz != dest_taz) %>%
  left_join(., combine_df, by = c("orig_taz", "dest_taz")) %>%
  replace_na(list(auto = 0.0,
                  cv_sut = 0.0,
                  cv_mut = 0.0))

write_csv(seed_df, file = output_ee_seed_filename)

# Internal attraction model (StreetLight Data) ---------------------------------
join_taz_df <- tibble(taz = taz_sf$ID,
                      district_01 = taz_sf$DISTRICT,
                      district_02 = taz_sf$DISTRICT2)

join_socec_district_02_df <- socec_df %>%
  mutate(emp = Industry + Office + Service_RateLow + Service_RateHigh + Retail) %>%
  select(taz = TAZ, emp, pop = Total_POP) %>%
  left_join(., join_taz_df, by = c("taz")) %>%
  rename(district = district_02) %>%
  group_by(district) %>%
  summarise(pop = sum(pop), emp = sum(emp), .groups = "drop")

estimation_df <- sl_df %>%
  filter(purpose %in% c("IX", "XI")) %>%
  left_join(., select(join_taz_df, orig_taz = taz, orig_district = district_02), by = c("orig_taz")) %>%
  left_join(., select(join_taz_df, dest_taz = taz, dest_district = district_02), by = c("dest_taz")) %>%
  mutate(district = if_else(purpose == "IX", orig_district, dest_district)) %>%
  group_by(source, type, district) %>%
  summarize(trips = sum(flow), .groups = "drop") %>%
  left_join(., join_socec_district_02_df, by = c("district"))

correlations_sl_df <- estimation_df %>%
  select(trips, pop, emp) %>%
  corrr::correlate()

# Internal attraction model (NCSTM Data) ---------------------------------------
combined_estimation_df <- state_df %>%
  filter(purpose %in% c("IX", "XI")) %>%
  filter(vehicle_type == "auto") %>%
  select(-vehicle_type) %>%
  left_join(., select(join_taz_df, orig_taz = taz, orig_district = district_02), by = c("orig_taz")) %>%
  left_join(., select(join_taz_df, dest_taz = taz, dest_district = district_02), by = c("dest_taz")) %>%
  mutate(district = if_else(purpose == "IX", orig_district, dest_district)) %>%
  group_by(district) %>%
  summarize(trips = sum(flow), .groups = "drop") %>%
  left_join(., join_socec_district_02_df, by = c("district"))

correlations_ncstm_df <- combined_estimation_df %>%
  select(trips, pop, emp) %>%
  corrr::correlate()

# More districts
join_socec_district_01_df <- socec_df %>%
  mutate(emp = Industry + Office + Service_RateLow + Service_RateHigh + Retail) %>%
  select(taz = TAZ, emp, pop = Total_POP) %>%
  left_join(., join_taz_df, by = c("taz")) %>%
  rename(district = district_01) %>%
  group_by(district) %>%
  summarise(pop = sum(pop), emp = sum(emp), .groups = "drop")

combined_estimation_df <- state_df %>%
  filter(purpose %in% c("IX", "XI")) %>%
  filter(vehicle_type == "auto") %>%
  select(-vehicle_type) %>%
  left_join(., select(join_taz_df, orig_taz = taz, orig_district = district_01), by = c("orig_taz")) %>%
  left_join(., select(join_taz_df, dest_taz = taz, dest_district = district_01), by = c("dest_taz")) %>%
  mutate(district = if_else(purpose == "IX", orig_district, dest_district)) %>%
  group_by(district) %>%
  summarize(trips = sum(flow), .groups = "drop") %>%
  left_join(., join_socec_district_01_df, by = c("district"))

correlations_ncstm_df <- combined_estimation_df %>%
  select(trips, pop, emp) %>%
  corrr::correlate()

# Segment by freeway/non-freeway
segmented_estimation_df <- state_df %>%
  filter(purpose %in% c("IX", "XI")) %>%
  filter(vehicle_type == "auto") %>%
  select(-vehicle_type) %>%
  left_join(., select(join_taz_df, orig_taz = taz, orig_district = district), by = c("orig_taz")) %>%
  left_join(., select(join_taz_df, dest_taz = taz, dest_district = district), by = c("dest_taz")) %>%
  mutate(district = if_else(purpose == "IX", orig_district, dest_district)) %>%
  mutate(category = "Non-freeway") %>%
  mutate(category = if_else(purpose == "IX" & (dest_taz %in% freeway_station_vector), "Freeway", category)) %>%
  mutate(category = if_else(purpose == "XI" & (orig_taz %in% freeway_station_vector), "Freeway", category)) %>%
  group_by(district, category) %>%
  summarize(trips = sum(flow), .groups = "drop") %>%
  left_join(., join_socec_district_01_df, by = c("district"))

# Models
freeway_model <- lm(trips ~ pop + emp, data = filter(segmented_estimation_df, category == "Freeway"))
summary(freeway_model)

non_freeway_model <- lm(trips ~ pop + emp, data = filter(segmented_estimation_df, category == "Non-freeway"))
summary(non_freeway_model)

combined_model <- lm(trips ~ pop + emp, data = combined_estimation_df)
summary(combined_model)

preferred_model <- lm(trips ~ 0 + pop + emp, data = combined_estimation_df)
summary(preferred_model)

# Attraction Model Application ------------------------------------------------
join_observed_df <- state_df %>%
  filter(purpose %in% c("IX", "XI")) %>%
  filter(vehicle_type == "auto") %>%
  select(-vehicle_type) %>%
  group_by(orig_taz, dest_taz) %>%
  summarise(observed_trips = sum(flow), .groups = "drop")

join_socec_df <- socec_df %>%
  mutate(emp = Industry + Office + Service_RateLow + Service_RateHigh + Retail) %>%
  select(attraction_taz = TAZ, emp, pop = Total_POP)

max_internal_zone <- max(filter(socec_df, Type == "Internal")$TAZ)

working_df <- expand_grid(orig_taz = taz_vector, dest_taz = taz_vector) %>%
  mutate(purpose = "II") %>%
  mutate(purpose = if_else(orig_taz > max_internal_zone & dest_taz > max_internal_zone, "XX", purpose)) %>%
  mutate(purpose = if_else(orig_taz > max_internal_zone & dest_taz <= max_internal_zone, "XI", purpose)) %>%
  mutate(purpose = if_else(orig_taz <= max_internal_zone & dest_taz > max_internal_zone, "IX", purpose)) %>%
  filter(purpose %in% c("XI", "IX")) %>%
  left_join(., select(join_taz_df, orig_taz = taz, orig_district = district_01), by = c("orig_taz")) %>%
  left_join(., select(join_taz_df, dest_taz = taz, dest_district = district_01), by = c("dest_taz")) %>%
  mutate(attraction_district = if_else(purpose == "IX", orig_district, dest_district)) %>%
  select(-orig_district, -dest_district) %>%
  mutate(attraction_taz = if_else(purpose == "IX", orig_taz, dest_taz)) %>%
  left_join(., join_observed_df, by = c("orig_taz", "dest_taz")) %>%
  mutate(observed_trips = replace_na(observed_trips, 0.0))

ei_attractions_df <- working_df %>%
  group_by(attraction_taz, attraction_district) %>%
  summarize(observed_trips = sum(observed_trips), .groups = "drop") %>%
  left_join(., join_socec_df, by = c("attraction_taz")) %>%
  mutate(raw_estimated_trips = preferred_model$coefficients["pop"] * pop +
           preferred_model$coefficients["emp"] * emp) %>%
  mutate(estimated_trips = raw_estimated_trips * sum(.$observed_trips) / sum(.$raw_estimated_trips))

ei_distance_df <- working_df %>%
  filter(observed_trips > 0.0) %>%
  left_join(., distance_df, by = c("orig_taz" = "orig", "dest_taz" = "dest")) %>%
  mutate(category = "Non-freeway") %>%
  mutate(category = if_else(purpose == "IX" & (dest_taz %in% freeway_station_vector), "Freeway", category)) %>%
  mutate(category = if_else(purpose == "XI" & (orig_taz %in% freeway_station_vector), "Freeway", category))
  
write_csv(ei_attractions_df, file = output_ei_attractions_filename)
write_csv(ei_distance_df, file = output_ei_distance_filename)

# TODO
# Write up findings in Rmd

