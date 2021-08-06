# Packages ---------------------------------------------------------------------
packages_vector <- c("tidyverse",
                     "readxl",
                     "sf",
                     "geosphere",
                     "measurements",
                     "foreign",
                     "knitr")
need_to_install <- packages_vector[!(packages_vector %in% installed.packages()[,"Package"])]
if (length(need_to_install)) install.packages(need_to_install)
for (package in packages_vector){
  library(package, character.only = TRUE)
}
knitr::opts_chunk$set(echo = TRUE)
options(dplyr.summarise.inform = FALSE)
options(scipen = 999)

# Remote I/O -------------------------------------------------------------------

private_dir <- "data/input/_PRIVATE/"
data_dir<-"data/input/"
prepared_data_dir<-"data/input/university/"

NCSUsurvey_name<-paste0(private_dir,"2013_NCSU_Data_Raw_All_2020-05-14_ITRE.xls")
taz_shape_file_name<-paste0(data_dir,"tazs/master_tazs.shp")
distance_skim_name<-paste0(data_dir,"AMSOVDistanceSkim.csv")
se_filename<-paste0(data_dir,"se_data/se_2016.csv")

# Parameters -------------------------------------------------------------------
PLANAR_EPSG <- 3857
LATLON_EPSG <- 4326

# Data Reads -------------------------------------------------------------------
NCSU_Person_df<-read_excel(NCSUsurvey_name,"Person")
NCSU_Trip_df<-read_excel(NCSUsurvey_name,"Trip")
NCSU_Place_df<-read_excel(NCSUsurvey_name,"Place")
NCSU_DDtemp_df<-read_excel(NCSUsurvey_name,"Dictionary") [-c(1:3),]
NCSU_DataDictionary_df<-NCSU_DDtemp_df    #need to turn first row into header
NCSU_All_df<- NCSU_Person_df %>% 
  full_join(NCSU_Trip_df, by="Person_ID") %>%
  mutate(Trip_ID=seq(1:2824))

taz_sf <- st_read(taz_shape_file_name, stringsAsFactors = FALSE)
socioecon_df <-read_csv(se_filename) 
distance_skim_df <- read_csv(distance_skim_name, col_names = c("originTAZ","destinationTAZ","distance_zonetozone"))

# Assign survey responses to TAZ------------------------------------------------
taz_join_sf <- st_transform(taz_sf, PLANAR_EPSG)

orig_tazs_df <- NCSU_All_df %>% 
  filter(Finished==1) %>% 
  select(Start_PlaceID,Start_Lat,Start_Long) %>%
  filter(!is.na(Start_Lat)) %>% 
  st_as_sf(., coords = c("Start_Long", "Start_Lat"),crs=LATLON_EPSG) %>%
  st_transform(., PLANAR_EPSG) %>%
  st_join(., taz_join_sf, join = st_intersects)

dest_tazs_df <- NCSU_All_df %>% 
  filter(Finished==1) %>% 
  select(End_PlaceID,End_Lat,End_Long)%>% 
  filter(!is.na(End_Lat))%>% 
  st_as_sf(., coords = c("End_Long", "End_Lat"),crs=LATLON_EPSG) %>%
  st_transform(., PLANAR_EPSG) %>%
  st_join(., taz_join_sf, join = st_intersects)

# Add Crow Flies Distance to trips in survey  ----------------------------------
CrowFliesdistance_df<- NCSU_All_df %>%
  select(Person_ID, Trip_ID, Start_Lat, Start_Long, End_Lat, End_Long)%>%
  rowwise()%>%
  mutate(distance_meters = geosphere::distm(c(Start_Lat,Start_Long), c(End_Lat, End_Long), fun = distHaversine),
         distance_miles = conv_unit(distance_meters, from = "m", to = "mi"))

# Add/Recode variables socioeconomic data---------------------------------------
# Total BuildingS per university
TotalBuildingS_NCSU_df <-socioecon_df %>% 
  filter(!is.na(BuildingS_NCSU)) %>% 
  summarize(sum=sum(BuildingS_NCSU))%>%
  pull(sum)

TotalBuildingS_UNC_df <-socioecon_df %>% 
  filter(!is.na(BuildingS_UNC)) %>% 
  summarize(sum=sum(BuildingS_UNC))%>%
  pull(sum)

TotalBuildingS_DUKE_df <-socioecon_df %>% 
  filter(!is.na(BuildingS_DUKE)) %>% 
  summarize(sum=sum(BuildingS_DUKE))%>%
  pull(sum)

TotalBuildingS_NCCU_df <-socioecon_df %>% 
  filter(!is.na(BuildingS_NCCU)) %>% 
  summarize(sum=sum(BuildingS_NCCU))%>%
  pull(sum)


# Additional variables - Distribution of BuildingS by TAZ, employment, campus TAZa 
socioecon2_df <- socioecon_df %>%
  mutate(Share_Bldg_NCSU  = BuildingS_NCSU/TotalBuildingS_NCSU_df, 
         Share_Bldg_UNC = BuildingS_UNC/TotalBuildingS_UNC_df,
         Share_Bldg_DUKE = BuildingS_DUKE/TotalBuildingS_DUKE_df,
         Share_Bldg_NCCU = BuildingS_NCCU/TotalBuildingS_NCCU_df,
         employment = Industry + Office + Service_RateLow + Service_RateHigh + Retail,
         Campus_NCSU_Main = if_else(TAZ %in% c(1486,	1487,1489,	1503, 1504,	1652,	1653,3052,3054,3055,3056,3057,3058,3059,3060), 1,0),
         Campus_NCSU_Centennial = if_else(TAZ %in% c(1597,3031,3032,3036,3038,3039,3040,3041), 1,0),
         Campus_NCSU_Biomedical = if_else(TAZ == 1624,1,0),
         Campus_UNC = if_else(TAZ %in% c(1290,1291,	1292,	1293,	1294,	1295,	1296,	1297,	1298,	1299,	1301, 3012,3013,3014), 1,0),
         Campus_DUKE = if_else(TAZ %in% c(3017,3018,3020,3023,3024,3025,3026,3029,3030),1,0),
         Campus_NCCU = if_else(TAZ == 301,1,0))

campusTAZs_df<-socioecon2_df %>%
  select(TAZ,
         Campus_NCSU_Main,
         Campus_NCSU_Centennial,
         Campus_NCSU_Biomedical,
         Campus_UNC,
         Campus_DUKE,
         Campus_NCCU)%>%
  mutate(campus =  case_when(Campus_NCSU_Main == 1 ~ "NCSU_Main",
                             Campus_NCSU_Centennial == 1 ~ "NCSU_Centennial",
                             Campus_NCSU_Biomedical == 1 ~ "NCSU_Biomedical",
                             Campus_UNC == 1 ~ "UNC",
                             Campus_DUKE == 1 ~"Duke",
                             Campus_NCCU == 1 ~ "NCCU"),
         aggcampus = case_when(campus == "NCSU_Main" ~ "NCSU",
                               campus == "NCSU_Centennial" ~ "NCSU",
                               campus == "NCSU_Biomedical" ~ "NCSU",
                               campus == "UNC" ~ "UNC",
                               campus == "Duke" ~ "Duke",
                               campus == "NCCU" ~ "NCCU")) %>%
  select(TAZ,campus,aggcampus)%>%
  filter(!is.na(aggcampus))

# distance to campus ----------------------------------------------------------
distance_tocampus_df<- distance_skim_df %>%
  right_join(campusTAZs_df, by = c("originTAZ" = "TAZ")) %>%
  group_by(destinationTAZ,aggcampus) %>%
  summarize(avg_distance=mean(distance_zonetozone),min_distance=min(distance_zonetozone))%>%
  pivot_wider(names_from = aggcampus, values_from =c(avg_distance, min_distance))
             
# New/Recoded variables survey data---------------------------------------------
NCSUtemp_df<- NCSU_All_df %>% 
  full_join(CrowFliesdistance_df) %>% 
  left_join(orig_tazs_df, by="Start_PlaceID")%>% 
  left_join(dest_tazs_df,by="End_PlaceID")%>%
  mutate(Origin_PA = case_when(Start_PlaceType=="Home" ~ "P",
                               End_PlaceType!="Home" & Start_PlaceType=="North Carolina State University"~ "P",
                               End_PlaceType!="Home" & End_PlaceType!="North Carolina State University"~ "P",
                               TRUE ~ "A"),
         Destination_PA = case_when(End_PlaceType=="Home" ~ "P",
                                    Start_PlaceType!="Home"& Start_PlaceType!="North Carolina State University" & End_PlaceType=="North Carolina State University"~ "P",
                                    TRUE ~ "A"),
         TAZ_P = case_when(Origin_PA=="P" ~ ID.x,TRUE ~ ID.y),
         TAZ_A = case_when(Origin_PA=="A" ~ ID.x,TRUE ~ ID.y))%>%
  left_join(campusTAZs_df, by=c("TAZ_P"="TAZ")) %>%
  rename(Campus_TAZ_P = campus)%>%
  left_join(campusTAZs_df, by=c("TAZ_A"="TAZ")) %>%
  rename(Campus_TAZ_A = campus)%>%
  mutate(Trip_Purpose=case_when(
    Start_PlaceType=="Home" & End_PlaceType=="Home" ~ "99",
    Start_PlaceType=="Home" & End_PlaceType=="North Carolina State University" ~ "UHC", 
    End_PlaceType=="Home" & Start_PlaceType=="North Carolina State University" ~ "UHC",
    Start_PlaceType=="Home" & End_PlaceType!="North Carolina State University" ~ "UHO",
    End_PlaceType=="Home" & Start_PlaceType!="North Carolina State University" ~ "UHO",
    Start_PlaceType!="Home" & Start_PlaceType != "North Carolina State University"  & End_PlaceType=="North Carolina State University" ~ "UCO",
    End_PlaceType!="Home" & End_PlaceType != "North Carolina State University" & Start_PlaceType=="North Carolina State University" ~ "UCO",
    Start_PlaceType=="Other" & End_PlaceType=="Other" ~ "UOO",
    Start_PlaceType=="Off-campus Workplace" & End_PlaceType=="Off-campus Workplace" ~ "UOO",
    Start_PlaceType=="Other" & End_PlaceType=="Off-campus Workplace" ~ "UOO",
    End_PlaceType=="Other" & Start_PlaceType=="Off-campus Workplace" ~ "UOO",
    (Campus_TAZ_P == "NCSU_Main" | Campus_TAZ_P == "NSCU_Centennial") & (Campus_TAZ_A == "NCSU_Biomedical") ~ "UCC",
    (Campus_TAZ_P == "NCSU_Main") & (Campus_TAZ_A == "NSCU_Centennial" | Campus_TAZ_A == "NCSU_Biomedical") ~ "UCC",
    (Campus_TAZ_P == "NCSU_Main" | Campus_TAZ_P == "NSCU_Biomedical") & (Campus_TAZ_A == "NCSU_Centennial") ~ "UCC",
    (Campus_TAZ_A == "NCSU_Main" | Campus_TAZ_A == "NSCU_Centennial") & (Campus_TAZ_P == "NCSU_Biomedical") ~ "UCC",
    (Campus_TAZ_A == "NCSU_Main") & (Campus_TAZ_P == "NSCU_Centennial" | Campus_TAZ_P == "NCSU_Biomedical") ~ "UCC",
    (Campus_TAZ_A == "NCSU_Main" | Campus_TAZ_A == "NSCU_Biomedical") & (Campus_TAZ_P == "NCSU_Centennial") ~ "UCC",
    TRUE ~ "UC1"),
    UHC=if_else(Trip_Purpose=="UHC", 1,0),
    UHO=if_else(Trip_Purpose=="UHO", 1,0),
    UCO=if_else(Trip_Purpose=="UCO", 1,0),
    UC1=if_else(Trip_Purpose=="UC1", 1,0),
    UOO=if_else(Trip_Purpose=="UOO", 1,0),
    UCC=if_else(Trip_Purpose=="UCC", 1,0),
    Primary_Mode = as.factor(Mode_1),
    Primary_Mode = case_when(Primary_Mode == "Bicycle" ~ "Bicycle",
                             Primary_Mode == "Public Bus / Private Shuttle" | Primary_Mode == "Other, wolfline" ~ "Bus",
                             Primary_Mode == "Driver - Auto / Van / Truck" |  Primary_Mode == "Driver - Auto / Van / Truck, Other" ~ "Car",
                             Primary_Mode == "Passenger - Auto / Van / Truck" ~ "Carpool",
                             Primary_Mode == "Walk" ~ "Walk",
                             Primary_Mode == "Other" | Primary_Mode == "Other, Longboard" | Primary_Mode == "Motorcycle / Motorized Moped or Scooter" ~ "Other"),
    
    Bicycle = if_else(Primary_Mode == "Bicycle",1,0),
    Bus = if_else(Primary_Mode == "Bus",1,0),
    Car = if_else(Primary_Mode == "Car",1,0),
    Carpool = if_else(Primary_Mode == "Carpool",1,0),
    Walk = if_else(Primary_Mode == "Walk", 1,0),
    Other = if_else(Primary_Mode == "Other",1,0))%>%
  left_join(distance_skim_df,by=c("ID.x" = "originTAZ", "ID.y" = "destinationTAZ"))



HometoCampus_distance_df <- NCSUtemp_df %>% 
  filter(Trip_Purpose == "UHC") %>%
  select(Person_ID,distance_miles, distance_zonetozone)%>%
  group_by(Person_ID)%>%
  summarize(distanceHC=mean(distance_miles),distanceHC_zonetozone=mean(distance_zonetozone))

Person_subset_df<-NCSU_Person_df %>%
  filter(Finished==1 &
         Derived_minus_stated>=-1)%>%
  left_join(.,HometoCampus_distance_df,by="Person_ID")%>%  
              select(Person_ID,
                     On_campus,
                     Class_status,
                     Employed,
                     Have_children,
                     Have_car, 
                     Have_parking_permit, 
                     Not_to_campus_weekdays,
                     Stated_trip_rate,
                     Derived_trip_rate,
                     Derived_minus_stated,
                     Graduate,
                     Full_time, 
                     Weight,
                     distanceHC,# distance between campus and home
                     distanceHC_zonetozone) %>%  # distance between campus and home
              mutate(Job = case_when(Employed=="No" ~ "0",
                                     Employed=="Yes, both on and off campus" ~ "3",
                                     Employed=="Yes, off campus" ~ "2",
                                     Employed=="Yes, on campus" ~ "1"),
                     Job_on = case_when(Employed== "Yes, on campus" ~ 1,
                                        Employed== "Yes, both on and off campus" ~ 1,
                                        TRUE ~ 0),
                     Job_off = case_when(Employed== "Yes, off campus" ~ 1,
                                         Employed== "Yes, both on and off campus" ~ 1,
                                         TRUE ~ 0),
                     Permit = case_when(Have_parking_permit=="Yes" ~ 1,
                                        TRUE ~ 0))


# Datasets for analysis --------------------------------------------------------
Trip_subset_df<-NCSUtemp_df  %>% 
  filter(Finished==1 & Derived_minus_stated>=-1) %>%
  select(Person_ID,
         On_campus,
         Graduate,
         Have_car,
         Have_parking_permit,
         Start_PlaceID,
         Start_PlaceType,
         End_PlaceID,
         End_PlaceType, 
         TAZ_o=ID.x,
         TAZ_d=ID.y,
         Origin_PA,
         Destination_PA,
         TAZ_P,
         TAZ_A,
         Trip_Purpose,
         UHC,
         UHO,
         UCO,
         UC1,
         UOO,
         UCC,
         Campus_TAZ_A,
         Campus_TAZ_P,
         Purpose,
         Primary_Mode,
         Bicycle,
         Bus,
         Car,
         Carpool,
         Walk,
         Other,
         distance_miles, # trip distance
         distance_zonetozone, # trip distance
         Weight)%>%
  mutate(Bicycle_W = Bicycle * Weight,
         Bus_W = Bus * Weight,
         Car_W = Car * Weight,
         Carpool_W = Carpool * Weight,
         Walk_W  = Walk * Weight,
         Other_W = Other * Weight)


Productions_bymode_df<-Trip_subset_df %>%   
  filter(Trip_Purpose!="99" & 
           !is.na(Trip_Purpose))%>% 
  group_by(Person_ID, 
           Trip_Purpose, 
           UHC,
           UHO,
           UCO,
           UC1,
           UOO,
           UCC,
           Primary_Mode) %>%
  summarize(Trips=n()) %>%
  left_join(Person_subset_df, by = "Person_ID")%>% 
  mutate(Trips_Weighted = Trips * Weight)%>%
  select(Person_ID,
         On_campus,
         distanceHC, # distance home - campus
         Trip_Purpose,
         UHC,
         UHO,
         UCO,
         UC1,
         UOO,
         UCC,
         Trips,
         Trips_Weighted,
         Primary_Mode,
         Graduate, 
         Full_time,
         Job_on,
         Job_off,
         Permit,
         Weight)


Attractions_byTAZbySegment_df<-Trip_subset_df %>% 
  filter(Trip_Purpose!="99" & 
           !is.na(Trip_Purpose))%>% 
  group_by(Person_ID,
           Weight,
           On_campus,
           Trip_Purpose, 
           UHC,
           UHO,
           UCO,
           UC1,
           UOO,
           UCC,
           Primary_Mode,
           TAZ_A) %>%
  summarize(Trips=n()) %>%
  mutate(Trips_Weighted= Trips * Weight,
         OnCampusStudents_UHOTrips = if_else(Trip_Purpose == "UHO" & On_campus == 1,Trips_Weighted,0),
         OnCampusStudents_UCOTrips = if_else(Trip_Purpose == "UCO" & On_campus == 1,Trips_Weighted,0),
         OnCampusStudents_UOOTrips = if_else(Trip_Purpose == "UOO" & On_campus == 1,Trips_Weighted,0),
         OffCampusStudents_UHOTrips = if_else(Trip_Purpose == "UHO" & On_campus == 0,Trips_Weighted,0),
         OffCampusStudents_UCOTrips = if_else(Trip_Purpose == "UCO" & On_campus == 0,Trips_Weighted,0),
         OffCampusStudents_UOOTrips = if_else(Trip_Purpose == "UOO" & On_campus == 0,Trips_Weighted,0),
         OnCampusStudents_UHOUCOTrips = OnCampusStudents_UHOTrips + OnCampusStudents_UCOTrips,
         OffCampusStudents_UHOUCOTrips = OffCampusStudents_UHOTrips + OffCampusStudents_UCOTrips, 
         OnCampusStudents_Trips =   OnCampusStudents_UHOUCOTrips  + OnCampusStudents_UOOTrips,
         OffCampusStudents_Trips =  OffCampusStudents_UHOUCOTrips + OffCampusStudents_UOOTrips,
         AllStudents_Trips = OnCampusStudents_Trips + OffCampusStudents_Trips) 

Attractions_byTAZ_df<-Attractions_byTAZbySegment_df%>%  
  ungroup()%>%
  select(TAZ_A,
         OnCampusStudents_UHOTrips,
         OnCampusStudents_UCOTrips,
         OnCampusStudents_UOOTrips,
         OffCampusStudents_UHOTrips,
         OffCampusStudents_UCOTrips,
         OffCampusStudents_UOOTrips,
         OnCampusStudents_UHOUCOTrips,
         OffCampusStudents_UHOUCOTrips,
         OnCampusStudents_Trips,
         OffCampusStudents_Trips,
         AllStudents_Trips)%>%
  group_by(TAZ_A)%>%
  summarize_all(sum)%>%
  left_join(.,socioecon2_df,by = c("TAZ_A" ="TAZ")) %>%
  left_join(distance_tocampus_df, by = c("TAZ_A" = "destinationTAZ"))

# Output -----------------------------------------------------------------------
write_rds(Productions_bymode_df,paste0(private_dir,"Productions_bymode_df.RDS"))
write_rds(Attractions_byTAZbySegment_df,paste0(private_dir,"Attractions_byTAZbySegment_df.RDS"))
write_rds(Attractions_byTAZ_df,paste0(private_dir,"Attractions_byTAZ_df.RDS"))
write_rds(Trip_subset_df, paste0(private_dir,"Trip_subset_df.RDS"))
write_rds(Person_subset_df,paste0(private_dir,"Person_subset_df.RDS"))
write_rds(socioecon2_df,paste0(prepared_data_dir,"socioecon2_df.RDS"))
write_rds(distance_tocampus_df,paste0(prepared_data_dir,"distance_tocampus_df.RDS"))
write_csv(Trip_subset_df, paste0(private_dir,"Trip_subset_df.csv"))
