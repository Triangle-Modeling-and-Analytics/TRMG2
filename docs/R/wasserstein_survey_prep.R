# This script creates additional trips in the survey that travel to zones near
# the actual trip destination. These records are given less weight than the
# original trip. The idea is that standard GEV estimation will get partial
# credit for guessing zones near the actual zone chosen.

library(tidyverse)

skim <- read_csv("../../working_files/choice_model_estimation/dc/length_skim.csv")
skim_filtered <- skim %>%
  rename(skim_length = `Length (Skim)`) %>%
  filter(skim_length <= 15)
survey <- read_csv("data/output/_PRIVATE/survey_processing/trips_processed.csv") %>%
  select(seqtripid, trip_type, o_taz, d_taz, tod, weight = trip_weight_combined)

create_extra_trips <- survey %>%
  left_join(skim_filtered, by = c("d_taz" = "Origin")) %>%
  arrange(seqtripid, skim_length) %>%
  group_by(seqtripid) %>%
  mutate(
    new_weight1 = 1 / skim_length ^ 2 * weight,
    total_new_weight1 = sum(new_weight1),
    new_weight = new_weight1 * weight / total_new_weight1
  )


# # Check TLFD of NHB trips
# survey <- read_csv("data/output/_PRIVATE/survey_processing/trips_processed.csv")
# survey %>%
#   filter(homebased == "NH")
# mean(survey$skim_length, na.rm = TRUE)
# quantile(survey$skim_length, probs = seq(from = .05, to = 1, by = .05), na.rm = TRUE) %>%
#   as.data.frame()
