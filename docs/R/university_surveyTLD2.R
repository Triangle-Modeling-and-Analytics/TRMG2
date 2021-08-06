
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
apply_productions_filename <- paste0(univ_dir,"Apply_Produtions_df.RDS")

# Read data -------------------------------------------------------------------
trip_subset_df <-readRDS(trip_subset_filename)
Apply_Productions_df <-readRDS(apply_productions_filename)    

# Histogram trip distance zone to zone ----------------------------------------

zonetozonedistance_bypurpose_histogram<-trip_subset_df %>%
  filter(Trip_Purpose !="99")%>%
  filter(Trip_Purpose !="UC1")%>%
  filter(distance_zonetozone < 30)%>%
  group_by(On_campus,Trip_Purpose) %>%
  ggplot(aes(distance_zonetozone)) +
  geom_histogram(binwidth = 1) +
  facet_grid(On_campus ~ Trip_Purpose)

zonetozonedistance_bypurpose_histogram + labs(title = "Trip Length Distribution (All purposes,except UC1)", 
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






