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
univ_dir<-"data/output/"

trip_subset_filename <- paste0(private_dir,"Trip_subset_df.RDS")


# Read data -------------------------------------------------------------------
trip_subset_df <-readRDS(trip_subset_filename)

# Histogram trip distance 

Test_UC1_Tripdistance_histogram<-trip_subset_df %>% 
  filter(Trip_Purpose == "UC1" & distance_miles<3)%>%
  ggplot(aes(distance_miles,after_stat(density), color = On_campus, fill = On_campus)) + 
  geom_histogram(position = "identity", alpha = 0.5)

Test_UC1_Tripdistance_histogram + labs(title = "Trip Length Distribution - UC1", 
                           subtitle = "for off-campus students (On_campus== 0) and on-campus students (On_campus == 1) students",  
                           caption = "Source: NCSU survey (unweighted)")

UC1_Oncampus_Tripdistance_histogram<-trip_subset_df %>% 
  ungroup()%>%
  filter(Trip_Purpose == "UC1" & On_campus == 1 & distance_miles<2)%>%
  ggplot(aes(distance_miles,after_stat(density))) + 
  geom_histogram()


UC1_Oncampus_Tripdistance_histogram + labs(title = "Trip Length Distribution - UC1 Trips by On-campus students", 
                              subtitle ="", 
                              caption = ("Source: NCSU survey (unweighted)"))


UC1_Offcampus_Tripdistance_histogram<-trip_subset_df %>% 
  filter(Trip_Purpose == "UC1" & On_campus == 0 & distance_miles<2)%>%
  ggplot(aes(distance_miles)) + 
  geom_histogram()


UC1_Offcampus_Tripdistance_histogram + labs(title = "Trip Length Distribution - UC1 Trips by Off-campus students", 
                                           subtitle="", 
                                           caption = ("Source: NCSU survey (unweighted)"))


# Histogram trip distance zone to zone

zonetozonedistance_allpurposes_histogram<-trip_subset_df %>%
  filter(Trip_Purpose !="99")%>%
  filter(Trip_Purpose !="UC1")%>%
  filter(distance_zonetozone < 30)%>%
  group_by(On_campus,Trip_Purpose) %>%
  ggplot(aes(distance_zonetozone)) +
  geom_histogram(binwidth = 1) +
  facet_grid(On_campus ~ Trip_Purpose)

zonetozonedistance_allpurposes_histogram

zonetozonedistance_UC1_histogram<-trip_subset_df %>%
  filter(Trip_Purpose =="UC1")%>%
  group_by(On_campus) %>%
  ggplot(aes(distance_zonetozone)) +
  geom_histogram(binwidth = 1) +
  facet_grid(On_campus ~ .)
zonetozonedistance_UC1_histogram

# Mode 
# also split by Have_car

#mode_barchart <-trip_subset_df %>%
  filter(Trip_Purpose !="99") %>%
  group_by(On_campus,Trip_Purpose) %>%
  ggplot(aes(Primary_Mode, fill=Primary_Mode)) +
  geom_bar() +
  facet_grid(On_campus ~ Trip_Purpose)
#mode_barchart

trips_bypurpose_oncampus<-trip_subset_df %>%
  filter(Trip_Purpose !="99") %>%
  filter(!is.na(Walk)) %>%
  filter(On_campus == 1) %>%
  group_by(Trip_Purpose)%>%
  summarize(Total = n(),
            Bicycle = sum(Bicycle),
            Walk = sum(Walk),
            Car = sum(Car),
            Carpool = sum(Carpool),
            Bus = sum(Bus),
            Other = sum(Other)) %>%
  kable(digits = 1) %>%
  kable_styling(full_width = FALSE)

trips_bypurpose_offcampus<-trip_subset_df %>%
  filter(Trip_Purpose !="99") %>%
  filter(!is.na(Walk)) %>%
  filter(On_campus == 0) %>%
  group_by(Trip_Purpose)%>%
  summarize(Total = n(),
            Bicycle = sum(Bicycle),
            Walk = sum(Walk),
            Car = sum(Car),
            Carpool = sum(Carpool),
            Bus = sum(Bus),
            Other = sum(Other)) %>%
  kable(digits = 1) %>%
  kable_styling(full_width = FALSE)

trips_bypurpose_oncampus_pct<-trip_subset_df %>%
  filter(Trip_Purpose !="99") %>%
  filter(!is.na(Walk)) %>%
  filter(On_campus == 1) %>%
  group_by(Trip_Purpose)%>%
  summarize(Total = n(),
            Bicycle = sum(Bicycle)/count * 100,
            Walk = sum(Walk)/count * 100,
            Car = sum(Car)/count * 100,
            Carpool = sum(Carpool)/count * 100,
            Bus = sum(Bus)/count * 100,
            Other = sum(Other)/count * 100) %>%
  kable(digits = 1) %>%
  kable_styling(full_width = FALSE)

trips_bypurpose_offcampus<-trip_subset_df %>%
  filter(Trip_Purpose !="99") %>%
  filter(On_campus == 0) %>%
  filter(!is.na(Walk)) %>%
  group_by(Trip_Purpose)%>%
  summarize(Total = n(),
            Bicycle = sum(Bicycle)/count * 100,
            Walk = sum(Walk)/count * 100,
            Car = sum(Car)/count * 100,
            Carpool = sum(Carpool)/count * 100,
            Bus = sum(Bus)/count * 100,
            Other = sum(Other)/count * 100) %>%
  kable(digits = 1) %>%
  kable_styling(full_width = FALSE)



  
  


