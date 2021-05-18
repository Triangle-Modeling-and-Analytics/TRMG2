# Packages ---------------------------------------------------------------------
packages_vector <- c("tidyverse",
                     "sf",
                     "corrr",
                     "geosphere",
                     "measurements",
                     "kableExtra",
                     "knitr")

need_to_install <- packages_vector[!(packages_vector %in% installed.packages()[,"Package"])]

if (length(need_to_install)) install.packages(need_to_install)

for (package in packages_vector) {
  library(package, character.only = TRUE)
}

# Remote I/O -------------------------------------------------------------------
private_dir <- "data/_PRIVATE/"
data_dir <- "data/input/"
output_dir <- "data/output/"

clean_streetlight_filename <- paste0(private_dir, "clean-streetlight.rds")
socec_filename <- paste0(data_dir, "airport/se_2016.csv")
taz_shape_filename <- paste0(data_dir, "tazs/master_tazs.shp")
distance_skim_filename <- paste0(data_dir, "airport/distance-skim.RDS")
hotel_filename <- paste0(private_dir, "hotels.RDS")

campo_sl_shape <- paste0(private_dir, "streetlight/161428_TRM20test5_2016/Shapefile/161428_TRM20test5_2016_origin/161428_TRM20test5_2016_origin.shp")
durham_sl_shape <- paste0(private_dir, "streetlight/164792_TRM20_2016_All/Shapefile/164792_TRM20_2016_All_origin/164792_TRM20_2016_All_origin.shp")

output_production_filename <- paste0(output_dir, "airport/airport-productions.csv")

# Parameters -------------------------------------------------------------------
SL_AIRPORT_ZONE <- 1261
AIRPORT_TAZ <- 2369
LAT_LNG_EPSG <- 4326
OUTLIER_MIN <- 200

# Data Reads -------------------------------------------------------------------
clean_sl_df <- readRDS(clean_streetlight_filename)
socec_df <- read_csv(socec_filename, col_types = cols(.default = col_double(),
                                                      TAZ = col_integer(),
                                                      Type = col_character()))

distance_df <- readRDS(distance_skim_filename)

taz_sf <- st_read(taz_shape_filename) %>%
  st_transform(LAT_LNG_EPSG)

campo_sf <- st_read(campo_sl_shape, crs = LAT_LNG_EPSG)
durham_sf <- st_read(durham_sl_shape, crs = LAT_LNG_EPSG)

hotels_df <- readRDS(hotel_filename)

# Enplanements -----------------------------------------------------------------
rdu_enplanements <- filter(socec_df, TAZ == AIRPORT_TAZ)$RDU_ENPLANE

# TAZ Coordinates --------------------------------------------------------------
centroids_sf <- select(taz_sf, taz = ID, geometry) %>%
  st_centroid()

centroids_df <- as_tibble(st_coordinates(centroids_sf)) %>%
  bind_cols(., tibble(taz = centroids_sf$taz)) %>%
  rename(lat = Y, lng = X)

# StreetLight Zone Coordinates -------------------------------------------------
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

# StreetLight to TAZ Correspondence --------------------------------------------
working_df <- centroids_df %>%
  select(master_taz = taz, master_lat = lat, master_lng = lng) %>%
  full_join(., sl_centroids_df, by = character()) %>%
  mutate(distance = sqrt((master_lat - lat)**2 + (master_lng - lng)**2))

closest_df <- working_df %>%
  group_by(zone, source) %>%
  summarise(min_dist = min(distance), .groups = "drop") %>%
  left_join(working_df, closest_df, by = c("zone", "source")) %>%
  filter(distance <= min_dist) %>%
  select(taz = master_taz,
         sl_zone = zone,
         sl_source = source,
         distance)

# Reductions -------------------------------------------------------------------
working_df <- clean_sl_df %>%
  filter(type == "Personal") %>%
  filter(day_type == "1: Weekday (M-Th)") %>%
  filter(orig_pass_through == "no" & dest_pass_through == "no") %>%
  filter(orig_zone == SL_AIRPORT_ZONE | dest_zone == SL_AIRPORT_ZONE) %>%
  filter(orig_zone != dest_zone) %>%
  filter(day_part == "0: All Day (12am-12am)") %>%
  filter(!is.na(duration_sec)) %>%
  mutate(production_sl_zone = if_else(orig_zone == SL_AIRPORT_ZONE, dest_zone, orig_zone)) %>%
  mutate(purpose = if_else(orig_zone == SL_AIRPORT_ZONE, "From Airport", "To Airport"))

productions_df <- working_df %>%
  group_by(production_sl_zone, source) %>%
  summarize(airport_productions = sum(flow), duration_min = mean(duration_sec)/60.0, .groups = "drop") %>%
  left_join(., closest_df, by = c("production_sl_zone" = "sl_zone", "source" = "sl_source")) %>%
  group_by(taz) %>%
  summarise(airport_productions = sum(airport_productions), .groups = "drop") %>%
  left_join(., centroids_df, by = c("taz")) %>%
  left_join(., socec_df, by = c("taz" = "TAZ")) %>%
  left_join(., hotels_df, by = c("taz" = "TAZ")) %>%
  mutate(hotel_rooms = replace_na(hotel_rooms, 0L)) %>%
  left_join(., select(distance_df, taz = orig, dist_to_airport_miles = distance), by = c("taz")) %>%
  filter(Type == "Internal") %>%
  mutate(employment = Industry + Office + Service_RateLow + Service_RateHigh + Retail) %>%
  mutate(workers = Pct_Worker/100.0 * HH_POP) %>%
  mutate(high_earners = PctHighEarn/100.0 * workers) %>%
  mutate(high_earn_distance = high_earners * dist_to_airport_miles)

# Correlations -----------------------------------------------------------------
correlations_df <- productions_df %>%
  select(airport_productions,
         workers,
         employment,
         high_earners,
         high_earn_distance,
         hotel_rooms,
         dist_to_airport_miles,
         HH,
         Median_Inc,
         Pct_Worker,
         Stud_GQ,
         Other_NonInst_GQ,
         Inst_GQ,
         Total_POP,
         Industry,
         Office,
         Service_RateHigh,
         Service_RateLow,
         Retail,
         PctHighEarn,
         BuildingS_NCSU) %>%
  correlate() %>%
  select(term, airport_productions) %>%
  arrange(-airport_productions)

# Model Data -------------------------------------------------------------------
model_df <- productions_df %>%
  mutate(y = if_else(airport_productions > OUTLIER_MIN, OUTLIER_MIN, airport_productions))

adjust_factor <- (rdu_enplanements * 2.0)/sum(model_df$y)

model_df <- model_df %>%
  mutate(y = y * adjust_factor)

# Model Estimation -------------------------------------------------------------
model_01 <- lm(y ~ employment + workers,
               data = model_df)

model_02 <- lm(y ~ workers + high_earners + Service_RateHigh + Industry + Office + Retail + high_earn_distance + hotel_rooms,
               data = model_df)

model_03 <- lm(y ~ high_earners + high_earn_distance + employment,
               data = model_df)

model_04 <- lm(y ~ high_earners + high_earn_distance + Industry + Office + Service_RateHigh + Retail,
               data = model_df)

# Model Application ------------------------------------------------------------
output_df <- productions_df %>%
  mutate(observed_productions = if_else(airport_productions < OUTLIER_MIN,
                                        airport_productions * adjust_factor,
                                        OUTLIER_MIN * adjust_factor)) %>%
  mutate(estimated_productions = model_03$coefficients["(Intercept)"] +
           model_03$coefficients["high_earners"] * high_earners +
           model_03$coefficients["high_earn_distance"] * high_earn_distance +
           model_03$coefficients["employment"] * employment) %>%
  mutate(estimated_productions = if_else(estimated_productions < 0.0, 
                                         0.0,
                                         estimated_productions))

# Write out Tableau Production File --------------------------------------------
write_csv(output_df, output_production_filename)

# Diurnals ---------------------------------------------------------------------
diurnal_df <- clean_sl_df %>%
  filter(type == "Personal") %>%
  filter(day_type == "1: Weekday (M-Th)") %>%
  filter(orig_pass_through == "no" & dest_pass_through == "no") %>%
  filter(orig_zone == SL_AIRPORT_ZONE | dest_zone == SL_AIRPORT_ZONE) %>%
  filter(orig_zone != dest_zone) %>%
  filter(day_part != "0: All Day (12am-12am)") %>%
  filter(!is.na(duration_sec)) %>%
  mutate(production_sl_zone = if_else(orig_zone == SL_AIRPORT_ZONE, dest_zone, orig_zone)) %>%
  mutate(purpose = if_else(orig_zone == SL_AIRPORT_ZONE, "From Airport", "To Airport")) %>%
  group_by(purpose, day_part) %>%
  summarise(trips = sum(flow), .groups = "drop") %>%
  group_by(purpose) %>%
  mutate(share = trips/sum(trips))

# convert to model time periods
diurnal_cross_df <- crossing(tibble(hour = seq(from = 0, to = 23)),
                               tibble(minute = seq(from = 0, to = 60))) %>%
  mutate(decimal_time = hour + minute/60.0) %>%
  mutate(sl_period = case_when(
    hour < 6 ~ "1: Early AM (12am-6am)",
    hour < 10 ~ "2: Peak AM (6am-10am)",
    hour < 15 ~  "3: Mid-Day (10am-3pm)",
    hour < 19 ~ "4: Peak PM (3pm-7pm)",
    TRUE ~ "5: Late PM (7pm-12am)"
  )) %>%
  mutate(model_period = case_when(
    hour < 7 ~ "NT",
    hour < 9 ~ "AM",
    decimal_time < 15.5 ~  "MD",
    decimal_time < 18.25 ~ "PM",
    TRUE ~ "NT"
  )) %>%
  group_by(sl_period, model_period) %>%
  summarise(count_of_minutes = n(), .groups = "drop") %>%
  group_by(sl_period) %>%
  mutate(share_of_model_in_sl = count_of_minutes / sum(count_of_minutes)) %>%
  ungroup() %>%
  select(-count_of_minutes)

model_diurnals_df <- left_join(diurnal_df, diurnal_cross_df, by = c("day_part" = "sl_period")) %>%
  mutate(model_share = share * share_of_model_in_sl) %>%
  mutate(model_trips = trips * share_of_model_in_sl) %>%
  group_by(purpose, model_period) %>%
  summarise(share = sum(model_share), trips = sum(model_trips), .groups = "drop") %>%
  left_join(., tibble(model_period = c("AM", "MD", "PM", "NT"), order = c(1,2,3,4)), by = c("model_period")) %>%
  arrange(purpose, order) %>%
  mutate(direction = if_else(purpose == "From Airport", "A to P", "P to A")) %>%
  select(purpose, direction, period = model_period, share)
