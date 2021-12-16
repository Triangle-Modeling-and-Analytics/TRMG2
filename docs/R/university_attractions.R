# Packages ---------------------------------------------------------------------
library(tidyverse)
library(corrr)
library(kableExtra)
library(broom)

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

# Correlations -----------------------------------------------------------------
correlations_df <- Attractions_byTAZ_df %>%
  select(AllStudents_Trips,
         OnCampusStudents_UHOTrips,
         OffCampusStudents_UHOTrips,
         AllStudents_UCOTrips,
         AllStudents_UOOTrips,
         AllStudents_UHOUCOTrips,
         AllStudents_Trips,
         Households = HH,
         'NCSU Student Group Quarter Population' = StudGQ_NCSU,
         'NCSU Off-campus Student Population' = StudOff_NCSU,
         'UNC Student Group Quarters Population' = StudGQ_UNC,
         'Total Population' = Total_POP_rem,
         'Total Employment' = employment,
         'Industrial Employment' = Industry,
         'Office Employment' = Office,
         'Service Employment (High)' = Service_RateHigh,
         'Service Employment (Low)' = Service_RateLow,
         'Retail Employment' = Retail) %>%
  correlate() 


# Regression models ------------------------------------------------------------------------------------


# Productions on-campus & Attractions off-campus -------------------------------------------------------
### UCO (Campus-Other) Trips by On-Campus Students
### use model 3
Model_UCO_1 = lm(AllStudents_UCOTrips ~ StudOff_NCSU, data = Attractions_byTAZ_df)
tidy(Model_UCO_1)

Model_UCO_2 = lm(AllStudents_UCOTrips ~ StudOff_NCSU + Retail,  data = Attractions_byTAZ_df)
tidy(Model_UCO_2)

apply_Model_OnCampusUCO_2 <- Attractions_byTAZ_df %>% 
    mutate(Predicted = 
             Model_UCO_2$coefficients["(Intercept)"] + 
             Model_UCO_2$coefficients["StudOff_NCSU"] * StudOff_NCSU + 
             Model_UCO_2$coefficients["Retail"] * Retail)
  
plot_Model_UCO_2 <- apply_Model_OnCampusUCO_2 %>%
    ggplot(aes(OnCampusStudents_UCOTrips,Predicted)) +
    geom_point()

Model_UCO_3 = lm(AllStudents_UCOTrips ~ StudOff_NCSU + Retail + avg_distance_NCSU,  data = Attractions_byTAZ_df)
tidy(Model_UCO_3)

Model_UCO_4 = lm(AllStudents_UCOTrips ~ StudOff_NCSU + Retail + min_distance_NCSU,  data = Attractions_byTAZ_df)
tidy(Model_UCO_4)

### UHO (Home=Campus - Other )Trips by On-Campus Students 

Model_Oncampus_UHO_1= lm(OnCampusStudents_UHOTrips ~ StudOff_NCSU + Retail , data = Attractions_byTAZ_df)
tidy(Model_Oncampus_UHO_1)

Model_Oncampus_UHO_2= lm(OnCampusStudents_UHOTrips ~ StudOff_NCSU + Retail + avg_distance_NCSU , data = Attractions_byTAZ_df)
tidy(Model_Oncampus_UHO_2)



# Regression models - Production and Attraction Off-campus-----------------------------------------------------------

### UHO Trips by Off-Campus Students
Model_Offcampus_UHO_1 = lm(OffCampusStudents_UHOTrips ~ StudOff_NCSU , data = Attractions_byTAZ_df)
tidy(Model_Offcampus_UHO_1)
summary(Model_Offcampus_UHO_1)

Model_Offcampus_UHO_2 = lm(OffCampusStudents_UHOTrips ~ StudOff_NCSU + Retail , data = Attractions_byTAZ_df)
tidy(Model_Offcampus_UHO_2)
summary(Model_Offcampus_UHO_2)

