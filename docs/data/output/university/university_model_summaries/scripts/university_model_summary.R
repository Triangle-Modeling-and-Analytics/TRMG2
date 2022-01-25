library(tidyverse)

interim_dir <- "D:/Models/TRMG2/docs/data/output/university/university_model_summaries/data/interim/"
external_dir <- "D:/Models/TRMG2/docs/data/output/university/university_model_summaries/data/external/"

sed_filename <- paste0(interim_dir,"scenario_se.csv")

trips_am_filename <- paste0(interim_dir,"university_trips_AM.csv")
trips_md_filename <- paste0(interim_dir,"university_trips_MD.csv")
trips_pm_filename <- paste0(interim_dir,"university_trips_PM.csv")
trips_nt_filename <- paste0(interim_dir,"university_trips_NT.csv")

trips_uhc_off_am_filename <- paste0(interim_dir,"university_mode_trips_UHC_OFF_AM.csv")
trips_uhc_off_md_filename <- paste0(interim_dir,"university_mode_trips_UHC_OFF_MD.csv")
trips_uhc_off_pm_filename <- paste0(interim_dir,"university_mode_trips_UHC_OFF_PM.csv")
trips_uhc_off_nt_filename <- paste0(interim_dir,"university_mode_trips_UHC_OFF_NT.csv")

sov_distance_am_filename <- paste0(interim_dir,"sov_distance_skim_am.csv")
  
survey_trips_filename <- paste0(external_dir,"Trip_subset_df.csv")

sed_df <- read.csv(sed_filename)

sed_df <- sed_df %>%
  mutate(productions_ncsu = rowSums(select(., starts_with("Prod") & ends_with("NCSU")))) %>%
  mutate(productions_unc = rowSums(select(., starts_with("Prod") & ends_with("UNC")))) %>%
  mutate(productions_duke = rowSums(select(., starts_with("Prod") & ends_with("DUKE")))) %>%
  mutate(productions_nccu = rowSums(select(., starts_with("Prod") & ends_with("NCCU")))) %>%
  mutate(enrollment_ncsu = StudGQ_NCSU + StudOff_NCSU) %>%
  mutate(enrollment_unc = StudGQ_UNC + StudOff_UNC) %>%
  mutate(enrollment_duke = StudGQ_DUKE + StudOff_DUKE) %>%
  mutate(enrollment_nccu = StudGQ_NCCU + StudOff_NCCU)

trips_am_df <- read_csv(trips_am_filename, col_types = "iidddd", col_names = FALSE)
trips_md_df <- read_csv(trips_md_filename, col_types = "iidddd", col_names = FALSE)
trips_pm_df <- read_csv(trips_pm_filename, col_types = "iidddd", col_names = FALSE)
trips_nt_df <- read_csv(trips_nt_filename, col_types = "iidddd", col_names = FALSE)

trips_uhc_off_am_df <- read_csv(trips_uhc_off_am_filename, col_types = "iidddd", col_names = FALSE)
trips_uhc_off_md_df <- read_csv(trips_uhc_off_md_filename, col_types = "iidddd", col_names = FALSE)
trips_uhc_off_pm_df <- read_csv(trips_uhc_off_pm_filename, col_types = "iidddd", col_names = FALSE)
trips_uhc_off_nt_df <- read_csv(trips_uhc_off_nt_filename, col_types = "iidddd", col_names = FALSE)


trips_am_df <- trips_am_df %>% as.data.frame()
trips_md_df <- trips_md_df %>% as.data.frame()
trips_pm_df <- trips_pm_df %>% as.data.frame()
trips_nt_df <- trips_nt_df %>% as.data.frame()

names(trips_am_df) <- c("orig", "dest", "auto_am", "transit_am", "walk_am", "bike_am")
names(trips_md_df) <- c("orig", "dest", "auto_md", "transit_md", "walk_md", "bike_md")
names(trips_pm_df) <- c("orig", "dest", "auto_pm", "transit_pm", "walk_pm", "bike_pm")
names(trips_nt_df) <- c("orig", "dest", "auto_nt", "transit_nt", "walk_nt", "bike_nt")

trips_uhc_off_am_df <- trips_uhc_off_am_df %>% as.data.frame()
trips_uhc_off_md_df <- trips_uhc_off_md_df %>% as.data.frame()
trips_uhc_off_pm_df <- trips_uhc_off_pm_df %>% as.data.frame()
trips_uhc_off_nt_df <- trips_uhc_off_nt_df %>% as.data.frame()

names(trips_uhc_off_am_df) <- c("orig", "dest", "auto_am", "transit_am", "walk_am", "bike_am")
names(trips_uhc_off_md_df) <- c("orig", "dest", "auto_md", "transit_md", "walk_md", "bike_md")
names(trips_uhc_off_pm_df) <- c("orig", "dest", "auto_pm", "transit_pm", "walk_pm", "bike_pm")
names(trips_uhc_off_nt_df) <- c("orig", "dest", "auto_nt", "transit_nt", "walk_nt", "bike_nt")

skim_df <- read_csv(sov_distance_am_filename, col_types = "iid", col_names = FALSE)

skim_df <- skim_df %>% as.data.frame()
names(skim_df) <- c("orig", "dest", "distance")

survey_trips_df <- read.csv(survey_trips_filename)

survey_trips_df <- survey_trips_df %>% 
  filter(!is.na(Weight))

survey_trips_df <- survey_trips_df %>%
  filter(!is.na(Walk)) %>%
  filter(!is.na(Bicycle)) %>%
  filter(!is.na(Bus)) %>%
  filter(!is.na(Car)) %>%
  filter(!is.na(Carpool)) %>%
  filter(!is.na(Other)) %>%
  mutate(mode = case_when(
    Bicycle == 1 ~ "BIKE",
    Walk == 1 ~ "WALK",
    Bus == 1 ~ "TRANSIT", 
    Car == 1 ~ "AUTO",
    Carpool == 1 ~ "AUTO",
    TRUE ~ "OTHER")
  )


# ----------- Trips per Student ----------- #

trips_per_enrollment_df <- data.frame(
  campus = c("NCSU", "UNC", "DUKE", "NCCU", "NCSU"),
  value = c(
    round(sum(sed_df$productions_ncsu) / sum(sed_df$enrollment_ncsu), 2),
    round(sum(sed_df$productions_unc) / sum(sed_df$enrollment_unc), 2),
    round(sum(sed_df$productions_duke) / sum(sed_df$enrollment_duke), 2),
    round(sum(sed_df$productions_nccu) / sum(sed_df$enrollment_nccu), 2),
    round(sum(survey_trips_df$Weight) / sum(sed_df$enrollment_ncsu), 2)
  ),
  source = c("Simulated", "Simulated", "Simulated", "Simulated", "Observed")
)

trips_per_enrollment_df <- trips_per_enrollment_df %>%
  mutate(measure = "trips per enrollment")

trips_df <- trips_am_df %>%
  left_join(trips_md_df, by = c("orig", "dest")) %>%
  left_join(trips_pm_df, by = c("orig", "dest")) %>%
  left_join(trips_nt_df, by = c("orig", "dest")) %>%
  mutate(auto_trips = auto_am + auto_md + auto_pm + auto_nt) %>%
  mutate(transit_trips = transit_am + transit_md + transit_pm + transit_nt) %>%
  mutate(walk_trips = walk_am + walk_md + walk_pm + walk_nt) %>%
  mutate(bike_trips = bike_am + bike_md + bike_pm + bike_nt) %>%
  mutate(total_trips = auto_trips + transit_trips + walk_trips + bike_trips) %>%
  left_join(skim_df, by = c("orig", "dest")) %>%
  filter(!is.na(distance)) %>%
  mutate(
    auto_trips_distance = auto_trips * distance,
    transit_trips_distance = transit_trips * distance,
    walk_trips_distance = walk_trips * distance,
    bike_trips_distance = bike_trips * distance
  )

trips_uhc_off_df <- trips_uhc_off_am_df %>%
  left_join(trips_uhc_off_md_df, by = c("orig", "dest")) %>%
  left_join(trips_uhc_off_pm_df, by = c("orig", "dest")) %>%
  left_join(trips_uhc_off_nt_df, by = c("orig", "dest")) %>%
  mutate(auto_trips = auto_am + auto_md + auto_pm + auto_nt) %>%
  mutate(transit_trips = transit_am + transit_md + transit_pm + transit_nt) %>%
  mutate(walk_trips = walk_am + walk_md + walk_pm + walk_nt) %>%
  mutate(bike_trips = bike_am + bike_md + bike_pm + bike_nt) %>%
  select(orig, dest, auto_trips, transit_trips, bike_trips, walk_trips)

# ----------- Bldg sqft per Student ----------- #

bldg_per_enrollment_df <- data.frame(
  campus = c("NCSU", "UNC", "DUKE", "NCCU"),
  value = c(
    round(sum(sed_df$BuildingS_NCSU) / sum(sed_df$enrollment_ncsu), 2),
    round(sum(sed_df$BuildingS_UNC) / sum(sed_df$enrollment_unc), 2),
    round(sum(sed_df$BuildingS_DUKE) / sum(sed_df$enrollment_duke), 2),
    round(sum(sed_df$BuildingS_NCCU) / sum(sed_df$enrollment_nccu), 2)
    )
)

bldg_per_enrollment_df <- bldg_per_enrollment_df %>%
  mutate(measure = "building sqft per student") %>%
  mutate(source = "Simulated")

# ----------- Average Trip Length ----------- #

avg_trip_length_simulated_df <- data.frame(
  mode = c("AUTO", "TRANSIT", "WALK", "BIKE"),
  value = c(
    round(sum(trips_df$auto_trips_distance) / sum(trips_df$auto_trips), 2),
    round(sum(trips_df$transit_trips_distance) / sum(trips_df$transit_trips), 2),
    round(sum(trips_df$walk_trips_distance) / sum(trips_df$walk_trips), 2),
    round(sum(trips_df$bike_trips_distance) / sum(trips_df$bike_trips), 2)
  )
)

avg_trip_length_simulated_df <- avg_trip_length_simulated_df %>%
  mutate(source = "Simulated") %>%
  mutate(measure = "average trip length")

avg_trip_length_observed_df <- survey_trips_df %>%
  filter(!is.na(distance_zonetozone)) %>%
  filter(mode != "OTHER") %>%
  mutate(trips_distance = Weight * distance_zonetozone) %>%
  group_by(mode) %>%
  summarise(value = round(sum(trips_distance) / sum(Weight), 2)) %>%
  mutate(source = "Observed") %>%
  mutate(measure = "average trip length")

avg_trip_length_df <- bind_rows(avg_trip_length_simulated_df, avg_trip_length_observed_df)


ncsu_taz_list <- sed_df %>%
  filter(BuildingS_NCSU > 0) %>%
  pull(TAZ)

duke_taz_list <- sed_df %>%
  filter(BuildingS_DUKE > 0) %>%
  pull(TAZ)

unc_taz_list <- sed_df %>%
  filter(BuildingS_UNC > 0) %>%
  pull(TAZ)

nccu_taz_list <- sed_df %>%
  filter(BuildingS_NCCU > 0) %>%
  pull(TAZ)

TAZ_MAIN_NCSU <- sed_df %>%
  slice_max(BuildingS_NCSU) %>%
  pull(TAZ)

TAZ_MAIN_UNC <- sed_df %>%
  slice_max(BuildingS_UNC) %>%
  pull(TAZ)

TAZ_MAIN_DUKE <- sed_df %>%
  slice_max(BuildingS_DUKE) %>%
  pull(TAZ)

TAZ_MAIN_NCCU <- sed_df %>%
  slice_max(BuildingS_NCCU) %>%
  pull(TAZ)


uhc_ncsu_on_df <- sed_df %>% 
  select(orig = TAZ, prod = ProdOn_UHC_NCSU) %>%
  mutate(
    dest = TAZ_MAIN_NCSU,
    campus = "NCSU",
    type = "On-Campus"
  )

uhc_ncsu_off_df <- sed_df %>% 
  select(orig = TAZ, prod = ProdOff_UHC_NCSU) %>%
  mutate(
    dest = TAZ_MAIN_NCSU,
    campus = "NCSU",
    type = "Off-Campus"
  )   

uhc_unc_on_df <- sed_df %>% 
  select(orig = TAZ, prod = ProdOn_UHC_UNC) %>%
  mutate(
    dest = TAZ_MAIN_UNC,
    campus = "UNC",
    type = "On-Campus"
  )

uhc_unc_off_df <- sed_df %>% 
  select(orig = TAZ, prod = ProdOff_UHC_UNC) %>%
  mutate(
    dest = TAZ_MAIN_UNC,
    campus = "UNC",
    type = "Off-Campus"
  )  

uhc_duke_on_df <- sed_df %>% 
  select(orig = TAZ, prod = ProdOn_UHC_DUKE) %>%
  mutate(
    dest = TAZ_MAIN_DUKE,
    campus = "DUKE",
    type = "On-Campus"
  )

uhc_duke_off_df <- sed_df %>% 
  select(orig = TAZ, prod = ProdOff_UHC_DUKE) %>%
  mutate(
    dest = TAZ_MAIN_DUKE,
    campus = "DUKE",
    type = "Off-Campus"
  )  

uhc_nccu_on_df <- sed_df %>% 
  select(orig = TAZ, prod = ProdOn_UHC_NCCU) %>%
  mutate(
    dest = TAZ_MAIN_NCCU,
    campus = "NCCU",
    type = "On-Campus"
  )

uhc_nccu_off_df <- sed_df %>% 
  select(orig = TAZ, prod = ProdOff_UHC_NCCU) %>%
  mutate(
    dest = TAZ_MAIN_NCCU,
    campus = "NCCU",
    type = "Off-Campus"
  ) 

uhc_trips_simulated_df <- bind_rows(uhc_ncsu_on_df, uhc_ncsu_off_df, uhc_unc_on_df, uhc_unc_off_df, uhc_duke_on_df, uhc_duke_off_df, uhc_nccu_on_df, uhc_nccu_off_df)

uhc_trips_simulated_df <- uhc_trips_simulated_df %>%
  left_join(skim_df, by = c("orig", "dest")) %>%
  filter(prod > 0) %>%
  rename(trips = prod) %>%
  mutate(source = "Simulated")

uhc_trips_observed_df <- survey_trips_df %>%
  mutate(type = ifelse(On_campus == 1, "On-Campus", "Off-Campus")) %>%
  mutate(distance = distance_zonetozone) %>%
  filter(!is.na(distance)) %>%
  filter(Trip_Purpose == "UHC") %>%
  select(orig = TAZ_o, dest = TAZ_d, type, distance, trips = Weight) %>%
  mutate(campus = "NCSU") %>%
  mutate(source = "Observed")

uhc_trips_df <- bind_rows(uhc_trips_simulated_df, uhc_trips_observed_df)

distance_bins_df <- tibble(bin = seq(from = 0, to = 30, by = 1)) %>%
  mutate(label = paste0(bin, " to ", lead(bin))) %>%
  mutate(label = str_replace(label, "NA", "Inf")) %>%
  mutate(index = row_number())

uhc_trip_length_df <- uhc_trips_df %>%
  filter(distance <= 30) %>%
  mutate(distance_bin = cut(distance,
                            breaks = distance_bins_df$bin,
                            labels = FALSE, 
                            right = TRUE)
  ) %>%
  left_join(., select(distance_bins_df, index, label), by = c("distance_bin" = "index")) %>%
  rename(distance_bin_label = label) %>%
  filter(campus == "NCSU") %>%
  group_by(source, distance_bin_label) %>%
  summarise(trips = sum(trips)) %>%
  mutate(share = trips / sum(trips))

# ----------- Mode Share ----------- #

mode_share_ncsu_df <- trips_df %>%
  select(orig, dest, auto_trips, transit_trips, walk_trips, bike_trips) %>%
  filter(orig %in% ncsu_taz_list | dest %in% ncsu_taz_list) %>%
  mutate(campus = "NCSU") %>%
  mutate(purpose = "ALL")

mode_share_unc_df <- trips_df %>%
  select(orig, dest, auto_trips, transit_trips, walk_trips, bike_trips) %>%
  filter(orig %in% unc_taz_list | dest %in% unc_taz_list) %>%
  mutate(campus = "UNC") %>%
  mutate(purpose = "ALL")

mode_share_duke_df <- trips_df %>%
  select(orig, dest, auto_trips, transit_trips, walk_trips, bike_trips) %>%
  filter(orig %in% duke_taz_list | dest %in% duke_taz_list) %>%
  mutate(campus = "DUKE") %>%
  mutate(purpose = "ALL")

mode_share_nccu_df <- trips_df %>%
  select(orig, dest, auto_trips, transit_trips, walk_trips, bike_trips) %>%
  filter(orig %in% nccu_taz_list | dest %in% nccu_taz_list) %>%
  mutate(campus = "NCCU") %>%
  mutate(purpose = "ALL")

mode_share_ncsu_uhc_off_df <- trips_uhc_off_df %>%
  select(orig, dest, auto_trips, transit_trips, walk_trips, bike_trips) %>%
  filter(orig %in% ncsu_taz_list | dest %in% ncsu_taz_list) %>%
  mutate(campus = "NCSU") %>%
  mutate(purpose = "UHC_OFF")

mode_share_duke_uhc_off_df <- trips_uhc_off_df %>%
  select(orig, dest, auto_trips, transit_trips, walk_trips, bike_trips) %>%
  filter(orig %in% duke_taz_list | dest %in% duke_taz_list) %>%
  mutate(campus = "DUKE") %>%
  mutate(purpose = "UHC_OFF")

mode_share_unc_uhc_off_df <- trips_uhc_off_df %>%
  select(orig, dest, auto_trips, transit_trips, walk_trips, bike_trips) %>%
  filter(orig %in% unc_taz_list | dest %in% unc_taz_list) %>%
  mutate(campus = "UNC") %>%
  mutate(purpose = "UHC_OFF")

mode_share_nccu_uhc_off_df <- trips_uhc_off_df %>%
  select(orig, dest, auto_trips, transit_trips, walk_trips, bike_trips) %>%
  filter(orig %in% nccu_taz_list | dest %in% nccu_taz_list) %>%
  mutate(campus = "NCCU") %>%
  mutate(purpose = "UHC_OFF")

mode_share_simulated_df <- bind_rows(mode_share_ncsu_df, mode_share_unc_df, mode_share_duke_df, mode_share_nccu_df,
                                     mode_share_ncsu_uhc_off_df, mode_share_duke_uhc_off_df, mode_share_unc_uhc_off_df, mode_share_nccu_uhc_off_df)
  
mode_share_simulated_df <- mode_share_simulated_df %>%
  group_by(campus, purpose) %>%
  summarise(
    AUTO = sum(auto_trips),
    TRANSIT = sum(transit_trips),
    WALK = sum(walk_trips),
    BIKE = sum(bike_trips)
  ) %>%
  pivot_longer(c("AUTO", "TRANSIT", "WALK", "BIKE"), names_to = "mode", values_to = "trips") %>%
  group_by(campus, purpose) %>%
  mutate(share = round(trips/sum(trips), 4)) %>%
  mutate(source = "Simulated")

mode_share_observed_df <- survey_trips_df %>%
  filter(mode != "OTHER") %>%
  group_by(mode) %>%
  summarise(trips = sum(Weight)) %>%
  mutate(share = round(trips/sum(trips), 4)) %>%
  mutate(campus = "NCSU") %>%
  mutate(source = "Observed") %>%
  mutate(purpose = "ALL")
            
mode_share_df <- bind_rows(mode_share_simulated_df, mode_share_observed_df)

output_df <- bind_rows(trips_per_enrollment_df, bldg_per_enrollment_df, avg_trip_length_df)

write.csv(output_df, paste0(interim_dir, "university_summary.csv"))

write.csv(uhc_trip_length_df, paste0(interim_dir,"home_to_campus_trip_length.csv"))

write.csv(mode_share_df, paste0(interim_dir,"university_mode_shares.csv"))

