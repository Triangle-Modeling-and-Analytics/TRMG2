dependent_vars <- c(
  "W_HB_O_All_hov",
  "W_HB_W_All_sov",
  "W_HB_O_All_sov",
  "W_HB_EK12_All_hov",
  "W_HB_O_All_walk",
  "W_HB_W_All_hov"
)
# trip_type <- "W_NH_WR_All_sov"
trip_type <- "N_NH_O_All_sov"
trips_df <- trips

estimate_nhb <- function(trips_df, trip_type, dependent_vars) {
  
  add_y <- trips_df
  add_y$trip_type <- ifelse(add_y$trip_type == trip_type, "y", add_y$trip_type)
  
  est_tbl <- add_y %>%
    select(personid, tour_num, trip_type, trip_weight_combined) %>%
    group_by(personid, tour_num) %>%
    mutate(keep = ifelse(any(trip_type == "y"), 1, 0)) %>%
    filter(keep == 1) %>%
    select(-keep) %>%
    filter(trip_type == "y" | !grepl("_NH_", trip_type)) %>%
    group_by(personid, tour_num, trip_type) %>%
    summarize(trips = sum(trip_weight_combined)) %>%
    pivot_wider(names_from = trip_type, values_from = trips) %>%
    relocate("y", .before = personid) %>%
    ungroup() %>%
    mutate(
      across(everything(), ~ifelse(is.na(.x), 0, .x)),
    ) %>%
    select(-personid, -tour_num)
  
  if (!is.null(dependent_vars)) {
    est_tbl <- est_tbl[, c("y", dependent_vars)]
  }
  
  model <- lm(y ~ . + 0, data = est_tbl)
  broom::tidy(model) %>%
    mutate(p.value = round(p.value, 5))
}

estimate_nhb2 <- function(trips_df, trip_type, dependent_vars) {
  
  add_y <- trips_df
  add_y$trip_type <- ifelse(add_y$trip_type == trip_type, "y", add_y$trip_type)
  
  est_tbl <- add_y %>%
    select(
      personid, tour_num, homebased, trip_type, trips = trip_weight_combined
    ) %>%
    group_by(personid, tour_num) %>%
    mutate(
      trips_generated = ifelse(lead(trip_type) == "y", lead(trips), 0),
      trips_generated = trips_generated / trips
    ) %>%
    replace_na(list(trips_generated = 0)) %>%
    filter(trip_type != "y" & !grepl("_NH_", trip_type)) %>%
    group_by(trip_type) %>%
    summarize(trips = mean(trips_generated)) %>%
    filter(trips > 0)
  
  est_tbl
}