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

Attractions_byTAZbySegment_df<-readRDS(paste0(private_dir,"Attractions_byTAZbySegment_df.RDS"))
Attractions_byTAZ_df<-readRDS(paste0(private_dir,"Attractions_byTAZ_df.RDS"))
Trip_subset_df<-readRDS(paste0(private_dir,"Trip_subset_df.RDS"))
Person_subset_df<-readRDS(paste0(private_dir,"Person_subset_df.RDS"))
socioecon2_df<-readRDS(paste0(input_dir,"socioecon2_df.RDS"))
#distance_TAZcampus_df<-socioecon2_df %>% select(TAZ,
#                                                NCSU_min_distance, 
#                                                NCSU_avg_distance,
#                                                UNC_min_distance, 
#                                                UNC_avg_distance,
#                                                Duke_min_distance, 
#                                                Duke_avg_distance,
#                                                NCCU_min_distance, 
#                                                NCCU_avg_distance)

# Correlations -----------------------------------------------------------------
correlations_df <- Attractions_byTAZ_df %>%
  select(AllStudents_Trips,
         OnCampusStudents_Trips,
         OffCampusStudents_Trips,
         OnCampusStudents_UHOTrips,
         OnCampusStudents_UCOTrips,
         OnCampusStudents_UOOTrips,
         OnCampusStudents_UHOUCOTrips,
         OffCampusStudents_UHOTrips,
         OffCampusStudents_UCOTrips,
         OffCampusStudents_UOOTrips,
         OffCampusStudents_UHOUCOTrips,
         HH,
         Stud_GQ,
         StudGQ_NCSU,
         StudOff_NCSU,
         StudGQ_UNC,
         Total_POP,
         employment,
         Industry,
         Office,
         Service_RateHigh,
         Service_RateLow,
         Retail) %>%
  correlate() 

correlations_df

# Scatterplots -----------------------------------------------------------------

Retail_Trip_OnCampus_pl<-Attractions_byTAZ_df%>% 
  ggplot(aes(Retail,OnCampusStudents_Trips)) + 
  geom_point()+
  geom_smooth(method="lm")
LogRetail_LogTrip_OnCampus_pl<-Attractions_byTAZ_df%>%
  ggplot(aes(log10(Retail),log10(OnCampusStudents_Trips))) + 
  geom_point() + 
  geom_smooth(method="lm")
Retail_Trip_OnCampus_pl
LogRetail_LogTrip_OnCampus_pl


StudOffNCSU_Trip_OnCampus_pl<-Attractions_byTAZ_df%>% 
  ggplot(aes(StudOff_NCSU,OnCampusStudents_Trips)) + 
  geom_point()+
  geom_smooth(method="lm")
LogStudOffNCSU_LogTrip_OnCampus_pl<-Attractions_byTAZ_df%>%
  ggplot(aes(log10(StudOff_NCSU),log10(OnCampusStudents_Trips))) + 
  geom_point() + 
  geom_smooth(method="lm")
StudOffNCSU_Trip_OnCampus_pl
LogStudOffNCSU_LogTrip_OnCampus_pl

StudOffNCSU_Trip_OffCampus_pl<-Attractions_byTAZ_df%>% 
  ggplot(aes(StudOff_NCSU,OffCampusStudents_Trips)) + 
  geom_point()+
  geom_smooth(method="lm")
LogStudOffNCSU_LogTrip_OffCampus_pl<-Attractions_byTAZ_df%>%
  ggplot(aes(log10(StudOff_NCSU),log10(OffCampusStudents_Trips))) + 
  geom_point() + 
  geom_smooth(method="lm")
StudOffNCSU_Trip_OffCampus_pl
LogStudOffNCSU_LogTrip_OffCampus_pl




# Regression models ------------------------------------------------------------------------------------
 

# Productions on-campus & Attractions off-campus -------------------------------------------------------
### UCO (Campus-Other) Trips by On-Campus Students
### use model 3
Model_OnCampusUCO_1 = lm(OnCampusStudents_UCOTrips ~ StudOff_NCSU, data = Attractions_byTAZ_df)
tidy(Model_OnCampusUCO_1)

Model_OnCampusUCO_2 = lm(OnCampusStudents_UCOTrips ~ StudOff_NCSU + Retail,  data = Attractions_byTAZ_df)
tidy(Model_OnCampusUCO_2)

apply_Model_OnCampusUCO_2 <- Attractions_byTAZ_df %>% 
    mutate(Predicted = 
             Model_OnCampusUCO_2$coefficients["(Intercept)"] + 
             Model_OnCampusUCO_2$coefficients["StudOff_NCSU"] * StudOff_NCSU + 
             Model_OnCampusUCO_2$coefficients["Retail"] * Retail)
  
plot_Model_OnCampusUCO_2 <- apply_Model_OnCampusUCO_2 %>%
    ggplot(aes(OnCampusStudents_UCOTrips,Predicted)) +
    geom_point()

Model_OnCampusUCO_3 = lm(OnCampusStudents_UCOTrips ~ StudOff_NCSU + Retail + avg_distance_NCSU,  data = Attractions_byTAZ_df)
tidy(Model_OnCampusUCO_3)

Model_OnCampusUCO_4 = lm(OnCampusStudents_UCOTrips ~ StudOff_NCSU + Retail + min_distance_NCSU,  data = Attractions_byTAZ_df)
tidy(Model_OnCampusUCO_4)

### UHO (Home=Campus - Other )Trips by On-Campus Students 

Model_Oncampus_UHO_1= lm(OnCampusStudents_UHOTrips ~ StudOff_NCSU + Retail , data = Attractions_byTAZ_df)
tidy(Model_Oncampus_UHO_1)

Model_Oncampus_UHO_2= lm(OnCampusStudents_UHOTrips ~ StudOff_NCSU + Retail + avg_distance_NCSU , data = Attractions_byTAZ_df)
tidy(Model_Oncampus_UHO_2)


### UCO (Campus - Other) Trips by Off-Campus Students

Model_Offcampus_UCO_1= lm(OffCampusStudents_UCOTrips ~ StudOff_NCSU + Retail , data = Attractions_byTAZ_df)
tidy(Model_Offcampus_UCO_1)
summary(Model_Offcampus_UCO_1)

Model_Offcampus_UCO_2= lm(OffCampusStudents_UCOTrips ~ StudOff_NCSU + Retail + avg_distance_NCSU, data = Attractions_byTAZ_df)
summary(Model_Offcampus_UCO_2)



# Regression models - Production and Attraction Off-campus-----------------------------------------------------------

### UHO Trips by Off-Campus Students
Model_Offcampus_UHO_1 = lm(OffCampusStudents_UHOTrips ~ StudOff_NCSU , data = Attractions_byTAZ_df)
tidy(Model_Offcampus_UHO_1)
summary(Model_Offcampus_UHO_1)

Model_Offcampus_UHO_2 = lm(OffCampusStudents_UHOTrips ~ StudOff_NCSU + Retail , data = Attractions_byTAZ_df)
tidy(Model_Offcampus_UHO_2)
summary(Model_Offcampus_UHO_2)

Model_Offcampus_UHO_3 = lm(OffCampusStudents_UHOTrips ~ StudOff_NCSU + Retail + employment, data = Attractions_byTAZ_df)
tidy(Model_Offcampus_UHO_3)
summary(Model_Offcampus_UHO_3)
