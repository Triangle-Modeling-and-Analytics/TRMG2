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



# Histogram trip distance zone to zone

zonetozonedistance_allpurposes_histogram<-trip_subset_df %>%
  filter(Trip_Purpose !="99")%>%
  filter(Trip_Purpose !="UC1")%>%
  filter(distance_zonetozone < 30)%>%
  group_by(On_campus,Trip_Purpose) %>%
  ggplot(aes(distance_zonetozone)) +
  geom_histogram(binwidth = 1) +
  facet_grid(On_campus ~ Trip_Purpose)

zonetozonedistance_allpurposes_histogram + labs(title = "Trip Length Distribution (All purposes,except UC1)", 
                                              subtitle="for off-campus students (On_campus== 0) and on-campus students (On_campus == 1) students", 
                                              caption = ("Source: NCSU survey (unweighted)"))

zonetozonedistance_UC1_histogram<-trip_subset_df %>%
  filter(Trip_Purpose =="UC1")%>%
  group_by(On_campus) %>%
  ggplot(aes(distance_zonetozone)) +
  geom_histogram(binwidth = 1) +
  facet_grid(On_campus ~ .)
zonetozonedistance_UC1_histogram + labs(title = "Trip Length Distribution (UC1 Trips)", 
                                        subtitle="for off-campus students (On_campus== 0) and on-campus students (On_campus == 1) students", 
                                        caption = ("Source: NCSU survey (unweighted)"))

# Mode Split

trips_bypurpose_oncampus_pct_df<-trip_subset_df %>%
  filter(Trip_Purpose !="99") %>%
  filter(!is.na(Walk)) %>%
  filter(On_campus == 1) %>%
  group_by(Trip_Purpose)%>%
  summarize(Total = n(),
            Bicycle = sum(Bicycle)/Total * 100,
            Walk = sum(Walk)/Total * 100,
            Car = sum(Car)/Total * 100,
            Carpool = sum(Carpool)/Total * 100,
            Bus = sum(Bus)/Total * 100,
            Other = sum(Other)/Total * 100)
  #kable(digits = 1) %>%
  #kable_styling(full_width = FALSE)

sumtripsoncampusbymode<-sum(trips_bypurpose_oncampus_pct$Total)

trips_bypurpose_offcampus_pct_df<-trip_subset_df %>%
  filter(Trip_Purpose !="99") %>%
  filter(On_campus == 0) %>%
  filter(!is.na(Walk)) %>%
  group_by(Trip_Purpose)%>%
  summarize(Total = n(),
            Bicycle = sum(Bicycle)/Total * 100,
            Walk = sum(Walk)/Total * 100,
            Car = sum(Car)/Total * 100,
            Carpool = sum(Carpool)/Total * 100,
            Bus = sum(Bus)/Total * 100,
            Other = sum(Other)/Total * 100)
sumtripsoffcampusbymode<-sum(trips_bypurpose_offcampus_pct$Total)

# plots mode split

trips_bypurpose_oncampus_plot <-trip_subset_df %>%
  filter(Trip_Purpose != "99")%>%
  filter(Primary_Mode != "NA")%>%
  filter(On_campus == 1) %>%
  filter(Trip_Purpose != "UC1") %>%
  ggplot(aes(Trip_Purpose, fill=Primary_Mode)) + geom_bar(position="dodge")

trips_bypurpose_oncampus_plot + labs(title = "Mode Split by Purpose (except UC1)", 
                                     subtitle="On-campus students", 
                                     caption = ("Source: NCSU survey (unweighted)"))

trips_bypurpose_offcampus_plot <-trip_subset_df %>%
  filter(Trip_Purpose != "99")%>%
  filter(Primary_Mode != "NA")%>%
  filter(Trip_Purpose != "UC1") %>%
  filter(On_campus == 0) %>%
  ggplot(aes(Trip_Purpose, fill=Primary_Mode)) + geom_bar(position="dodge")

trips_bypurpose_offcampus_plot + labs(title = "Mode Split by Purpose (except UC1)", 
                                     subtitle="Off-campus students", 
                                     caption = ("Source: NCSU survey (unweighted)"))


# mode split based on car availability 
trips_bypurpose_oncampus_caravail_pct2_df<-trip_subset_df %>%
  filter(Trip_Purpose !="99") %>%
  filter(!is.na(Walk)) %>%
  filter(On_campus == 1) %>%
  filter(Have_car == "Yes" | (Have_car=="No" & Car!= 1)) %>%
  group_by(Trip_Purpose,
           Have_car)%>%
  summarize(Total = n(),
            Bicycle = sum(Bicycle)/Total * 100,
            Walk = sum(Walk)/Total * 100,
            Car = sum(Car)/Total * 100,
            Carpool = sum(Carpool)/Total * 100,
            Bus = sum(Bus)/Total * 100,
            Other = sum(Other)/Total * 100) 


  sumtripsoncampusbymode_clean<-sum(trips_bypurpose_oncampus_caravail_pct2$Total)

trips_bypurpose_offcampus_caravail_pct2_df<-trip_subset_df %>%
  filter(Trip_Purpose !="99") %>%
  filter(On_campus == 0) %>%
  filter(!is.na(Walk)) %>%
  filter(Have_car == "Yes" | (Have_car=="No" & Car!= 1)) %>%
  group_by(Trip_Purpose,
           Have_car)%>%
  summarize(Total = n(),
            Bicycle = sum(Bicycle)/Total * 100,
            Walk = sum(Walk)/Total * 100,
            Car = sum(Car)/Total * 100,
            Carpool = sum(Carpool)/Total * 100,
            Bus = sum(Bus)/Total * 100,
            Other = sum(Other)/Total * 100) 

sumtripsoffcampusbymode_clean<-sum(trips_bypurpose_offcampus_caravail_pct2$Total)




  


