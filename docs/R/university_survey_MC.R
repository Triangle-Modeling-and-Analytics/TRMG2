

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


# Read data -------------------------------------------------------------------
trip_subset_df <-readRDS(trip_subset_filename)


# Mode Split -------------------------------------------------------------------

## Mode Split all trips --------------------------------------------------------

modesplit_alltrips_df<-trip_subset_df %>%
  filter(!is.na(Walk_W)) %>%
  summarize(Temp_Total = sum(Weight),
            TotalBicycle = sum(Bicycle_W),
            TotalWalk = sum(Walk_W),
            TotalCar = sum(Car_W),
            TotalCarpool = sum(Carpool_W),
            TotalBus = sum(Bus_W),
            TotalOther = sum(Other_W),
            Temp_Pct_Bicycle = TotalBicycle/Temp_Total * 100,
            Temp_Pct_Walk = TotalWalk/Temp_Total * 100,
            Temp_Pct_Car = TotalCar/Temp_Total * 100,
            Temp_Pct_Carpool = TotalCarpool/Temp_Total * 100,
            Temp_Pct_Bus = TotalBus/Temp_Total * 100,
            Temp_Pct_Other = TotalOther/Temp_Total * 100) 

modesplit_bypurpose_campusbasedtrips_df<- modesplit_alltrips_df %>%
  mutate(Pct_Auto = Temp_Pct_Car + Temp_Pct_Carpool) %>%
  select('Percent Bicycle' = Temp_Pct_Bicycle,
         'Percent Walk' = Temp_Pct_Walk,
         'Percent Transit' = Temp_Pct_Bus,
         'Percent Auto' = Pct_Auto,
         'Percent Other' = Temp_Pct_Other)

calibrationtargets_alltrips_df<- modesplit_alltrips_df %>%
  summarize(Total = sum(Temp_Total) - sum(TotalOther),
            Pct_Bicycle = sum(TotalBicycle)/Total * 100,
            Pct_Walk = sum(TotalWalk)/Total * 100,
            Pct_Auto = (sum(TotalCar) + sum(TotalCarpool))/Total * 100) %>%
  rowwise() %>%
  mutate(Pct_Bus = 100.00 - (Pct_Bicycle + Pct_Walk + Pct_Auto),
         Pct_AllModes = Pct_Bicycle + Pct_Walk + Pct_Auto + Pct_Bus) %>%
  ungroup() %>%
  select('Percent Bicycle' = Pct_Bicycle, 
         'Percent Walk'= Pct_Walk, 
         'Percent Transit'= Pct_Bus, 
         'Percent Auto'= Pct_Auto, 
         'Total' = Pct_AllModes) 
## Mode Split campus-based trips-----------------------------------------------

modesplit_campusbased_df<-trip_subset_df %>%
  filter(Trip_Purpose !="99") %>%
  filter(Trip_Purpose != "UOO") %>%
  filter(!is.na(Walk_W)) %>%
  filter(Trip_Purpose == "UC1" | Trip_Purpose == "UCO" | Trip_Purpose == "UCC")%>%
  mutate(Trip_Purpose_long = case_when(Trip_Purpose == "UCO" ~ "Campus-Other",
                                       Trip_Purpose == "UC1"  ~ "On-campus",
                                       Trip_Purpose == "UCC" ~ "Campus-to-campus")) %>%
  filter(!is.na(Trip_Purpose_long))%>%
  group_by(Trip_Purpose_long)%>% 
  summarize(Temp_Total = sum(Weight),
            TotalBicycle = sum(Bicycle_W),
            TotalWalk = sum(Walk_W),
            TotalCar = sum(Car_W),
            TotalCarpool = sum(Carpool_W),
            TotalBus = sum(Bus_W),
            TotalOther = sum(Other_W),
            Temp_Pct_Bicycle = TotalBicycle/Temp_Total * 100,
            Temp_Pct_Walk = TotalWalk/Temp_Total * 100,
            Temp_Pct_Car = TotalCar/Temp_Total * 100,
            Temp_Pct_Carpool = TotalCarpool/Temp_Total * 100,
            Temp_Pct_Bus = TotalBus/Temp_Total * 100,
            Temp_Pct_Other = TotalOther/Temp_Total * 100) 

modesplit_bypurpose_campusbasedtrips_df<- modesplit_campusbased_df %>%
  mutate(Pct_Auto = Temp_Pct_Car + Temp_Pct_Carpool) %>%
  select('Trip Purpose' = Trip_Purpose_long,
         'Percent Bicycle' = Temp_Pct_Bicycle,
         'Percent Walk' = Temp_Pct_Walk,
         'Percent Transit' = Temp_Pct_Bus,
         'Percent Auto' = Pct_Auto,
         'Percent Other' = Temp_Pct_Other)

calibrationtargets_bypurpose_campusbasedtrips_df<- modesplit_campusbased_df %>%
  group_by(Trip_Purpose_long) %>%
  summarize(Total = sum(Temp_Total) - sum(TotalOther),
            Pct_Bicycle = sum(TotalBicycle)/Total * 100,
            Pct_Walk = sum(TotalWalk)/Total * 100,
            Pct_Auto = (sum(TotalCar) + sum(TotalCarpool))/Total * 100) %>%
  rowwise() %>%
  mutate(Pct_Bus = 100.00 - (Pct_Bicycle + Pct_Walk + Pct_Auto),
         Pct_AllModes = Pct_Bicycle + Pct_Walk + Pct_Auto + Pct_Bus) %>%
  ungroup() %>%
  select('Trip Purpose' = Trip_Purpose_long, 
         'Percent Bicycle' = Pct_Bicycle, 
         'Percent Walk'= Pct_Walk, 
         'Percent Transit'= Pct_Bus, 
         'Percent Auto'= Pct_Auto, 
         'Total' = Pct_AllModes) 


## Mode Split on-campus students home-based trips-------------------------------

modesplit_bypurpose_oncampus_df<-trip_subset_df %>%
filter(Trip_Purpose !="99") %>%
  filter(Trip_Purpose != "UOO") %>%
  filter(!is.na(Walk_W)) %>%
  filter(On_campus == 1) %>%
  filter(Trip_Purpose == "UHO" | Trip_Purpose == "UHC")%>%
  mutate(Trip_Purpose_long = case_when(Trip_Purpose == "UHC" ~ "Home-Campus",
                                       Trip_Purpose == "UHO" ~ "Home-Other")) %>%
  filter(!is.na(Trip_Purpose_long))%>%
  group_by(Trip_Purpose_long)%>% 
  summarize(Temp_Total = sum(Weight),
            TotalBicycle = sum(Bicycle_W),
            TotalWalk = sum(Walk_W),
            TotalCar = sum(Car_W),
            TotalCarpool = sum(Carpool_W),
            TotalBus = sum(Bus_W),
            TotalOther = sum(Other_W),
            Temp_Pct_Bicycle = TotalBicycle/Temp_Total * 100,
            Temp_Pct_Walk = TotalWalk/Temp_Total * 100,
            Temp_Pct_Car = TotalCar/Temp_Total * 100,
            Temp_Pct_Carpool = TotalCarpool/Temp_Total * 100,
            Temp_Pct_Bus = TotalBus/Temp_Total * 100,
            Temp_Pct_Other = TotalOther/Temp_Total * 100) 

modesplit_bypurpose_oncampus_2_df<- modesplit_bypurpose_oncampus_df %>%
  mutate(Pct_Auto = Temp_Pct_Car + Temp_Pct_Carpool) %>%
  select('Trip Purpose' = Trip_Purpose_long,
         'Percent Bicycle' = Temp_Pct_Bicycle,
         'Percent Walk' = Temp_Pct_Walk,
         'Percent Transit' = Temp_Pct_Bus,
         'Percent Auto' = Pct_Auto,
         'Percent Other' = Temp_Pct_Other)

calibrationtargets_bypurpose_oncampus_df<- modesplit_bypurpose_oncampus_df %>%
  ungroup() %>%
  group_by(Trip_Purpose_long) %>%
  summarize(Total = sum(Temp_Total) - sum(TotalOther),
            Pct_Bicycle = sum(TotalBicycle)/Total * 100,
            Pct_Walk = sum(TotalWalk)/Total * 100,
            Pct_Auto = (sum(TotalCar) + sum(TotalCarpool))/Total * 100) %>%
  rowwise() %>%
  mutate(Pct_Bus = 100.00 - (Pct_Bicycle + Pct_Walk + Pct_Auto),
         Pct_AllModes = Pct_Bicycle + Pct_Walk + Pct_Auto + Pct_Bus) %>%
  ungroup() %>%
  select('Trip Purpose' = Trip_Purpose_long, 
         'Percent Bicycle' = Pct_Bicycle, 
         'Percent Walk'= Pct_Walk, 
         'Percent Transit'= Pct_Bus, 
         'Percent Auto'= Pct_Auto, 
         'Total' = Pct_AllModes) 

## Mode Split off-campus students home-based trips------------------------------

modesplit_bypurpose_offcampus_df<-trip_subset_df %>%
  filter(Trip_Purpose !="99") %>%
  filter(Trip_Purpose != "UOO") %>%
  filter(On_campus == 0) %>%
  filter(!is.na(Walk_W)) %>%
  mutate(Trip_Purpose_long = case_when(Trip_Purpose == "UHC" ~ "Home-Campus",
                                        Trip_Purpose == "UHO" ~ "Home-Other"))%>%  
  filter(!is.na(Trip_Purpose_long))%>%
  group_by(Trip_Purpose_long)%>%
  summarize(Temp_Total = sum(Weight),
            TotalBicycle = sum(Bicycle_W),
            TotalWalk = sum(Walk_W),
            TotalCar = sum(Car_W),
            TotalCarpool = sum(Carpool_W),
            TotalBus = sum(Bus_W),
            TotalOther = sum(Other_W),
            Temp_Pct_Bicycle = TotalBicycle/Temp_Total * 100,
            Temp_Pct_Walk = TotalWalk/Temp_Total * 100,
            Temp_Pct_Car = TotalCar/Temp_Total * 100,
            Temp_Pct_Carpool = TotalCarpool/Temp_Total * 100,
            Temp_Pct_Bus = TotalBus/Temp_Total * 100,
            Temp_Pct_Other = TotalOther/Temp_Total * 100)

modesplit_bypurpose_offcampus_2_df<- modesplit_bypurpose_offcampus_df %>%
  mutate(Pct_Auto = Temp_Pct_Car + Temp_Pct_Carpool) %>%
select('Trip Purpose' = Trip_Purpose_long,
       'Percent Bicycle' = Temp_Pct_Bicycle,
       'Percent Walk' = Temp_Pct_Walk,
       'Percent Transit' = Temp_Pct_Bus,
       'Percent Auto' = Pct_Auto,
       'Percent Other' = Temp_Pct_Other)

calibrationtargets_bypurpose_offcampus_df <- modesplit_bypurpose_offcampus_df %>%
  group_by(Trip_Purpose_long) %>%
  summarize(Total = Temp_Total - TotalOther,
            Pct_Bicycle = TotalBicycle/Total * 100,
            Pct_Walk = TotalWalk/Total * 100,
            Pct_Auto = (TotalCar + TotalCarpool)/Total * 100,
            Pct_Bus = 100.00 - (Pct_Bicycle + Pct_Walk + Pct_Auto),
            Pct_AllModes = Pct_Bicycle + Pct_Walk + Pct_Auto + Pct_Bus) %>%
  select('Trip Purpose' = Trip_Purpose_long, 
         'Percent Bicycle' = Pct_Bicycle, 
         'Percent Walk'= Pct_Walk, 
         'Percent Transit'= Pct_Bus, 
         'Percent Auto'= Pct_Auto, 
         'Total' = Pct_AllModes) 

# plots mode split - all purposes except UC1-----------------------------------------------------------

trips_bypurpose_plot <-trip_subset_df %>%
  filter(Trip_Purpose != "99")%>%
  filter(Primary_Mode != "NA")%>%

  filter(Trip_Purpose != "UC1") %>%
  ggplot(aes(Trip_Purpose, fill=Primary_Mode)) + geom_bar(position="dodge")

# plots mode split - only UC1-----------------------------------------------------------

trips_bypurpose_oncampusUC1_plot <-trip_subset_df %>%
  filter(Trip_Purpose != "99")%>%
  filter(Primary_Mode != "NA")%>%

  filter(Trip_Purpose == "UC1") %>%
  ggplot(aes(Trip_Purpose, fill=Primary_Mode)) + geom_bar(position="dodge") + 
  geom_hline(yintercept = 20)

# write results ------------------------------------------------------
calibrationtargets_bypurpose_oncampus<-write_csv(calibrationtargets_bypurpose_oncampus_df,paste0(univ_dir,"calibrationtargets_bypurpose_oncampus.CSV"))
calibrationtargets_bypurpose_offcampus<-write_csv(calibrationtargets_bypurpose_offcampus_df, paste0(univ_dir,"calibrationtargets_bypurpose_offcampus.CSV"))
calibrationtargets_alltrips_df <-write_csv(calibrationtargets_alltrips_df, paste0(univ_dir,"calibrationtargets_alltrips.CSV"))

