library(tidyverse)

interim_dir <- "D:/Models/TRMG2/docs/data/output/university/university_model_summaries/data/interim/"
external_dir <- "D:/Models/TRMG2/docs/data/output/university/university_model_summaries/data/external/"

univ_pa_trips_filename <- paste0(interim_dir,"university_pa_trips.csv")
sov_distance_am_filename <- paste0(interim_dir,"sov_distance_skim_am.csv")
survey_trips_filename <- paste0(external_dir,"Trip_subset_df.csv")

skim_df <- read_csv(sov_distance_am_filename, col_types = "iid", col_names = FALSE)

skim_df <- skim_df %>% as.data.frame()
names(skim_df) <- c("orig", "dest", "distance")

univ_trips_df <- read.csv(univ_pa_trips_filename)

names(univ_trips_df) <- c("orig", "dest", "UHC_ON_NCSU_AM", "UHC_ON_NCSU_MD", "UHC_ON_NCSU_PM", "UHC_ON_NCSU_NT",
                          "UHC_OFF_NCSU_AM", "UHC_OFF_NCSU_MD", "UHC_OFF_NCSU_PM", "UHC_OFF_NCSU_NT",
                          "UHO_ON_NCSU_AM", "UHO_ON_NCSU_MD", "UHO_ON_NCSU_PM", "UHO_ON_NCSU_NT",
                          "UHO_OFF_NCSU_AM", "UHO_OFF_NCSU_MD", "UHO_OFF_NCSU_PM", "UHO_OFF_NCSU_NT",
                          "UCO_NCSU_AM", "UCO_NCSU_MD", "UCO_NCSU_PM", "UCO_NCSU_NT",
                          "UCC_NCSU_AM", "UCC_NCSU_MD", "UCC_NCSU_PM", "UCC_NCSU_NT",
                          "UC1_NCSU_AM", "UC1_NCSU_MD", "UC1_NCSU_PM", "UC1_NCSU_NT")

survey_trips_df <- read.csv(survey_trips_filename)

survey_trips_df <- survey_trips_df %>% 
  filter(!is.na(Weight))

distance_bins_df <- tibble(bin = seq(from = 0, to = 30, by = 1)) %>%
  mutate(label = paste0(bin, " to ", lead(bin))) %>%
  mutate(label = str_replace(label, "NA", "Inf")) %>%
  mutate(index = row_number())

purpose_map_df <- tibble(
  Trip_Purpose = c("UHC", "UHC", "UHO", "UHO", "UCO", "UCO", "UC1", "UC1", "UCC", "UCC", "UOO", "UOO"),
  campus = c("ON", "OFF", "ON", "OFF", "ON", "OFF", "ON", "OFF", "ON", "OFF", "ON", "OFF"),
  purpose = c("UHC-ON", "UHC-OFF", "UHO-ON", "UHO-OFF", "UCO", "UCO", "UC1", "UC1", "UCC", "UCC", "UOO", "UOO")
)

observed_trips_df <- survey_trips_df %>%
  filter(!is.na(distance_zonetozone)) %>%
  filter(Trip_Purpose != "99") %>%
  filter(Trip_Purpose != "UOO") %>%
  mutate(distance = distance_zonetozone) %>%
  mutate(campus = if_else(On_campus == 1,"ON","OFF")) %>%
  left_join(., purpose_map_df, by = c("Trip_Purpose", "campus")) %>%
  select(orig = TAZ_o, dest = TAZ_d, purpose, distance, trips = Weight) %>%
  mutate(type = ifelse(((purpose == "UHC-OFF")| (purpose == "UHO-OFF")), purpose, "ON-CAMPUS"))

obs_avg_trip_length_df <- observed_trips_df %>%
  mutate(trip_time_distance = trips * distance) %>%
  group_by(type) %>%
  summarize(value = round(sum(trip_time_distance)/sum(trips), 2)) %>%
  mutate(source = "Observed")

obs_tlfd_df <- observed_trips_df %>%
  filter(distance <= 30) %>%
  mutate(distance_bin = cut(distance,
                            breaks = distance_bins_df$bin,
                            labels = FALSE, 
                            right = TRUE)
  ) %>%
  left_join(., select(distance_bins_df, index, label), by = c("distance_bin" = "index")) %>%
  rename(distance_bin_label = label) %>%
  group_by(type, distance_bin_label) %>%
  summarise(trips = sum(trips)) %>%
  mutate(share = trips / sum(trips)) %>%
  mutate(source = "Observed")

simulated_trips_df <- univ_trips_df %>%
  mutate(
    `UHC-ON` = UHC_ON_NCSU_AM + UHC_ON_NCSU_MD + UHC_ON_NCSU_PM + UHC_ON_NCSU_NT,
    `UHC-OFF` = UHC_OFF_NCSU_AM + UHC_OFF_NCSU_MD + UHC_OFF_NCSU_PM + UHC_OFF_NCSU_NT,
    `UHO-ON` = UHO_ON_NCSU_AM + UHO_ON_NCSU_MD + UHO_ON_NCSU_PM + UHO_ON_NCSU_NT,
    `UHO-OFF` = UHO_OFF_NCSU_AM + UHO_OFF_NCSU_MD + UHO_OFF_NCSU_PM + UHO_OFF_NCSU_NT,
    `UCO` = UCO_NCSU_AM + UCO_NCSU_MD + UCO_NCSU_PM + UCO_NCSU_NT,
    `UCC` = UCC_NCSU_AM + UCC_NCSU_MD + UCC_NCSU_PM + UCC_NCSU_NT,
    `UC1` = UC1_NCSU_AM + UC1_NCSU_MD + UC1_NCSU_PM + UC1_NCSU_NT
  ) %>%
  left_join(skim_df, by = c("orig", "dest")) %>%
  filter(!is.na(distance)) %>%
  select(orig, dest, distance, `UHC-ON`, `UHC-OFF`, `UHO-ON`, `UHO-OFF`, UCO, UCC, UC1) %>%
  pivot_longer(c("UHC-ON", "UHC-OFF", "UHO-ON", "UHO-OFF", "UCO", "UCC", "UC1"), names_to = "purpose", values_to = "trips") %>%
  filter(trips > 0) %>%
  mutate(type = ifelse(((purpose == "UHC-OFF")| (purpose == "UHO-OFF")), purpose, "ON-CAMPUS"))

sim_avg_trip_length_df <- simulated_trips_df %>%
  mutate(trip_time_distance = trips * distance) %>%
  group_by(type) %>%
  summarize(value = round(sum(trip_time_distance)/sum(trips), 2)) %>%
  mutate(source = "Simulated")

sim_tlfd_df <- simulated_trips_df %>%
  filter(distance <= 30) %>%
  mutate(distance_bin = cut(distance,
                            breaks = distance_bins_df$bin,
                            labels = FALSE, 
                            right = TRUE)
  ) %>%
  left_join(., select(distance_bins_df, index, label), by = c("distance_bin" = "index")) %>%
  rename(distance_bin_label = label) %>%
  group_by(type, distance_bin_label) %>%
  summarise(trips = sum(trips)) %>%
  mutate(share = trips / sum(trips)) %>%
  mutate(source = "Simulated")

trip_length_df <- obs_tlfd_df %>%
  rename(obs_share = share) %>%
  select(type, distance_bin_label, obs_share) %>%
  full_join(select(sim_tlfd_df, type, distance_bin_label, sim_share = share), by = c("type", "distance_bin_label")) %>%
  replace_na(list(obs_share = 0, sim_share = 0))

distance_dist_df <- bind_rows(obs_tlfd_df, sim_tlfd_df) 

avg_trip_length_df <- bind_rows(obs_avg_trip_length_df, sim_avg_trip_length_df)



write.csv(avg_trip_length_df, paste0(interim_dir,"avg_trip_lengths.csv"), row.names = F)

write.csv(distance_dist_df, paste0(interim_dir,"distance_distribution.csv"), row.names = F)
  
write.csv(trip_length_df, paste0(interim_dir,"trip_length_distribution.csv"), row.names = F)
