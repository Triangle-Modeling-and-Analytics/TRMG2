# trip_type <- "N_NH_OME_All_sov"
# trips_df <- trips
# boost = TRUE

estimate_nhb <- function(trips_df, trip_type, equiv = NULL, 
                         dependent_vars = NULL, boost = FALSE) {
  
  logsum_tbl <- read_csv("data/input/nhb/logsums.csv") %>%
    # select(TAZ, GeneralAccessibility_walk:EmploymentAccessibility_sov)
    select(TAZ, logsum = GeneralAccessibility_sov)
  
  add_y <- trips_df
  add_y$trip_type <- ifelse(add_y$trip_type == trip_type, "y", add_y$trip_type)
  tour_str = substr(trip_type, 1, 1)
  
  add_logsum <- add_y %>%
    left_join(logsum_tbl, by = c("a_taz" = "TAZ"))
  
  collapse_types <- add_logsum %>%
    mutate(trip_type_orig = trip_type)
  if (!is.null(equiv)) {
    for (i in 1:length(equiv)) {
      name <- names(equiv)[i]
      value <- equiv[[i]]
      collapse_types$trip_type <- ifelse(
        collapse_types$trip_type == name, value, collapse_types$trip_type
      )
    }
  }
  
  temp1 <- collapse_types %>%
    filter(substr(trip_type, 1, 1) %in% c(tour_str, "y")) %>%
    select(personid, tour_num, trip_type, trip_weight_combined, logsum) %>%
    group_by(personid, tour_num) %>%
    mutate(keep = ifelse(any(trip_type == "y"), 1, 0))
  
  temp2 <- temp1 %>%
    filter(keep == 0) %>%
    group_by(personid, tour_num) %>%
    slice(1) %>%
    mutate(
      trip_type = "y",
      trip_weight_combined = 0
    )
  
  est_tbl <- bind_rows(temp1, temp2) %>%
    select(-keep) %>%
    filter(
      trip_type == "y" | !grepl("_NH_", trip_type)
    ) %>%
    group_by(personid, tour_num, trip_type) %>%
    summarize(
      trips = sum(trip_weight_combined),
      logsum = mean(logsum, na.rm = TRUE)
    ) %>%
    pivot_wider(names_from = trip_type, values_from = trips) %>%
    relocate("y", .before = personid) %>%
    ungroup() %>%
    mutate(
      across(everything(), ~ifelse(is.na(.x), 0, .x)),
    ) %>%
    select(-personid, -tour_num)
  
  if (!is.null(dependent_vars)) {
    est_tbl <- est_tbl[, c("y", c("logsum", dependent_vars))]
  }
  
  model <- lm(y ~ . -logsum + 0, data = est_tbl)
  adj_r_sq <- summary(model)$adj.r.squared
  coeffs <- broom::tidy(model) %>%
    mutate(p.value = round(p.value, 5))
  
  add_orig_types <- coeffs %>%
    left_join(
      collapse_types %>%
        select(trip_type, trip_type_orig) %>%
        group_by(trip_type_orig) %>%
        slice(1),
      by = c("term" = "trip_type")
    ) %>%
    relocate(trip_type_orig, .before = term) %>%
    rename(trip_type = trip_type_orig, estimated_as = term)
  
  result <- list()
  result$r_sq <- round(adj_r_sq, 2)
  result$tbl <- add_orig_types
  return(result)
}