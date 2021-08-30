

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
## Mode Split on-campus students -----------------------------------------------
### unweighted -----------------------------------------------------------------
unweighted_modesplit_bypurpose_oncampus_df<-trip_subset_df %>%
  filter(Trip_Purpose !="99") %>%
  filter(Trip_Purpose != "UOO") %>%
  filter(!is.na(Walk)) %>%
  filter(On_campus == 1) %>%
  mutate(TripPurpose_recode = case_when(Trip_Purpose == "UC1" ~ "CampusCampus",
                                        Trip_Purpose == "UCC" ~ "InterCampus",
                                        Trip_Purpose == "UCO" ~ "CampusOther",
                                        Trip_Purpose == "UHC" ~ "CampusCampus",
                                        Trip_Purpose == "UHO" ~ "CampusOther"))%>%
           group_by(Trip_Purpose, TripPurpose_recode)%>% 
    summarize(Temp_Total = n(),
              TotalBicycle = sum(Bicycle),
              TotalWalk = sum(Walk),
              TotalCar = sum(Car),
              TotalCarpool = sum(Carpool),
              TotalBus = sum(Bus),
              TotalOther = sum(Other),
              Temp_Pct_Bicycle = TotalBicycle/Temp_Total * 100,
              Temp_Pct_Walk = TotalWalk/Temp_Total * 100,
              Temp_Pct_Car = TotalCar/Temp_Total * 100,
              Temp_Pct_Carpool = TotalCarpool/Temp_Total * 100,
              Temp_Pct_Bus = TotalBus/Temp_Total * 100,
              Temp_Pct_Other = TotalOther/Temp_Total * 100)
unweighted_modesplit_bypurpose_oncampus_df



### weighted -----------------------------------------------------------------
modesplit_bypurpose_oncampus_df<-trip_subset_df %>%
  filter(Trip_Purpose !="99") %>%
  filter(Trip_Purpose != "UOO") %>%
  filter(!is.na(Walk_W)) %>%
  filter(On_campus == 1) %>%
  mutate(TripPurpose_recode = case_when(Trip_Purpose == "UC1" ~ "CampusCampus",
                                        Trip_Purpose == "UCC" ~ "InterCampus",
                                        Trip_Purpose == "UCO" ~ "CampusOther",
                                        Trip_Purpose == "UHC" ~ "CampusCampus",
                                        Trip_Purpose == "UHO" ~ "CampusOther"))%>%
  group_by(Trip_Purpose, TripPurpose_recode)%>% 
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
  modesplit_bypurpose_oncampus_df

modesplit_bypurpose_oncampus_2_df<- modesplit_bypurpose_oncampus_df %>%
  select(Trip_Purpose,
         Pct_Bicycle = Temp_Pct_Bicycle,
         Pct_Walk = Temp_Pct_Walk,
         Pct_Car = Temp_Pct_Car,
         Pct_Carpool = Temp_Pct_Carpool,
         Pct_Bus = Temp_Pct_Bus,
         Pct_Other = Temp_Pct_Other)


modesplit_byrecodedpurpose_oncampus_df <- modesplit_bypurpose_oncampus_df %>%
  ungroup() %>%
  select(-c(Trip_Purpose)) %>%
  group_by(TripPurpose_recode) %>%
  summarize(Total = sum(Temp_Total) - sum(TotalOther),
            Pct_Bicycle = sum(TotalBicycle)/Total * 100,
            Pct_Walk = sum(TotalWalk)/Total * 100,
            Pct_Car = (sum(TotalCar) + sum(TotalCarpool))/Total * 100) %>%
  rowwise() %>%
  mutate(Pct_Bus = 100.00 - (Pct_Bicycle + Pct_Walk + Pct_Car),
         Pct_AllModes = Pct_Bicycle + Pct_Walk + Pct_Car + Pct_Bus) %>%
  ungroup() %>%
  select(TripPurpose_recode, 
         Total, 
         Pct_Bicycle, 
         Pct_Walk, 
         Pct_Car, 
         Pct_Bus, 
         Pct_AllModes) 
modesplit_byrecodedpurpose_oncampus_df


calibrationtargets_bypurpose_oncampus_df <- modesplit_bypurpose_oncampus_df %>%
  left_join(modesplit_byrecodedpurpose_oncampus_df, by="TripPurpose_recode") %>%
  select(Trip_Purpose, 
         Pct_Bicycle, 
         Pct_Walk, 
         Pct_Car, 
         Pct_Bus, 
         Pct_AllModes)

calibrationtargets_bypurpose_oncampus_df


## Mode Split off-campus students -----------------------------------------------
### unweighted -----------------------------------------------------------------
unweighted_modesplit_bypurpose_offcampus_df<-trip_subset_df %>%
  filter(Trip_Purpose !="99") %>%
  filter(Trip_Purpose != "UOO") %>%
  filter(On_campus == 0) %>%
  filter(!is.na(Walk)) %>%
  group_by(Trip_Purpose)%>%
  summarize(Temp_Total = n(),
            TotalBicycle = sum(Bicycle),
            TotalWalk = sum(Walk),
            TotalCar = sum(Car),
            TotalCarpool = sum(Carpool),
            TotalBus = sum(Bus),
            TotalOther = sum(Other),
            Temp_Pct_Bicycle = TotalBicycle/Temp_Total * 100,
            Temp_Pct_Walk = TotalWalk/Temp_Total * 100,
            Temp_Pct_Car = TotalCar/Temp_Total * 100,
            Temp_Pct_Carpool = TotalCarpool/Temp_Total * 100,
            Temp_Pct_Bus = TotalBus/Temp_Total * 100,
            Temp_Pct_Other = TotalOther/Temp_Total * 100) 
  unweighted_modesplit_bypurpose_offcampus_df



### weighted -----------------------------------------------------------------
modesplit_bypurpose_offcampus_df<-trip_subset_df %>%
  filter(Trip_Purpose !="99") %>%
  filter(Trip_Purpose != "UOO") %>%
  filter(On_campus == 0) %>%
  filter(!is.na(Walk_W)) %>%
  group_by(Trip_Purpose)%>%
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
select(Trip_Purpose,
       Pct_Bicycle = Temp_Pct_Bicycle,
       Pct_Walk = Temp_Pct_Walk,
       Pct_Car = Temp_Pct_Car,
       Pct_Carpool = Temp_Pct_Carpool,
       Pct_Bus = Temp_Pct_Bus,
       Pct_Other = Temp_Pct_Other)



calibrationtargets_bypurpose_offcampus_df <- modesplit_bypurpose_offcampus_df %>%
  group_by(Trip_Purpose) %>%
  summarize(Total = Temp_Total - TotalOther,
            Pct_Bicycle = TotalBicycle/Total * 100,
            Pct_Walk = TotalWalk/Total * 100,
            Pct_Car = (TotalCar + TotalCarpool)/Total * 100,
            Pct_Bus = 100.00 - (Pct_Bicycle + Pct_Walk + Pct_Car),
            Pct_AllModes = Pct_Bicycle + Pct_Walk + Pct_Car + Pct_Bus) %>%
  select(Trip_Purpose,
         Pct_Bicycle, 
         Pct_Walk, 
         Pct_Car, 
         Pct_Bus,
         Pct_AllModes) 
calibrationtargets_bypurpose_offcampus_df

# plots mode split - all purposes except UC1-----------------------------------------------------------


trips_bypurpose_oncampus_plot <-trip_subset_df %>%
  filter(Trip_Purpose != "99")%>%
  filter(Primary_Mode != "NA")%>%
  filter(On_campus == 1) %>%
  filter(Trip_Purpose != "UC1") %>%
  ggplot(aes(Trip_Purpose, fill=Primary_Mode)) + geom_bar(position="dodge") + 
  geom_hline(yintercept = 20)

trips_bypurpose_oncampus_plot + labs(title = "Mode Split by Purpose (except UC1)", 
                                     subtitle="On-campus students", 
                                     caption = ("Source: NCSU survey (unweighted)"))

trips_bypurpose_offcampus_plot <-trip_subset_df %>%
  filter(Trip_Purpose != "99")%>%
  filter(Primary_Mode != "NA")%>%
  filter(Trip_Purpose != "UC1") %>%
  filter(On_campus == 0) %>%
  ggplot(aes(Trip_Purpose, fill=Primary_Mode)) + geom_bar(position="dodge") + 
  geom_hline(yintercept = 20)

trips_bypurpose_offcampus_plot + labs(title = "Mode Split by Purpose (except UC1)", 
                                     subtitle="Off-campus students", 
                                     caption = ("Source: NCSU survey (unweighted)"))


# plots mode split - only UC1-----------------------------------------------------------

trips_bypurpose_oncampusUC1_plot <-trip_subset_df %>%
  filter(Trip_Purpose != "99")%>%
  filter(Primary_Mode != "NA")%>%
  filter(On_campus == 1) %>%
  filter(Trip_Purpose == "UC1") %>%
  ggplot(aes(Trip_Purpose, fill=Primary_Mode)) + geom_bar(position="dodge") + 
  geom_hline(yintercept = 20)

trips_bypurpose_oncampusUC1_plot + labs(title = "Mode Split for UC1 trips", 
                                        subtitle="On-campus students", 
                                        caption = ("Source: NCSU survey (unweighted)"))

trips_bypurpose_offcampusUC1_plot <-trip_subset_df %>%
  filter(Trip_Purpose != "99")%>%
  filter(Primary_Mode != "NA")%>%
  filter(Trip_Purpose == "UC1") %>%
  filter(On_campus == 0) %>%
  ggplot(aes(Trip_Purpose, fill=Primary_Mode)) + geom_bar(position="dodge") + 
  geom_hline(yintercept = 20)

trips_bypurpose_offcampusUC1_plot + labs(title = "Mode Split for UC1 trips", 
                                         subtitle="Off-campus students", 
                                         caption = ("Source: NCSU survey (unweighted)"))

  
# write results ------------------------------------------------------
calibrationtargets_bypurpose_oncampus<-write_csv(calibrationtargets_bypurpose_oncampus_df,paste0(univ_dir,"calibrationtargets_bypurpose_oncampus.CSV"))
calibrationtargets_bypurpose_offcampus<-write_csv(calibrationtargets_bypurpose_offcampus_df, paste0(univ_dir,"calibrationtargets_bypurpose_offcampus.CSV"))

