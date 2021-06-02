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
univ_dir<-"data/output/"

# Data Reads -------------------------------------------------------------------

Attractions_byTAZbySegment_df<-readRDS(paste0(private_dir,"Attractions_byTAZbySegment_df.RDS"))
Attractions_byTAZ_df<-readRDS(paste0(private_dir,"Attractions_byTAZ_df.RDS"))
Trip_subset_df<-readRDS(paste0(private_dir,"Trip_subset_df.RDS"))
Person_subset_df<-readRDS(paste0(private_dir,"Person_subset_df.RDS"))
socioecon2_df<-readRDS(paste0(univ_dir,"socioecon3_df.RDS"))
distance_TAZcampus_df<-socioecon2_df %>% select(TAZ,
                                                NCSU_min_distance, 
                                                NCSU_avg_distance,
                                                UNC_min_distance, 
                                                UNC_avg_distance,
                                                Duke_min_distance, 
                                                Duke_avg_distance,
                                                NCCU_min_distance, 
                                                NCCU_avg_distance)

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


# Data for off-campus attraction models ---------------------------------------
# all tazs
All_fromcampus_ON_df<-Attractions_byTAZ_df%>%
  filter(!is.na(W_On_UCOTrips) & !is.na(W_On_UHOTrips))%>%
           mutate(W_OAtrips_fromCampus=W_On_UCOTrips +  W_On_UHOTrips)%>%
           left_join(distance_TAZcampus_df,by=c("TAZ_A" = "TAZ"))

All_fromcampus_OFF_df<-Attractions_byTAZ_df%>%
  filter(!is.na(W_Off_UCOTrips))%>%
  left_join(distance_TAZcampus_df,by=c("TAZ_A" = "TAZ"))

All_fromoffcampus_OFF_df<-Attractions_byTAZ_df%>%
 filter(!is.na(W_Off_UHOTrips))

# only tazs with trips for that purpose
UCO_ON_df<-Attractions_byTAZ_df%>%
  filter(W_On_UCOTrips>0)%>%
  left_join(distance_TAZcampus_df,by=c("TAZ_A" = "TAZ"))

UCO_OFF_df<-Attractions_byTAZ_df%>%
  filter(W_Off_UCOTrips>0)%>%
  left_join(distance_TAZcampus_df,by=c("TAZ_A" = "TAZ"))

UHO_ON_df<-Attractions_byTAZ_df%>%
  filter(W_On_UHOTrips>0)%>%
  left_join(distance_TAZcampus_df,by=c("TAZ_A" = "TAZ"))

UHO_OFF_df<-Attractions_byTAZ_df%>%
  filter(W_Off_UHOTrips>0)


# Regression models ------------------------------------------------------------
# Are there group quarters in  off-campus zones - zones are mixed campus-non-campus or 
# do group quarters include off-campus students?

# Productions on-campus & Attractions off-campus --------------------------------
### UCO Trips by On-Campus Students estimated with full dataset
Model_OnCampusUCO_1 = lm(OnCampusStudents_UCOTrips ~ StudOff_NCSU, data = Attractions_byTAZ_df)
tidy(Model_OnCampusUCO_1)
Model_OnCampusUCO_2 = lm(OnCampusStudents_UCOTrips ~ StudOff_NCSU + Retail,  data = Attractions_byTAZ_df)
tidy(Model_OnCampusUCO_2)

  Intercept_lm_modelOn_UCOTrips_2<- tidy(lm_modelOn_UCOTrips_2) %>%
    filter(term=="(Intercept)") %>% 
    select(estimate) %>% 
    pull(estimate)
  StudOff_NCSU_lm_modelOn_UCOTrips_2<- tidy(lm_modelOn_UCOTrips_2) %>%
    filter(term=="StudOff_NCSU") %>% 
    select(estimate) %>% 
    pull(estimate)
  Retail_lm_modelOn_UCOTrips_2<- tidy(lm_modelOn_UCOTrips_2) %>%
    filter(term=="Retail") %>% 
    select(estimate) %>% 
    pull(estimate)
  
  apply_lm_modelOn_UCOTrips_2 <- Attractions_byTAZ_df %>% 
    mutate(Predicted=Intercept_lm_modelOn_UCOTrips_2 + StudOff_NCSU_lm_modelOn_UCOTrips_2 * StudOff_NCSU + Retail_lm_modelOn_UCOTrips_2 * Retail) %>%
    mutate(Predicted2=lm_modelOn_UCOTrips_2model_03$coefficients["(Intercept)"] 
  plot_lm_modelOn_UCOTrips_2 <- apply_lm_modelOn_UCOTrips_2 %>%
    ggplot(aes(W_On_UCOTrips,Predicted)) +
    geom_point()


lm_modelOn_UCOTrips_3= lm(W_On_UCOTrips ~ StudOff_NCSU + Retail + NCSU_avg_distance, data = All_fromcampus_ON_df)
summary(lm_modelOn_UCOTrips_3)

Intercept_lm_modelOn_UCOTrips_3<- tidy(lm_modelOn_UCOTrips_3) %>%
  filter(term=="(Intercept)") %>% 
  select(estimate) %>% 
  pull(estimate)
StudOff_NCSU_lm_modelOn_UCOTrips_3<- tidy(lm_modelOn_UCOTrips_3) %>%
  filter(term=="StudOff_NCSU") %>% 
  select(estimate) %>% 
  pull(estimate)
Retail_lm_modelOn_UCOTrips_3<- tidy(lm_modelOn_UCOTrips_3) %>%
  filter(term=="Retail") %>% 
  select(estimate) %>% 
  pull(estimate)

apply_lm_modelOn_UCOTrips_3 <- Attractions_byTAZ_df %>% 
  mutate(Predicted=Intercept_lm_modelOn_UCOTrips_3 + StudOff_NCSU_lm_modelOn_UCOTrips_3 * StudOff_NCSU + Retail_lm_modelOn_UCOTrips_3 * Retail)
plot_lm_modelOn_UCOTrips_3 <- apply_lm_modelOn_UCOTrips_3 %>%
  ggplot(aes(W_On_UCOTrips,Predicted)) +
  geom_point()

glm_modelOn_UCOTrips_1 = glm(W_On_UCOTrips ~ StudOff_NCSU, family=poisson, data = All_fromcampus_ON_df)
summary(glm_modelOn_UCOTrips_1)

glm_modelOn_UCOTrips_2 = glm(W_On_UCOTrips ~ StudOff_NCSU + Retail, family=poisson, data = All_fromcampus_ON_df)
summary(glm_modelOn_UCOTrips_2)

### UCO Trips by On-Campus Students estimated based on TAZs with UCO Trips

selTAZ_lm_modelOn_UCOTrips_2 = lm(W_On_UCOTrips ~ StudOff_NCSU, data = UCO_ON_df)
summary(lm_modelOn_UCOTrips_2)

selTAZ_lm_modelOn_UCOTrips_3= lm(W_On_UCOTrips ~ StudOff_NCSU + Retail + NCSU_avg_distance, data = UCO_ON_df)
summary(selTAZ_lm_modelOn_UCOTrips_3)

Intercept_lm_modelOn_UCOTrips_3<- tidy(lm_modelOn_UCOTrips_3) %>%
  filter(term=="(Intercept)") %>% 
  select(estimate) %>% 
  pull(estimate)
StudOff_NCSU_lm_modelOn_UCOTrips_3<- tidy(lm_modelOn_UCOTrips_3) %>%
  filter(term=="StudOff_NCSU") %>% 
  select(estimate) %>% 
  pull(estimate)
Retail_lm_modelOn_UCOTrips_3<- tidy(lm_modelOn_UCOTrips_3) %>%
  filter(term=="Retail") %>% 
  select(estimate) %>% 
  pull(estimate)

apply_lm_modelOn_UCOTrips_3 <- Attractions_byTAZ_df %>% 
  mutate(Predicted=Intercept_lm_modelOn_UCOTrips_3 + StudOff_NCSU_lm_modelOn_UCOTrips_3 * StudOff_NCSU + Retail_lm_modelOn_UCOTrips_3 * Retail)
plot_lm_modelOn_UCOTrips_3 <- apply_lm_modelOn_UCOTrips_3 %>%
  ggplot(aes(W_On_UCOTrips,Predicted)) +
  geom_point()

### UHO Trips by On-Campus Students 

lm_modelOn_UHOTrips_1= lm(W_On_UHOTrips ~ StudOff_NCSU + Retail , data = All_fromcampus_ON_df)
summary(lm_modelOn_UHOTrips_1)

lm_modelOn_UHOTrips_2= lm(W_On_UHOTrips ~ StudOff_NCSU + Retail + NCSU_avg_distance, data = All_fromcampus_ON_df)
summary(lm_modelOn_UHOTrips_2)

selTAZ_lm_modelOn_UHOTrips_1= lm(W_On_UHOTrips ~ StudOff_NCSU + Retail , data = UHO_ON_df)
summary(selTAZ_lm_modelOn_UHOTrips_1)

selTAZ_lm_modelOn_UHOTrips_2= lm(W_On_UHOTrips ~ StudOff_NCSU + Retail , data = UHO_ON_df)
summary(selTAZ_lm_modelOn_UHOTrips_1)

### UCO Trips by Off-Campus Students

lm_modelOff_UCOTrips_1= lm(W_Off_UCOTrips ~ StudOff_NCSU + Retail , data = All_fromcampus_OFF_df)
summary(lm_modelOff_UCOTrips_1)

lm_modelOff_UCOTrips_2= lm(W_Off_UCOTrips ~ StudOff_NCSU + Retail + NCSU_avg_distance, data = All_fromcampus_OFF_df)
summary(lm_modelOff_UCOTrips_2)

selTAZ_lm_modelOff_UCOTrips_1= lm(W_Off_UCOTrips ~ StudOff_NCSU + Retail, data = UCO_OFF_df)
summary(selTAZ_lm_modelOff_UCOTrips_1)


# Regression models - Production and Attraction Off-campus-----------------------------------------------------------

### UHO Trips by Off-Campus Students
lm_modelOA_non_1 = lm(W_Off_UHOTrips ~ StudOff_NCSU , data = All_fromoffcampus_OFF_df)
summary(lm_modelOA_non_1)

lm_modelOA_non_2 = lm(W_Off_UHOTrips ~ StudOff_NCSU + Retail , data = All_fromoffcampus_OFF_df)
summary(lm_modelOA_non_2)

lm_modelOA_non_3 = lm(W_Off_UHOTrips ~ StudOff_NCSU + Retail + employment, data = All_fromoffcampus_OFF_df)
summary(lm_modelOA_non_3)

selTAZ_lm_modelOA_non_1 = lm(W_Off_UHOTrips ~ StudOff_NCSU + Retail , data = UHO_OFF_df)
summary(selTAZ_lm_modelOA_non_1)


