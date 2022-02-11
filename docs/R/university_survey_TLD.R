
# Packages ---------------------------------------------------------------------
packages_vector <- c("tidyverse",
                     "ggplot2",
                     "kableExtra",
                     "readr")

need_to_install <- packages_vector[!(packages_vector %in% installed.packages()[,"Package"])]
if (length(need_to_install)) install.packages(need_to_install)
for (package in packages_vector){
  library(package, character.only = TRUE)
}

knitr::opts_chunk$set(echo = FALSE)
options(dplyr.summarise.inform = FALSE)
options(scipen = 999)

# Remote I/O -------------------------------------------------------------------
private_dir <- "data/input/_PRIVATE/"
input_dir <-"data/input/university/"
univ_dir<-"data/output/university/"

trip_subset_filename <- paste0(private_dir,"Trip_subset_df.RDS")


# Read data -------------------------------------------------------------------
trip_subset_df <-readRDS(trip_subset_filename)
   

# Histogram trip distance zone to zone ----------------------------------------
purpose_map_df <- tibble(code = c("UHC", "UHO", "UCO", "UC1", "UCC", "UOO"),
                         name = c("Home-Campus",
                                  "Home-Other",
                                  "Campus-Other",
                                  "On-campus",
                                  "Campus-to-campus",
                                  "Other-to-other"))

trip_subset2_df <-trip_subset_df %>%
  filter(!is.na(distance_zonetozone))

# histograms
zonetozonedistance_bypurposeHB_histogram<-trip_subset2_df %>%
  filter(Trip_Purpose =="UHO"| Trip_Purpose =="UHC") %>%
  filter(distance_zonetozone < 30)%>%
  left_join(., purpose_map_df, by = c("Trip_Purpose" = "code"))%>%
mutate(On_campus = if_else(On_campus == 0, "Off-campus", "On-campus")) %>%
  group_by(On_campus,name) %>%
  rename(`Trip Purpose` = name) %>%
  rename(`On-campus`= On_campus)%>%
  ggplot(aes(distance_zonetozone)) +
  geom_histogram(binwidth = 1) +
  facet_grid(`On-campus` ~ `Trip Purpose`)

zonetozonedistance_bypurposeCB_histogram<-trip_subset2_df %>%
  filter(Trip_Purpose =="UCO" | Trip_Purpose =="UCC") %>%
  filter(distance_zonetozone < 30)%>%
  left_join(., purpose_map_df, by = c("Trip_Purpose" = "code"))%>%
  group_by(name) %>%
  rename(`Trip Purpose` = name) %>%
  ggplot(aes(distance_zonetozone)) +
  geom_histogram(binwidth = 1) +
facet_grid(`Trip Purpose`~ .)

zonetozonedistance_UC1_histogram<-trip_subset2_df %>%
  filter(Trip_Purpose =="UC1")%>%
  ggplot(aes(distance_zonetozone)) +
  geom_histogram(binwidth = 1) 

# tables

avgdistance_HB_df <- trip_subset2_df %>%
  filter(!is.na(distance_zonetozone))%>%
  filter(Trip_Purpose =="UHO"| Trip_Purpose =="UHC") %>%
  mutate(On_campus = if_else(On_campus == 1,"On-campus","Off-campus")) %>%
  left_join(., purpose_map_df, by = c("Trip_Purpose" = "code"))%>%
  group_by(name, On_campus) %>%
  summarize(total = n(),
            totaldistance = sum(distance_zonetozone),
            avg = totaldistance/total)%>%
  select('Trip Purpose'= name, 
         "Home Location" = On_campus,
         Count = total,
         "Average Distance" = avg)

         
avgdistance_NHB_df <- trip_subset2_df %>%
  filter(Trip_Purpose =="UCO" | Trip_Purpose =="UCC" | Trip_Purpose == "UC1") %>%
  filter(!is.na(distance_zonetozone))%>%
  left_join(., purpose_map_df, by = c("Trip_Purpose" = "code"))%>%
  group_by(name) %>%
  summarize(total = n(),
            totaldistance = sum(distance_zonetozone),
            avg= totaldistance/total) %>%
  select('Trip Purpose'= name,
         Count = total,
         "Average Distance" = avg)

# targets for calibration

avgdistance_CB_HBoncampus_df <-trip_subset2_df %>%
  filter(Trip_Purpose =="UCO" | Trip_Purpose =="UCC" | Trip_Purpose == "UC1" | 
           (Trip_Purpose =="UHO" & On_campus == 1) |(Trip_Purpose =="UHC" & On_campus == 1)) %>%
  filter(!is.na(distance_zonetozone))%>%
  summarize(total = n(),
            totaldistance = sum(distance_zonetozone),
            avg = totaldistance/total) %>%
  mutate('Trip Purpose' = "Campus-based and Home-based by on-campus students") %>%
  select('Trip Purpose', 
         Count = total,
         "Average Distance" = avg)

# write

write_csv(avgdistance_HB_df,paste0(univ_dir,"avgdistance_HB_df.csv"))
write_csv(avgdistance_CB_HBoncampus_df,paste0(univ_dir,"avgdistance_CB_HBoncampus_df.csv"))

  
