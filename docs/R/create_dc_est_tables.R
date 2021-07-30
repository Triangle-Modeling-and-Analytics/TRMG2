library(tidyverse)

hh_raw <- read_csv("data/output/_PRIVATE/survey_processing/hh_processed.csv")
trips_raw <- read_csv("data/output/_PRIVATE/survey_processing/trips_processed.csv")
cluster <- read_csv("data/input/dc/cluster_def.csv")

# OME
df_ome <- trips_raw %>%
  filter(trip_type == "N_HB_OME_All") %>%
  left_join(
    hh_raw %>%
      select(hhid, hh_income_midpt, num_adults),
    by = "hhid"
  ) %>%
  group_by(tour_num, a_taz) %>%
  slice(1) %>%
  mutate(
    HomeTAZ = ifelse(pa_flag == 1, o_taz, d_taz),
    AvgIncPerAdult = hh_income_midpt / num_adults,
    LowIncome = ifelse(AvgIncPerAdult < 75000, 1, 0)
  ) %>%
  left_join(cluster, by = c("HomeTAZ" = "TAZ")) %>%
  rename(Home_Cluster = Cluster) %>%
  left_join(cluster, by = c("o_taz" = "TAZ")) %>%
  rename(O_Cluster = Cluster) %>%
  left_join(cluster, by = c("d_taz" = "TAZ")) %>%
  rename(D_Cluster = Cluster) %>%
  mutate(ZeroAutoHH = ifelse(num_vehicles == 0, 1, 0)) %>%
  ungroup() %>%
  select(
    EstDataID = seqtripid, personid, hhid, HomeTAZ, o_taz, d_taz, 
    HHIncomeMP = hh_income_midpt, AvgIncPerAdult,
    LowIncome, Home_Cluster, O_Cluster, D_Cluster, Segment = choice_segment,
    ZeroAutoHH
  )
write_csv(df_ome, "ome_est_tbl.csv")
