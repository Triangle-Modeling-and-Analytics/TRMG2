
# Packages ---------------------------------------------------------------------
packages_vector <- c("tidyverse",
                     "ggplot2",
                     "kableExtra"
                     
)

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
apply_productions_filename <- paste0(univ_dir,"Apply_Productions.RDS")

# Read data -------------------------------------------------------------------
trip_subset_df <-readRDS(trip_subset_filename)
Apply_Productions_df <-readRDS(apply_productions_filename)    

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
#  filter(Trip_Purpose !="99")%>%
#  filter(Trip_Purpose !="UC1")%>%
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
#  filter(Trip_Purpose !="99")%>%
#  filter(Trip_Purpose !="UC1")%>%
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
#  filter(Trip_Purpose !="99")%>%
  ggplot(aes(distance_zonetozone)) +
  geom_histogram(binwidth = 1) 

# old tables

trip_length_df <- trip_subset2_df %>%
  filter(Trip_Purpose !="99")%>%
  left_join(., purpose_map_df, by = c("Trip_Purpose" = "code"))%>%
  mutate(Distance = case_when(distance_zonetozone <= 2 ~ "1. up to 2 miles",
                              distance_zonetozone > 2 & distance_zonetozone <=5 ~ "2. up to 5 miles",
                              distance_zonetozone > 5 & distance_zonetozone <= 10 ~ "3. up to 10 miles",
                              distance_zonetozone > 10 ~ "4. more than 10 miles",
                              TRUE ~ "5. n/a")) %>%
  select(Trip_Purpose, distance_zonetozone, Distance, On_campus)

totals_df <- trip_length_df %>%
  filter(Distance !="5. n/a")%>%
  group_by(Trip_Purpose) %>%
  summarize(total = n())

zonetozonedistance_bypurpose_df <- trip_length_df %>%
  filter(Trip_Purpose !="99")%>%
  left_join(totals_df, by = "Trip_Purpose") %>%
  group_by(Distance,Trip_Purpose,total) %>%
  summarize(count = n(),
            .groups = "drop") %>%
  mutate(Share = count/total * 100) %>%
  select(-c(count, total))%>%
  pivot_wider(names_from = "Trip_Purpose", values_from = "Share")

#new table

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
         

