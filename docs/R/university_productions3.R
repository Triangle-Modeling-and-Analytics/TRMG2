# Packages ---------------------------------------------------------------------
packages_vector <- c("tidyverse",
                     "corrr",
                     "kableExtra",
                     "broom"
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

# Data Reads -------------------------------------------------------------------
Productions_bymode_df<- readRDS(paste0(private_dir,"Productions_bymode_df.RDS"))
Trip_subset_df<-readRDS(paste0(private_dir,"Trip_subset_df.RDS"))
Person_subset_df<-readRDS(paste0(private_dir,"Person_subset_df.RDS"))
socioecon2_df<-readRDS(paste0(input_dir,"socioecon2_df.RDS")) 
 
# Enrollment by University -----------------------------------------------------
enrollment_NCSU<-socioecon2_df %>% 
  filter(!is.na(StudGQ_NCSU),!is.na(StudOff_NCSU))%>% 
  summarize(total=sum(StudGQ_NCSU,StudOff_NCSU))%>%
  pull(total)

enrollment_UNC<-socioecon2_df %>%
  filter(!is.na(StudGQ_UNC),!is.na(StudOff_UNC))%>% 
  summarize(total=sum(StudGQ_UNC,StudOff_UNC))%>%
  pull(total)

enrollment_Duke<-socioecon2_df %>% 
  filter(!is.na(StudGQ_DUKE),!is.na(StudOff_DUKE))%>% 
  summarize(total=sum(StudGQ_DUKE,StudOff_DUKE))%>%
  pull(total)

enrollment_NCCU<-socioecon2_df %>% 
  filter(!is.na(StudGQ_NCCU),!is.na(StudOff_NCCU))%>% 
  summarize(total=sum(StudGQ_NCCU,StudOff_NCCU))%>%
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
  summarize(count=n())

# Trip Production Histograms ---------------------------------------------------
Triprates_histogram<-Productions_bymode_df %>% 
  group_by(Person_ID,
           Trip_Purpose, 
           On_campus)%>%
  summarize(Trips_per_student=sum(Trips),.groups = "drop")%>%
  group_by(On_campus) %>% 
  ggplot(aes(Trips_per_student, fill=Trip_Purpose)) + 
  geom_histogram(bins=20) + 
  facet_grid(Trip_Purpose~On_campus)

Triprates_histogram + labs(title = "Figure 1 - Trips per student by purpose", 
                           subtitle="for off-campus students (On_campus==0) and on-campus students (On_campus==1) students", 
                           caption = ("Source: NCSU survey (unweighted)"))


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

avg_trips_bypurpose_Oncampus_df<-Productions_bymode_df%>%
  filter(On_campus==1)%>%
  group_by(Trip_Purpose)%>%
  summarize(segment="On-campus Students",
            trips=sum(Trips),
            respondents=Respondents_Oncampus_students,
            avg_trips=trips/respondents,
            .groups = "drop")

avg_trips_bypurpose_Offcampus_df<-Productions_bymode_df%>%
  filter(On_campus==0)%>%
  group_by(Trip_Purpose)%>%
  summarize(segment="Off-campus Students",
            trips=sum(Trips),
            respondents=Respondents_Offcampus_students,
            avg_trips=trips/respondents,
            .groups = "drop")

avg_trips_bypurpose_df<-rbind(avg_trips_bypurpose_Oncampus_df,avg_trips_bypurpose_Offcampus_df)
avg_trips_bypurpose_col=c("segment","Trip_Purpose","avg_trips","respondents")

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

w_avg_trips_bypurpose_Oncampus_df<-Productions_bymode_df%>%
  filter(On_campus==1 & !is.na(Weight))%>%
  group_by(Trip_Purpose)%>%
  summarize(segment="On_campus Students",
            trips=sum(Trips_Weighted),
            students=Oncampus_students,
            avg_trips=trips/students,
            respondents=Respondents_Oncampus_students,
            .groups = "drop")

w_avg_trips_bypurpose_Offcampus_df<-Productions_bymode_df%>%
  filter(On_campus==0)%>%
  group_by(Trip_Purpose)%>%
  summarize(segment = "Off_campus Students",
            trips=sum(Trips_Weighted),
            students=Offcampus_students,
            avg_trips=trips/students,
            respondents=Respondents_Offcampus_students,
            .groups = "drop")


w_avg_trips_bypurpose_df<-rbind(w_avg_trips_bypurpose_Oncampus_df,w_avg_trips_bypurpose_Offcampus_df)
w_avg_trips_bypurpose_col=c("segment","Trip_Purpose","avg_trips","respondents")

# summarize weighted and raw trip rates

headers<-c("Segment","Trip Purpose","Trip Rate", "Segment Sample Size")
kable(avg_trips_bypurpose_df[,avg_trips_bypurpose_col],caption ="Trip Rates by Purpose",col.names=headers)
kable(w_avg_trips_bypurpose_df[,w_avg_trips_bypurpose_col],caption ="Weighted Trip Rates by Purpose",col.names = headers)


# Trip Production Rates by Mode for UOO trips ----------------------------------
## Trip Production Rates by modes by purpose -----------------------------------
avg_trips_bypurpose_Oncampus_bymode_df<-Productions_bymode_df%>%
  filter(On_campus==1)%>%
  filter(!is.na(Primary_Mode))%>%
  group_by(Trip_Purpose, Primary_Mode)%>%
  summarize(segment="On-campus Students",
            trips=sum(Trips),
            respondents=Respondents_Oncampus_students,
            avg_trips=trips/respondents,
            count=n(),
            .groups = "drop")

avg_trips_bypurpose_Offcampus_bymode_df<-Productions_bymode_df%>%
  filter(On_campus==0)%>%
  filter(!is.na(Primary_Mode))%>%
  group_by(Trip_Purpose, Primary_Mode)%>%
  summarize(segment="Off-campus Students",
            trips=sum(Trips),
            respondents=Respondents_Offcampus_students,
            avg_trips=trips/respondents,
            count=n(),
            .groups = "drop")

avg_trips_bypurpose_bymode_df<-rbind(avg_trips_bypurpose_Oncampus_bymode_df,avg_trips_bypurpose_Offcampus_bymode_df)
avg_trips_bypurpose_bymode_col=c("segment", "Trip_Purpose", "Primary_Mode", "avg_trips", "count", "respondents")

headers<-c("Segment","Trip Purpose","Mode","Trip Rate", "Respondents", "Segment Sample Size")
kable(avg_trips_bypurpose_bymode_df [,avg_trips_bypurpose_bymode_col],caption ="Trip Rates by Purpose by Mode",col.names=headers)

## Trip Rates for UHO and UCO combined, by mode (basis for UOO trip rates)-------
avg_trips_UHOUCO_Oncampus_bymode_df<-Productions_bymode_df%>%
  filter(On_campus==1) %>%
  filter(UHO==1|UCO==1)%>%
  filter(!is.na(Primary_Mode))%>%
  group_by(Primary_Mode)%>%
  summarize(segment="On-campus Students UHO UCO Trips",
            trips=sum(Trips),
            respondents=Respondents_Oncampus_students,
            avg_trips=trips/respondents,
            count=n(),
            .groups = "drop")

avg_trips_UHOUCO_Offcampus_bymode_df<-Productions_bymode_df%>%
  filter(On_campus==0)%>%
  filter(UHO==1|UCO==1)%>%
  filter(!is.na(Primary_Mode))%>%
  group_by(Primary_Mode)%>%
  summarize(segment="Off-campus Students UHO UCO Trips",
            trips=sum(Trips),
            respondents=Respondents_Offcampus_students,
            avg_trips=trips/respondents,
            count=n(),
            .groups = "drop")

avg_trips_UHOUCO_df<-rbind(avg_trips_UHOUCO_Oncampus_bymode_df,avg_trips_UHOUCO_Offcampus_bymode_df)
avg_trips_UHOUCO_col=c("segment","Primary_Mode","avg_trips","count","respondents")
headers<-c("Segment","Mode","Trip Rate", "Respondents", "Segment Sample Size")
#kable(avg_trips_UHOUCO_df[,avg_trips_UHOUCO_col],caption ="UHO and UCO Trip Rates by Mode",col.names=headers)


## Trip Rates for UHO and UCO combined, car/no car --------------------------------
sumavg_trips_UHOUCO_df <-avg_trips_UHOUCO_df %>%
  mutate(oncampus_car = if_else(segment == "On-campus Students UHO UCO Trips" & 
                                  (Primary_Mode == "Car" | Primary_Mode == "Carpool"), 1, 0) * trips,
         oncampus_noncar = if_else(segment == "On-campus Students UHO UCO Trips" & 
                                     Primary_Mode != "Car" & Primary_Mode != "Carpool", 1, 0) * trips,
         offcampus_car = if_else(segment == "Off-campus Students UHO UCO Trips" & 
                                   (Primary_Mode == "Car" | Primary_Mode == "Carpool"), 1, 0) * trips,
         offcampus_noncar = if_else(segment == "Off-campus Students UHO UCO Trips" & 
                                      Primary_Mode != "Car" & Primary_Mode != "Carpool", 1, 0) * trips,
         car = if_else(Primary_Mode == "Car" | Primary_Mode == "Carpool", 1, 0) * trips,
         non_car = if_else(Primary_Mode != "Car" & Primary_Mode != "Carpool", 1, 0) * trips)%>%
  summarize(oncampus_car = sum(oncampus_car),
            oncampus_noncar= sum(oncampus_noncar),
            offcampus_car = sum(offcampus_car),
            offcampus_noncar = sum(offcampus_noncar),
            car = sum(car),
            non_car = sum(non_car),
            ssize_oncampus = min(respondents[segment=="On-campus Students UHO UCO Trips"]),
            ssize_offcampus = min(respondents[segment=="Off-campus Students UHO UCO Trips"]))
sumavg_trips_UHOUCO_df

## Trip Rates UOO, by mode -----------------------------------------------------
avg_trips_UOO_Oncampus_bymode_df<-avg_trips_bypurpose_Oncampus_bymode_df %>%
  filter (Trip_Purpose == "UOO") %>%
  select(-c(Trip_Purpose))

avg_trips_UOO_Offcampus_bymode_df<-avg_trips_bypurpose_Offcampus_bymode_df %>%
  filter (Trip_Purpose == "UOO") %>%
  select(-c(Trip_Purpose))

avg_trips_UOO_df<-rbind(avg_trips_UOO_Oncampus_bymode_df,avg_trips_UOO_Offcampus_bymode_df)
avg_trips_UHOUCOUOO_df<-rbind(avg_trips_UHOUCO_df,avg_trips_UOO_df)

avg_trips_UOO_col=c("segment","Primary_Mode","avg_trips","count","respondents")
headers<-c("Segment","Mode","Trip Rate", "Respondents", "Segment Sample Size")
#kable(avg_trips_UHOUCOUOO_df[,avg_trips_UOO_col],caption ="Trip Rates by Mode",col.names=headers)

## Trip Rates UOO, car/no car -----------------------------------------------------

sumavg_trips_UOO_df <-avg_trips_UOO_df %>%
  mutate(oncampus_car = if_else(segment == "On-campus Students" & 
                                  (Primary_Mode == "Car" | Primary_Mode == "Carpool"), 1, 0) * trips,
         oncampus_noncar = if_else(segment == "On-campus Students" & 
                                     Primary_Mode != "Car" & Primary_Mode != "Carpool", 1, 0) * trips,
         offcampus_car = if_else(segment == "Off-campus Students" & 
                                   (Primary_Mode == "Car" | Primary_Mode == "Carpool"), 1, 0) * trips,
         offcampus_noncar = if_else(segment == "Off-campus Students" & 
                                      Primary_Mode != "Car" & Primary_Mode != "Carpool", 1, 0) * trips,
         car = if_else(Primary_Mode == "Car" | Primary_Mode == "Carpool", 1, 0) * trips,
         non_car = if_else(Primary_Mode != "Car" & Primary_Mode != "Carpool", 1, 0) * trips) %>%
  summarize(oncampus_car = sum(oncampus_car),
            oncampus_noncar= sum(oncampus_noncar),
            offcampus_car = sum(offcampus_car),
            offcampus_noncar = sum(offcampus_noncar),
            car = sum(car),
            non_car = sum(non_car),
            ssize_oncampus = min(respondents[segment=="On-campus Students"]),
            ssize_offcampus = min(respondents[segment=="Off-campus Students"]))

sumavg_trips_UOO_df

## ratio UOO/UHOUCO

trip_purpose<-c("UHOUCO","UOO")

sumavg_trips_UHOUCOUOO_df <- cbind(rbind(sumavg_trips_UHOUCO_df,sumavg_trips_UOO_df),trip_purpose)

cartrips_ratioUOOtoUHOUCO <- sumavg_trips_UHOUCOUOO_df$car[trip_purpose == "UOO"]/
  sumavg_trips_UHOUCOUOO_df$car[trip_purpose == "UHOUCO"]

non_cartrips_ratioUOOtoUHOUCO <- sumavg_trips_UHOUCOUOO_df$non_car[trip_purpose == "UOO"]/
  sumavg_trips_UHOUCOUOO_df$non_car[trip_purpose == "UHOUCO"]

P_rates_ratioUOOtoUHOUCO_df <-data_frame(cartrips_ratioUOOtoUHOUCO,non_cartrips_ratioUOOtoUHOUCO)


# Selected Production Rates-----------------------------------------------------
P_rates_df<-w_avg_trips_bypurpose_df %>% 
  select(segment,
         Trip_Purpose, 
         avg_trips, 
         respondents) %>% 
  rename("Production Rate"= avg_trips, 
         "Sample Size"= respondents) %>%
  filter(Trip_Purpose =="UC1" | 
           Trip_Purpose == "UCO" |
           Trip_Purpose == "UHC" |  
           Trip_Purpose == "UHO" |
           Trip_Purpose == "UCC")

# Apply Selected Production Rates-----------------------------------------------
# Apply productions for UHC, UHO, UCO, UC1  
selected_columns<-c(1,24:63)

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
         Share_Bldg_NCCU)%>%
  
  mutate(P_rate_On_UHC=P_rates_df$'Production Rate'[P_rates_df$segment == "On_campus Students" & P_rates_df$Trip_Purpose =="UHC"],
         P_rate_On_UHO=P_rates_df$'Production Rate'[P_rates_df$segment == "On_campus Students" & P_rates_df$Trip_Purpose =="UHO"],
         P_rate_On_UCO=P_rates_df$'Production Rate'[P_rates_df$segment == "On_campus Students" & P_rates_df$Trip_Purpose =="UCO"],
         P_rate_On_UC1=P_rates_df$'Production Rate'[P_rates_df$segment == "On_campus Students" & P_rates_df$Trip_Purpose =="UC1"],
         P_rate_On_UCC=P_rates_df$'Production Rate'[P_rates_df$segment == "On_campus Students" & P_rates_df$Trip_Purpose =="UCC"],
         
         P_rate_Off_UHC=P_rates_df$'Production Rate'[P_rates_df$segment == "Off_campus Students" & P_rates_df$Trip_Purpose =="UHC"],
         P_rate_Off_UHO=P_rates_df$'Production Rate'[P_rates_df$segment == "Off_campus Students" & P_rates_df$Trip_Purpose =="UHO"],
         P_rate_Off_UCO=P_rates_df$'Production Rate'[P_rates_df$segment == "Off_campus Students" & P_rates_df$Trip_Purpose =="UCO"],
         P_rate_Off_UC1=P_rates_df$'Production Rate'[P_rates_df$segment == "Off_campus Students" & P_rates_df$Trip_Purpose =="UC1"],
         P_rate_Off_UCC=P_rates_df$'Production Rate'[P_rates_df$segment == "Off_campus Students" & P_rates_df$Trip_Purpose =="UCC"],
         
         Productions_UHC_On_Campus_NCSU = StudGQ_NCSU * P_rate_On_UHC,
         Productions_UHO_On_Campus_NCSU = StudGQ_NCSU * P_rate_On_UHO,
         Productions_UCO_On_Campus_NCSU = Share_Bldg_NCSU * enrollment_NCSU * P_rate_On_UCO,
         Productions_UC1_On_Campus_NCSU = Share_Bldg_NCSU * enrollment_NCSU * P_rate_On_UC1,
         Productions_UCC_On_Campus_NCSU = Share_Bldg_NCSU * enrollment_NCSU * P_rate_On_UCC,
         
         Productions_UHC_Off_Campus_NCSU = StudOff_NCSU * P_rate_Off_UHC,
         Productions_UHO_Off_Campus_NCSU = StudOff_NCSU * P_rate_Off_UHO,
         Productions_UCO_Off_Campus_NCSU = Share_Bldg_NCSU * enrollment_NCSU * P_rate_Off_UCO,
         Productions_UC1_Off_Campus_NCSU = Share_Bldg_NCSU * enrollment_NCSU * P_rate_Off_UC1,
         Productions_UCC_Off_Campus_NCSU = Share_Bldg_NCSU * enrollment_NCSU * P_rate_Off_UCC,
         
         Productions_UHC_On_Campus_UNC = StudGQ_UNC * P_rate_On_UHC,
         Productions_UHO_On_Campus_UNC = StudGQ_UNC * P_rate_On_UHO,
         Productions_UCO_On_Campus_UNC = Share_Bldg_UNC * enrollment_UNC * P_rate_On_UCO,
         Productions_UC1_On_Campus_UNC = Share_Bldg_UNC * enrollment_UNC * P_rate_On_UC1,
         Productions_UCC_On_Campus_UNC = Share_Bldg_UNC * enrollment_UNC * P_rate_On_UCC,
         
         Productions_UHC_Off_Campus_UNC = StudOff_UNC * P_rate_Off_UHC,
         Productions_UHO_Off_Campus_UNC = StudOff_UNC * P_rate_Off_UHO,
         Productions_UCO_Off_Campus_UNC = Share_Bldg_UNC * enrollment_UNC*P_rate_Off_UCO,
         Productions_UC1_Off_Campus_UNC = Share_Bldg_UNC * enrollment_UNC*P_rate_Off_UC1,
         Productions_UCC_Off_Campus_UNC = Share_Bldg_UNC * enrollment_UNC*P_rate_Off_UCC,
         
         Productions_UHC_On_Campus_Duke = StudGQ_DUKE * P_rate_On_UHC,
         Productions_UHO_On_Campus_Duke = StudGQ_DUKE * P_rate_On_UHO,
         Productions_UCO_On_Campus_Duke = Share_Bldg_DUKE * enrollment_Duke * P_rate_On_UCO,
         Productions_UC1_On_Campus_Duke = Share_Bldg_DUKE * enrollment_Duke * P_rate_On_UC1,
         Productions_UCC_On_Campus_Duke = Share_Bldg_DUKE * enrollment_Duke * P_rate_On_UCC,
         
         Productions_UHC_Off_Campus_Duke = StudOff_DUKE * P_rate_Off_UHC,
         Productions_UHO_Off_Campus_Duke = StudOff_DUKE * P_rate_Off_UHO,
         Productions_UCO_Off_Campus_Duke = Share_Bldg_DUKE * enrollment_Duke * P_rate_Off_UCO,
         Productions_UC1_Off_Campus_Duke = Share_Bldg_DUKE * enrollment_Duke * P_rate_Off_UC1,
         Productions_UCC_Off_Campus_Duke = Share_Bldg_DUKE * enrollment_Duke * P_rate_Off_UCC,
         
         Productions_UHC_On_Campus_NCCU = StudGQ_NCCU * P_rate_On_UHC,
         Productions_UHO_On_Campus_NCCU = StudGQ_NCCU * P_rate_On_UHO,
         Productions_UCO_On_Campus_NCCU = Share_Bldg_NCCU * enrollment_NCCU * P_rate_On_UCO,
         Productions_UC1_On_Campus_NCCU = Share_Bldg_NCCU * enrollment_NCCU * P_rate_On_UC1,
         Productions_UCC_On_Campus_NCCU = Share_Bldg_NCCU * enrollment_NCCU * P_rate_On_UCC,
         
         Productions_UHC_Off_Campus_NCCU = StudOff_NCCU * P_rate_Off_UHC,
         Productions_UHO_Off_Campus_NCCU = StudOff_NCCU * P_rate_Off_UHO,
         Productions_UCO_Off_Campus_NCCU = Share_Bldg_NCCU * enrollment_NCCU * P_rate_Off_UCO,
         Productions_UC1_Off_Campus_NCCU = Share_Bldg_NCCU * enrollment_NCCU * P_rate_Off_UC1, 
         Productions_UCC_Off_Campus_NCCU = Share_Bldg_NCCU * enrollment_NCCU * P_rate_Off_UCC)%>%
           
   select(selected_columns)

Summary_Productions_df<-Apply_Productions_df%>%
  summarize_all(sum) %>% 
  select(c(2:41)) %>%
  pivot_longer(c(1:40),names_to ="Segments",values_to = "Productions")

Summary_Productions_df

# Output------------------------------------------------------------------------

write_rds(Summary_Productions_df,paste0(univ_dir,"Summary_Productions_df.RDS"))
write_csv(P_rates_df,paste0(univ_dir,"P_rates.CSV"))
write_csv(P_rates_ratioUOOtoUHOUCO_df, paste0(univ_dir,"P_rates_ratioUOOtoUHOUCO.CSV"))
