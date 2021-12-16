# Packages ---------------------------------------------------------------------
library(tidyverse)
#library(corrr)
#library(kableExtra)
library(broom)

# Remote I/O -------------------------------------------------------------------
private_dir <- "data/input/_PRIVATE/"
input_dir <- "data/input/university/"
univ_dir <- "data/output/university/"

# Data Reads -------------------------------------------------------------------
Productions_bymode_df<- readRDS(paste0(private_dir,"Productions_bymode_df.RDS"))
Trip_subset_df<-readRDS(paste0(private_dir,"Trip_subset_df.RDS"))
Person_subset_df<-readRDS(paste0(private_dir,"Person_subset_df.RDS"))
socioecon2_df<-readRDS(paste0(input_dir,"socioecon2_df.RDS")) 
 
# Enrollment by University -----------------------------------------------------
enrollment_NCSU<-socioecon2_df %>% 
  filter(!is.na(StudGQ_NCSU),!is.na(StudOff_NCSU))%>% 
  summarize(total=sum(StudGQ_NCSU,StudOff_NCSU), .groups = "drop")%>%
  pull(total)

enrollment_UNC<-socioecon2_df %>%
  filter(!is.na(StudGQ_UNC),!is.na(StudOff_UNC))%>% 
  summarize(total=sum(StudGQ_UNC,StudOff_UNC), .groups = "drop")%>%
  pull(total)

enrollment_Duke<-socioecon2_df %>% 
  filter(!is.na(StudGQ_DUKE),!is.na(StudOff_DUKE))%>% 
  summarize(total=sum(StudGQ_DUKE,StudOff_DUKE), .groups = "drop")%>%
  pull(total)

enrollment_NCCU<-socioecon2_df %>% 
  filter(!is.na(StudGQ_NCCU),!is.na(StudOff_NCCU))%>% 
  summarize(total=sum(StudGQ_NCCU,StudOff_NCCU), .groups = "drop")%>%
  pull(total)

enrollment_total<-enrollment_NCSU + enrollment_UNC + enrollment_Duke + enrollment_NCCU

# Note: 2016 enrollment from university websites doesn't exactly match enrollment calculated above
# 2016 enrollment NCSU -https://newstudents.dasa.ncsu.edu/wp-content/uploads/sites/26/2016/08/2016-First-Year-Facts.pdf - 34000+
# Fall 2016 enrollment UNC - https://oira.unc.edu/wp-content/uploads/sites/297/2017/07/Fall-2016-Headcount-Enrollment_20170202.pdf -  29,469
# 2016 enrollment Duke https://library.duke.edu/rubenstein/uarchives/history/articles/statistics - 15,032
# 2016 ENROLLMENT NCCU - https://newstudents.dasa.ncsu.edu/wp-content/uploads/sites/26/2016/08/2016-First-Year-Facts.pdf - 8,094

# NCSU Survey Overview ---------------------------------------------------------
surveyRespondents_ResidenceClass_df<-Person_subset_df%>%
  filter(!is.na(On_campus)) %>%
  count(On_campus,Graduate)

SurveyRespondent_Residence_Weighted_df<-Person_subset_df%>%
  filter(!is.na(Weight))%>% 
  group_by(On_campus) %>%
  summarize(count=n(), .groups = "drop")

# Trip Production Histograms --------------------------------------------------


purpose_map_df <- tibble(code = c("UHC", "UHO", "UCO", "UC1", "UCC", "UOO"),
                         name = c("Home-Campus",
                                  "Home-Other",
                                  "Campus-Other",
                                  "On-campus",
                                  "Campus-to-campus",
                                  "Other-to-other"))

Triprates_histogram1 <- Productions_bymode_df %>% 
  filter(Trip_Purpose =="UHC"| Trip_Purpose =="UHO")%>%
  left_join(., purpose_map_df, by = c("Trip_Purpose" = "code")) %>%
  mutate(On_campus = if_else(On_campus == 0, "Off-campus", "On-campus")) %>%
  group_by(Person_ID,
           name, 
           On_campus) %>%
  summarize(`Trips per Student` = sum(Trips), .groups = "drop") %>%
  rename(`Trip Purpose` = name) %>%
  group_by(On_campus) %>%
  ggplot(aes(`Trips per Student`, fill = `Trip Purpose`)) + 
  geom_histogram(bins=20) + 
  facet_grid(`Trip Purpose` ~ On_campus)

Triprates_histogram2 <- Productions_bymode_df %>% 
  filter(Trip_Purpose == "UC1"| Trip_Purpose == "UCO"| Trip_Purpose == "UCC")%>%
  left_join(., purpose_map_df, by = c("Trip_Purpose" = "code")) %>%
  mutate(On_campus = if_else(On_campus == 0, "Off-campus", "On-campus")) %>%
  group_by(Person_ID,
           name) %>%
  summarize(`Trips per Student` = sum(Trips), .groups = "drop") %>%
  rename(`Trip Purpose` = name) %>%
  ggplot(aes(`Trips per Student`, fill = `Trip Purpose`)) + 
  geom_histogram(bins=20) + 
  facet_grid(`Trip Purpose` ~ .)


# Trip Production Rates based on Cross-Classification --------------------------
# Raw data
avg_trips_df<-Person_subset_df%>%
  summarize(segment = "All",
            avg_trips=mean(Derived_trip_rate),
            variance=var(Derived_trip_rate),
            median=median(Derived_trip_rate),
            respondents=n(),
            .groups = "drop")

avg_trips_byresidence_df<-Person_subset_df%>%
  group_by(On_campus)%>%
  summarize(avg_trips=mean(Derived_trip_rate),
            variance=var(Derived_trip_rate),
            median=median(Derived_trip_rate),
            respondents=n(),
            .groups = "drop")

Respondents_Oncampus_students<-avg_trips_byresidence_df%>%
  filter(On_campus==1)%>%
  select(respondents)%>%
  pull()

Respondents_Offcampus_students<-avg_trips_byresidence_df%>%
  filter(On_campus==0)%>%
  select(respondents)%>%
  pull()

Respondents_All_students<-avg_trips_df%>%
  select(respondents)%>%
  pull()



#Weighted data
w_avg_trips_df<-Person_subset_df%>%
  filter(!is.na(Weight))%>%
  mutate(w_trips = Derived_trip_rate * Weight)%>%
  summarize(trips = sum(w_trips),
            students = sum(Weight),
            avg_trips = trips/students,
            respondents = n(),
            .groups = "drop")

w_avg_trips_byresidence_df<-Person_subset_df%>%
  filter(!is.na(Weight))%>%
  mutate(w_trips=Derived_trip_rate * Weight)%>%
  group_by(On_campus)%>%
  summarize(trips = sum(w_trips),
            students = sum(Weight),
            avg_trips = trips/students,
            respondents = n(),
            .groups = "drop")

Oncampus_students<-w_avg_trips_byresidence_df%>%
  filter(On_campus==1)%>%
  select(students)%>%
  pull()

Offcampus_students<-w_avg_trips_byresidence_df%>%
  filter(On_campus==0)%>%
  select(students)%>%
  pull()

Total_students = Oncampus_students + Offcampus_students

# Trip Production Rates for UHC and UHO trip purposes (segmented by home location)
w_avg_trips_bypurpose_Oncampus_df<-Productions_bymode_df%>%
  filter(On_campus==1 & !is.na(Weight))%>%
  filter(Trip_Purpose %in% c("UHC","UHO")) %>%
  group_by(Trip_Purpose)%>%
  summarize(segment="On_campus Students",
            trips=sum(Trips_Weighted),
            students=Oncampus_students,
            avg_trips=trips/students,
            respondents=Respondents_Oncampus_students,
            .groups = "drop")

w_avg_trips_bypurpose_Offcampus_df<-Productions_bymode_df%>%
  filter(On_campus==0)%>%
  filter(Trip_Purpose %in% c("UHC","UHO")) %>%
  group_by(Trip_Purpose)%>%
  summarize(segment = "Off_campus Students",
            trips=sum(Trips_Weighted),
            students=Offcampus_students,
            avg_trips=trips/students,
            respondents=Respondents_Offcampus_students,
            .groups = "drop")


w_avg_trips_bypurpose_UHC_UHO_df<-rbind(w_avg_trips_bypurpose_Oncampus_df,w_avg_trips_bypurpose_Offcampus_df)%>% 
  select(segment,
         Trip_Purpose, 
         avg_trips, 
         respondents)


# Trip production rates for UCO, UCC, and UC1 (not segmented by home location)
trips_bypurpose_byTAZ_df <- Trip_subset_df %>%  
  filter(Trip_Purpose=="UCO"|Trip_Purpose=="UCC" |Trip_Purpose=="UC1") %>%
  group_by(Trip_Purpose, TAZ_P)%>%
  summarize(weighted_trips = sum(Weight, na.rm = TRUE),
            .groups = "drop")%>%
  left_join(socioecon2_df, by=c("TAZ_P"="TAZ"))

avgtrips_bypurpose_bybldgsf_M2_df <- trips_bypurpose_byTAZ_df %>%
  filter(BuildingS_NCSU!=0 & !is.na(BuildingS_NCSU))%>%
  select(Trip_Purpose,
         weighted_trips, 
         BuildingS_NCSU) %>%
  mutate(weighted_trips = if_else(is.na(weighted_trips),0,weighted_trips))%>%
  group_by(Trip_Purpose)%>%
  summarize(total_trips = sum(weighted_trips), 
            total_SF = sum(BuildingS_NCSU),
            tripsper1000SF_M2= total_trips/total_SF)

w_avg_trips_bypurpose_UC1_UCO_UCC_df <- avgtrips_bypurpose_bybldgsf_M2_df %>%
  mutate(segment ="All_Students",
         respondents = Respondents_Oncampus_students + Respondents_Offcampus_students)%>%
  select(segment, 
         Trip_Purpose,
         avg_trips=tripsper1000SF_M2,
         respondents)

#Trip Production Rates by Mode for UOO trips ----------------------------------

w_avg_trips_bypurpose_bymode_df<-Productions_bymode_df%>%
  filter(!is.na(Primary_Mode))%>%
  mutate(mode = case_when (Primary_Mode == "Car" ~ "Auto",
                           Primary_Mode == "Carpool" ~ "Auto",
                           Primary_Mode == "Bus" ~ "Transit",
                           Primary_Mode == "Walk" ~ "Walk",
                           Primary_Mode == "Bicycle" ~ "Bicycle"))%>%
  filter(!is.na(Trips_Weighted)) %>%
  group_by(Trip_Purpose, mode)%>%
  summarize(segment="All Students",
            trips=sum(Trips_Weighted),
            students=Total_students,
            avg_trips=trips/students,
            count=n(),
            .groups = "drop")

w_avg_trips_UOO_df <-w_avg_trips_bypurpose_bymode_df %>%
  filter (Trip_Purpose == "UOO") %>%
  filter(!is.na(mode))%>%
  select(-c(Trip_Purpose, segment))

w_avg_trips_UHOUCO_df <-w_avg_trips_bypurpose_bymode_df %>%
  filter (Trip_Purpose == "UHO"| Trip_Purpose == "UCO") %>%
  filter(!is.na(mode))%>%
  select(-c(Trip_Purpose,segment,avg_trips))%>%
  group_by(mode)%>%
  summarize(trips=sum(trips),
            students=Total_students,
            avg_trips=trips/students,
           count=sum(count),
          .groups = "drop")

w_sumavg_trips_UOO_df <- w_avg_trips_UOO_df %>%
  mutate(carnocar = if_else(mode == "Auto", "Car", "No-Car"))%>%
  filter(!is.na(carnocar))%>%
  group_by(carnocar) %>%
    summarize(trips=sum(trips),
              students = Total_students,
              avg_trips = trips/students)

car_triprate_UOO <- w_sumavg_trips_UOO_df %>%
  filter(carnocar=="Car") %>%
  select(avg_trips)%>%
  pull()

noncar_triprate_UOO <- w_sumavg_trips_UOO_df %>%
  filter(carnocar=="No-Car")%>%
  select(avg_trips)%>%
  pull()

w_sumavg_trips_UHOUCO_df <- w_avg_trips_UHOUCO_df %>%
  mutate(carnocar = if_else(mode == "Auto", "Car", "No-Car")) %>%
  filter(!is.na(carnocar))%>%
  group_by(carnocar) %>%
  summarize(trips=sum(trips),
            students = Total_students,
            avg_trips = trips/students)

car_triprate_UHOUCO <- w_sumavg_trips_UHOUCO_df %>%
  filter(carnocar=="Car")%>%
  select(avg_trips)%>%
  pull()

noncar_triprate_UHOUCO <- w_sumavg_trips_UHOUCO_df %>%
  filter(carnocar=="No-Car")%>%
  select(avg_trips)%>%
  pull()

w_cartrips_ratioUOOtoUHOUCO <- car_triprate_UOO/car_triprate_UHOUCO

w_non_cartrips_ratioUOOtoUHOUCO <- noncar_triprate_UOO/noncar_triprate_UHOUCO


Ratios_P_rates_ratioUOOtoUHOUCO_df <-tibble( mode = c("Car","No_Car"),
                                             rate = c(w_cartrips_ratioUOOtoUHOUCO,w_non_cartrips_ratioUOOtoUHOUCO))


# Selected Production Rates-----------------------------------------------------
w_avg_trips_bypurpose_df <- 
rbind(w_avg_trips_bypurpose_UHC_UHO_df,w_avg_trips_bypurpose_UC1_UCO_UCC_df)

P_rates_df<-w_avg_trips_bypurpose_df %>% 
  select(segment,
         Trip_Purpose, 
         avg_trips, 
         respondents) %>% 
  rename("Production Rate"= avg_trips, 
         "Sample Size"= respondents) 

# Apply Selected Production Rates-----------------------------------------------
# Apply productions for UHC, UHO, UCO, UC1  
selected_columns<-c(1,25:52)

Apply_Productions_df<-socioecon2_df %>%
  select(TAZ,
         StudGQ_NCSU, 
         StudGQ_UNC,
         StudGQ_NCCU,
         StudGQ_DUKE,
         StudOff_NCSU,
         StudOff_UNC,
         StudOff_DUKE,
         StudOff_NCCU,
         Share_Bldg_NCSU,
         Share_Bldg_UNC,
         Share_Bldg_DUKE,
         Share_Bldg_NCCU,
         BuildingS_NCSU,
         BuildingS_UNC,
         BuildingS_DUKE,
         BuildingS_NCCU)%>%
  
  mutate(P_rate_On_UHC=P_rates_df$'Production Rate'[P_rates_df$segment == "On_campus Students" & P_rates_df$Trip_Purpose =="UHC"],
         P_rate_On_UHO=P_rates_df$'Production Rate'[P_rates_df$segment == "On_campus Students" & P_rates_df$Trip_Purpose =="UHO"],
         P_rate_All_UCO=P_rates_df$'Production Rate'[P_rates_df$segment == "All_Students" & P_rates_df$Trip_Purpose =="UCO"],
         P_rate_All_UC1=P_rates_df$'Production Rate'[P_rates_df$segment == "All_Students" & P_rates_df$Trip_Purpose =="UC1"],
         P_rate_All_UCC=P_rates_df$'Production Rate'[P_rates_df$segment == "All_Students" & P_rates_df$Trip_Purpose =="UCC"],
         
         P_rate_Off_UHC=P_rates_df$'Production Rate'[P_rates_df$segment == "Off_campus Students" & P_rates_df$Trip_Purpose =="UHC"],
         P_rate_Off_UHO=P_rates_df$'Production Rate'[P_rates_df$segment == "Off_campus Students" & P_rates_df$Trip_Purpose =="UHO"],
        
         Productions_UHC_On_Campus_NCSU = StudGQ_NCSU * P_rate_On_UHC,
         Productions_UHO_On_Campus_NCSU = StudGQ_NCSU * P_rate_On_UHO,
         Productions_UCO_All_Campus_NCSU = BuildingS_NCSU * P_rate_All_UCO,
         Productions_UC1_All_Campus_NCSU = BuildingS_NCSU * P_rate_All_UC1,
         Productions_UCC_All_Campus_NCSU = BuildingS_NCSU * P_rate_All_UCC,
         
         Productions_UHC_Off_Campus_NCSU = StudOff_NCSU * P_rate_Off_UHC,
         Productions_UHO_Off_Campus_NCSU = StudOff_NCSU * P_rate_Off_UHO,
        
         Productions_UHC_On_Campus_UNC = StudGQ_UNC * P_rate_On_UHC,
         Productions_UHO_On_Campus_UNC = StudGQ_UNC * P_rate_On_UHO,
         Productions_UCO_All_Campus_UNC = BuildingS_UNC * P_rate_All_UCO,
         Productions_UC1_All_Campus_UNC = BuildingS_UNC * P_rate_All_UC1,
         Productions_UCC_All_Campus_UNC = BuildingS_UNC * P_rate_All_UCC,
         
         Productions_UHC_Off_Campus_UNC = StudOff_UNC * P_rate_Off_UHC,
         Productions_UHO_Off_Campus_UNC = StudOff_UNC * P_rate_Off_UHO,
         
         Productions_UHC_On_Campus_Duke = StudGQ_DUKE * P_rate_On_UHC,
         Productions_UHO_On_Campus_Duke = StudGQ_DUKE * P_rate_On_UHO,
         Productions_UCO_All_Campus_Duke = BuildingS_DUKE *  P_rate_All_UCO,
         Productions_UC1_All_Campus_Duke = BuildingS_DUKE * P_rate_All_UC1,
         Productions_UCC_All_Campus_Duke = BuildingS_DUKE * P_rate_All_UCC,
         
         Productions_UHC_Off_Campus_Duke = StudOff_DUKE * P_rate_Off_UHC,
         Productions_UHO_Off_Campus_Duke = StudOff_DUKE * P_rate_Off_UHO,

         Productions_UHC_On_Campus_NCCU = StudGQ_NCCU * P_rate_On_UHC,
         Productions_UHO_On_Campus_NCCU = StudGQ_NCCU * P_rate_On_UHO,
         Productions_UCO_All_Campus_NCCU = BuildingS_NCCU * P_rate_All_UCO,
         Productions_UC1_All_Campus_NCCU = BuildingS_NCCU * P_rate_All_UC1,
         Productions_UCC_All_Campus_NCCU = BuildingS_NCCU * P_rate_All_UCC,
         
         Productions_UHC_Off_Campus_NCCU = StudOff_NCCU * P_rate_Off_UHC,
         Productions_UHO_Off_Campus_NCCU = StudOff_NCCU * P_rate_Off_UHO)%>%
           
   select(all_of(selected_columns))

Summary_Productions_df<-Apply_Productions_df %>%
  summarize_all(sum) %>% 
  select(c(2:29)) %>%
  pivot_longer(c(1:28),names_to ="Segments",values_to = "Productions")

#Summary_Productions_df

# Output------------------------------------------------------------------------

saveRDS(Summary_Productions_df,paste0(univ_dir,"Summary_Productions.RDS"))
saveRDS(Summary_Productions_df,paste0(univ_dir,"Apply_Productions.RDS"))
write_csv(P_rates_df,paste0(univ_dir,"P_rates.CSV"))
write_csv(Ratios_P_rates_ratioUOOtoUHOUCO_df, paste0(univ_dir,"P_rates_ratioUOOtoUHOUCO.CSV"))

