# Packages ---------------------------------------------------------------------
packages_vector <- c("tidyverse",
                     "readxl",
                     "sf",
                     "foreign")
need_to_install <- packages_vector[!(packages_vector %in% installed.packages()[,"Package"])]
if (length(need_to_install)) install.packages(need_to_install)
for (package in packages_vector){
  library(package, character.only = TRUE)
}
knitr::opts_chunk$set(echo = TRUE)
options(dplyr.summarise.inform = FALSE)
options(scipen = 999)


# Remote I/O -------------------------------------------------------------------
private_dir <- "../data/input/_PRIVATE/"
data_dir<-"../data/input/"
prepared_data_dir<-"../data/input/university/"

# Parameters -------------------------------------------------------------------
PLANAR_EPSG <- 3857
LATLON_EPSG <- 4326

# Data Reads -------------------------------------------------------------------
#surveys
NCSUsurvey_name<-paste0(private_dir,"2013_NCSU_Data_Raw_All_2020-05-14_ITRE.xls")
ODU_name<-paste0(private_dir,"ODU1_adjustedNtrips.sav") 
UVA_name<-paste0(private_dir,"UVA1_adjustedNtrips.sav")
VCU_name<-paste0(private_dir,"VCU1_adjustedNtrips.sav")
VT_name<-paste0(private_dir,"VT1_adjustedNtrips.sav")
ODUw_name<-paste0(private_dir,"snVDOTCORRADINO_ODU_2010_with weight.sav") 
VTw_name<-paste0(private_dir,"snVDOTCORRADINO_VT_2010_with weight.sav")
dictUVA_name<-paste0(private_dir,"datadictionary.xlsx")

#zonal
taz_shape_file_name<-paste0(data_dir,"tazs/master_tazs.shp")
#adjacency_filename <-"Adjacent.csv"

#socioeconomics
se_filename<-paste0(data_dir,"se_data/se_2016.csv") # replace with master_tazs.bin converted to csv

# Data Reads -------------------------------------------------------------------
#NCSU surveys
NCSU_Person_df<-read_excel(NCSUsurvey_name,"Person")
NCSU_Trip_df<-read_excel(NCSUsurvey_name,"Trip")
NCSU_Place_df<-read_excel(NCSUsurvey_name,"Place")
NCSU_DDtemp_df<-read_excel(NCSUsurvey_name,"Dictionary")
NCSU_DataDictionary_df<-NCSU_DDtemp_df[-c(2:3),]

# join person and trip data (place data already included in trip data)
NCSU_All_df<- NCSU_Person_df %>% 
  full_join(NCSU_Trip_df, by="Person_ID")

#Virginia surveys
ODU_df<-ODUw_name %>% 
  read.spss(to.data.frame = TRUE)
VT_df<-VTw_name %>% 
  read.spss(to.data.frame = TRUE)
ODU_0_df<-ODU_name %>%  
  read.spss(to.data.frame = TRUE)
VCU_0_df<-VCU_name %>%  
  read.spss(to.data.frame = TRUE)
UVA_0_df<-UVA_name %>%  
  read.spss(to.data.frame = TRUE)
VT_0_df<-VT_name %>%  
  read.spss(to.data.frame = TRUE)
UVA_dd_df<-read_excel(dictUVA_name,"UVA1")

#Zonal
taz_sf <- st_read(taz_shape_file_name, stringsAsFactors = FALSE)
socioecon <-read_csv(se_filename)   
#adjacency<-read_csv(adjacency_filename)
#adjacency$TAZ<-as.character(adjacency$TAZ)

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

# New/Recoded variables survey data---------------------------------------------
NCSUtemp_df<- NCSU_All_df %>% 
  left_join(orig_tazs_df, by="Start_PlaceID")%>% 
  left_join(dest_tazs_df,by="End_PlaceID")%>%
  mutate(
    #ID_o=as.character(ID.x),
    #ID_d=as.character(ID.y),
    Trip_Purpose=case_when(
      Start_PlaceType=="Home" & End_PlaceType=="Home" ~ "99",
      Start_PlaceType=="Home" & End_PlaceType=="North Carolina State University" ~ "UHC", 
      End_PlaceType=="Home" & Start_PlaceType=="North Carolina State University" ~ "UHC",
      Start_PlaceType=="Home" & End_PlaceType!="North Carolina State University" ~ "UHO",
      End_PlaceType=="Home" & Start_PlaceType!="North Carolina State University" ~ "UHO",
      Start_PlaceType!="Home" & Start_PlaceType != "North Carolina State University"  & End_PlaceType=="North Carolina State University" ~ "UCO",
      End_PlaceType!="Home" & End_PlaceType != "North Carolina State University" & Start_PlaceType=="North Carolina State University" ~ "UCO",
      Start_PlaceType=="North Carolina State University" & End_PlaceType=="North Carolina State University" ~ "UC1",
      Start_PlaceType=="Other" & End_PlaceType=="Other" ~ "UOO",
      Start_PlaceType=="Off-campus Workplace" & End_PlaceType=="Off-campus Workplace" ~ "UOO",
      Start_PlaceType=="Other" & End_PlaceType=="Off-campus Workplace" ~ "UOO",
      End_PlaceType=="Other" & Start_PlaceType=="Off-campus Workplace" ~ "UOO"),
    UHC=if_else(Trip_Purpose=="UHC", 1,0),
    UHO=if_else(Trip_Purpose=="UHO", 1,0),
    UCO=if_else(Trip_Purpose=="UCO", 1,0),
    UC1=if_else(Trip_Purpose=="UC1", 1,0),
    UOO=if_else(Trip_Purpose=="UOO", 1,0),
    Origin_PA = case_when(
      Start_PlaceType=="Home" ~ "P",
      End_PlaceType!="Home" & Start_PlaceType=="North Carolina State University"~ "P",
      End_PlaceType!="Home" & End_PlaceType!="North Carolina State University"~ "P",
      TRUE ~ "A"),
    Destination_PA = case_when(
      End_PlaceType=="Home" ~ "P",
      Start_PlaceType!="Home"& Start_PlaceType!="North Carolina State University" & End_PlaceType=="North Carolina State University"~ "P",
      TRUE ~ "A"),
    TAZ_P = case_when(
      Origin_PA=="P" ~ ID.x,TRUE ~ ID.y),
    TAZ_A = case_when(
      Origin_PA=="A" ~ ID.x,TRUE ~ ID.y),
    Primary_Mode = as.factor(Mode_1),
    Primary_Mode = case_when(Primary_Mode == "Bicycle" ~ "Bicycle",
                             Primary_Mode == "Public Bus / Private Shuttle" | Primary_Mode == "Other, wolfline" ~ "Bus",
                             Primary_Mode == "Driver - Auto / Van / Truck" |  Primary_Mode == "Driver - Auto / Van / Truck, Other" | Primary_Mode == "Passenger - Auto / Van / Truck" ~ "Car",
                             Primary_Mode == "Walk" ~ "Walk",
                             Primary_Mode == "Other" | Primary_Mode == "Other, Longboard" | Primary_Mode == "Motorcycle / Motorized Moped or Scooter" ~ "Other"),
      
    Bicycle = if_else(Primary_Mode == "Bicycle",1,0),
    Bus = if_else(Primary_Mode == "Bus",1,0),
    Car = if_else(Primary_Mode == "Car",1,0),
    Walk = if_else(Primary_Mode == "Walk", 1,0),
    Other = if_else(Primary_Mode == "Other",1,0),
    rename(On_campus=On_campus.x))

Person_subset_df<-NCSU_Person_df %>%
  filter(Finished==1,
         Derived_minus_stated>=-1)%>%
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
         Weight) %>%
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

# New/Recoded variables socioeconomic data--------------------------------------
# Total BuildingS per university
TotalBuildingS_NCSU <-socioecon %>% 
  filter(!is.na(BuildingS_NCSU)) %>% 
  summarize(sum=sum(BuildingS_NCSU))%>%
  pull(sum)

TotalBuildingS_UNC <-socioecon %>% 
  filter(!is.na(BuildingS_UNC)) %>% 
  summarize(sum=sum(BuildingS_UNC))%>%
  pull(sum)

TotalBuildingS_DUKE <-socioecon %>% 
  filter(!is.na(BuildingS_DUKE)) %>% 
  summarize(sum=sum(BuildingS_DUKE))%>%
  pull(sum)

TotalBuildingS_NCCU <-socioecon %>% 
  filter(!is.na(BuildingS_NCCU)) %>% 
  summarize(sum=sum(BuildingS_NCCU))%>%
  pull(sum)

TotalBuildingS_NCSU
TotalBuildingS_UNC
TotalBuildingS_DUKE
TotalBuildingS_NCCU

# Distribution of BuildingS by TAZ
socioecon2_df <- socioecon %>%
  mutate(Share_Bldg_NCSU=BuildingS_NCSU/TotalBuildingS_NCSU, 
         Share_Bldg_UNC=BuildingS_UNC/TotalBuildingS_UNC,
         Share_Bldg_DUKE=BuildingS_DUKE/TotalBuildingS_DUKE,
         Share_Bldg_NCCU=BuildingS_NCCU/TotalBuildingS_NCCU)


# Datasets for analysis --------------------------------------------------------
Trip_subset_df<-NCSUtemp_df  %>% 
  filter(Finished==1 & Derived_minus_stated>=-1) %>%
  select(Person_ID,
         On_campus,
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
         Purpose,
         Primary_Mode,
         Bicycle,
         Bus,
         Car,
         Walk,
         Other,
         #Distance,
         Weight)

Productions_df<-Trip_subset_df %>%   
  filter(Trip_Purpose!="99" & 
           !is.na(Trip_Purpose))%>% 
  group_by(Person_ID, 
           On_campus,
           #Distance,
           Trip_Purpose, 
           Primary_Mode) %>%
  summarize(Trips=n()) %>%
  left_join(Person_subset_df, by="Person_ID")%>% 
  mutate(Trips_Weighted= Trips * Weight)%>%
  select(Person_ID,
         On_campus,
         #Distance,
         Trip_Purpose,
         UHC,
         UHO,
         UCO,
         UC1,
         UOO,
         Trips,
         Trips_Weighted,
         Primary_Mode,
         Graduate, 
         Full_time,
         Job_on,
         Job_off,
         Permit,
         Weight)

Productions_forregression_df<-Productions_df%>%
  group_by(Person_ID,
           On_campus, 
           #Distance,
           Graduate, 
           Full_time,
           Job_on,
           Job_off,
           Permit,
           UHC,
           UHO,
           UCO,
           UC1,
           UOO,
           Weight, 
           Trips)%>%
  summarize(Total_Trips=sum(Trips)) 

Attractions_df<-Trip_subset_df %>% 
  filter(Trip_Purpose!="99" &
           !is.na(Trip_Purpose))%>% 
  group_by(Person_ID, 
           Trip_Purpose, 
           On_campus, 
           TAZ_A, 
           Primary_Mode) %>%
  summarize(Trips=n()) %>%
  left_join(Person_subset_df, by="Person_ID")%>%
  # left_join(socioecon2,by=c("TAZ_A" ="TAZ_NG"))%>%
  mutate(Trips_Weighted= Trips * Weight,
         UHC=if_else(Trip_Purpose=="UHC", 1,0),
         UHO=if_else(Trip_Purpose=="UHO", 1,0),
         UCO=if_else(Trip_Purpose=="UCO", 1,0),
         UC1=if_else(Trip_Purpose=="UC1", 1,0),
         UOO=if_else(Trip_Purpose=="UOO", 1,0))%>%
  rename(On_campus=On_campus.x)

Attractions_byTAZbySegment_df<-Attractions_df %>% 
  ungroup()%>%
  select(TAZ_A,On_campus,Trip_Purpose,Trips,Trips_Weighted)%>%
  filter(Trip_Purpose=="UHO"| Trip_Purpose=="UCO"|Trip_Purpose=="UOO")%>%
  group_by(TAZ_A,
           On_campus,
           Trip_Purpose)%>%
  right_join(.,socioecon2,by=c("TAZ_A" ="TAZ_NG"))%>%
  mutate(Total_W_Trips=sum(Trips_Weighted),
         On_UHOTrips=if_else(Trip_Purpose=="UHO" & On_campus==1,Trips,as.integer(0)),
         On_UCOTrips=if_else(Trip_Purpose=="UCO"& On_campus==1 ,Trips,as.integer(0)),
         On_UOOTrips=if_else(Trip_Purpose=="UOO" & On_campus==1,Trips,as.integer(0)),
         W_On_UHOTrips=if_else(Trip_Purpose=="UHO"& On_campus==1,Trips_Weighted,0),
         W_On_UCOTrips=if_else(Trip_Purpose=="UCO" & On_campus==1,Trips_Weighted,0),
         W_On_UOOTrips=if_else(Trip_Purpose=="UOO" & On_campus==1,Trips_Weighted,0),
         Off_UHOTrips=if_else(Trip_Purpose=="UHO" & On_campus==0,Trips,as.integer(0)),
         Off_UCOTrips=if_else(Trip_Purpose=="UCO"& On_campus==0,Trips,as.integer(0)),
         Off_UOOTrips=if_else(Trip_Purpose=="UOO" & On_campus==0,Trips,as.integer(0)),
         W_Off_UHOTrips=if_else(Trip_Purpose=="UHO"& On_campus==0,Trips_Weighted,0),
         W_Off_UCOTrips=if_else(Trip_Purpose=="UCO" & On_campus==0,Trips_Weighted,0),
         W_Off_UOOTrips=if_else(Trip_Purpose=="UOO" & On_campus==0,Trips_Weighted,0)) 

Attractions_byTAZfinal_df<-Attractions_byTAZbySegment_df%>%
  ungroup()%>%
  select(TAZ_A,
         On_UHOTrips,
         On_UCOTrips,
         On_UOOTrips,
         W_On_UHOTrips,
         W_On_UCOTrips,
         W_On_UOOTrips,
         Off_UHOTrips,
         Off_UCOTrips,
         Off_UOOTrips,
         W_Off_UHOTrips,
         W_Off_UCOTrips,
         W_Off_UOOTrips)%>%
  group_by(TAZ_A)%>%
  summarize_all(sum)%>%
  right_join(.,socioecon2_df,by=c("TAZ_A" ="TAZ_NG"))


# Output -----------------------------------------------------------------------
write_rds(Productions_df,paste0(private_dir, "Productions_df.RDS"))
write_rds(Attractions_df,paste0(private_dir,"Attractions_df.RDS"))
write_rds(Productions_forregression_df,paste0(private_dir,"Productions_forregression_df.RDS"))
write_rds(Attractions_byTAZ_df,paste0(private_dir,"Attractions_byTAZ_df.RDS"))
write_rds(Attractions_byTAZbySegment_df,paste0(private_dir,"Attractions_byTAZbySegment_df.RDS"))
write_rds(Attractions_byTAZfinal_df,paste0(private_dir,"Attractions_byTAZfinal_df.RDS"))
write_rds(Trip_subset_df, paste0(private_dir,"Trip_subset_df.RDS"))
write_rds(Person_subset_df,paste0(private_dir,"Person_subset_df.RDS"))
write_rds(socioecon2_df,paste0(prepared_data_dir,"socioecon2_df.RDS"))
