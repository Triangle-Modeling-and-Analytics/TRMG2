#' This functions performs a large number of tests and summaries
#' of the survey data.
#' 
#' @param df The data.frame to process.
#' @param tour_type Grouping column for tour type.
#' @param homebased Grouping column for HB/NHB.
#' @param purpose Grouping column for activity purpose.
#' @param duration Grouping column for activity duration (e.g. "long"/"short")
#' 
#' @return A data frame with summaries and model coefficients for each market
#'   segment. Market segments defined by the four grouping column names.

eda <- function(df, tour_type = "tour_type", homebased = "homebased",
                purpose = "purp_scheme", duration = "dur_scheme") {
  
  # Avoid the complication of programming with dplyr by creating new columns
  df$tour_type <- df[[tour_type]]
  df$homebased <- df[[homebased]]
  df$purpose <- df[[purpose]]
  df$duration <- df[[duration]]
  
  df <- df %>%
    filter(tour_type != "H")
  
  # Perform the EDA
  eda <- df %>%
    group_by(tour_type, homebased, purpose, duration) %>%
    nest() %>%
    mutate(
      wTrips = map_dbl(
        data, function(df) round(sum(df$trip_weight_combined, na.rm = TRUE), 0)),
      r_size = map_dbl(data, function(df) {
        s <- df %>%
          group_by(hhid) %>%
          summarize(
            trips = sum(trip_weight_combined) / first(hh_weight_combined),
            hhsize = first(hhsize)
          )
        my_cor(s, "trips", "hhsize")
      }),
      r_senior = map_dbl(data, function(df) {
        s <- df %>%
          group_by(hhid) %>%
          summarize(
            trips = sum(trip_weight_combined) / first(hh_weight_combined),
            senior_present = first(senior_present)
          )
        my_cor(s, "trips", "senior_present")
      }),
      r_kid = map_dbl(data, function(df) {
        s <- df %>%
          group_by(hhid) %>%
          summarize(
            trips = sum(trip_weight_combined) / first(hh_weight_combined),
            child_present = first(child_present)
          )
        my_cor(s, "trips", "child_present")
      }),
      r_income = map_dbl(data, function(df) {
        s <- df %>%
          group_by(hhid) %>%
          summarize(
            trips = sum(trip_weight_combined) / first(hh_weight_combined),
            hh_income_midpt = first(hh_income_midpt)
          )
        my_cor(s, "trips", "hh_income_midpt")
      }),
      r_veh = map_dbl(data, function(df) {
        s <- df %>%
          group_by(hhid) %>%
          summarize(
            trips = sum(trip_weight_combined) / first(hh_weight_combined),
            num_vehicles = first(num_vehicles)
          )
        my_cor(s, "trips", "num_vehicles")
      }),
      tod_summary = map(data, function(df) {
        df %>%
          group_by(tod) %>%
          summarize(total = sum(trip_weight_combined, na.rm = TRUE)) %>%
          mutate(
            pct = round(total / sum(total) * 100, 1),
            tod = paste0("pct_", tod)
          ) %>%
          select(-total) %>%
          pivot_wider(names_from = "tod", values_from = "pct")
      }),
      mode_summary = map(data, function(df) {
        df %>%
          group_by(mode_simple2) %>%
          summarize(total = sum(trip_weight_combined, na.rm = TRUE)) %>%
          mutate(
            pct = round(total / sum(total) * 100, 1),
            mode_simple2 = paste0("pct_", mode_simple2)
          ) %>%
          select(-total) %>%
          pivot_wider(names_from = "mode_simple2", values_from = "pct")
      }),
      wAvgTrpLen = map_dbl(data, function(df) {
        round(weighted.mean(
          df$skim_length, df$trip_weight_combined, na.rm = TRUE), 2)
      }),
      r_emp = map_dbl(data, function(df) {
        s <- df %>%
          filter(!is.na(a_taz)) %>%
          group_by(a_taz) %>%
          summarize(
            trips = sum(trip_weight_combined),
            a_emp = first(a_emp)
          )
        my_cor(s, "trips", "a_emp")
      }),
      r_ret = map_dbl(data, function(df) {
        s <- df %>%
          filter(!is.na(a_taz)) %>%
          group_by(a_taz) %>%
          summarize(
            trips = sum(trip_weight_combined),
            a_ret = first(a_ret)
          )
        my_cor(s, "trips", "a_ret")
      }),
      r_ind = map_dbl(data, function(df) {
        s <- df %>%
          filter(!is.na(a_taz)) %>%
          group_by(a_taz) %>%
          summarize(
            trips = sum(trip_weight_combined),
            a_ind = first(a_ind)
          )
        my_cor(s, "trips", "a_ind")
      }),
      r_off = map_dbl(data, function(df) {
        s <- df %>%
          filter(!is.na(a_taz)) %>%
          group_by(a_taz) %>%
          summarize(
            trips = sum(trip_weight_combined),
            a_off = first(a_off)
          )
        my_cor(s, "trips", "a_off")
      }),
      r_svh = map_dbl(data, function(df) {
        s <- df %>%
          filter(!is.na(a_taz)) %>%
          group_by(a_taz) %>%
          summarize(
            trips = sum(trip_weight_combined),
            a_svh = first(a_svh)
          )
        my_cor(s, "trips", "a_svh")
      }),
      r_svl = map_dbl(data, function(df) {
        s <- df %>%
          filter(!is.na(a_taz)) %>%
          group_by(a_taz) %>%
          summarize(
            trips = sum(trip_weight_combined),
            a_svl = first(a_svl)
          )
        my_cor(s, "trips", "a_svl")
      })
    ) %>%
    unnest(cols = c(tod_summary, mode_summary)) %>%
    mutate(across(pct_bike:pct_walk, ~ifelse(is.na(.x), 0, .x))) %>%
    select(-data) %>%
    filter(tour_type != "H") %>%
    select(tour_type, homebased, purpose, duration, everything()) %>%
    arrange(desc(tour_type), homebased, purpose, duration)
}

my_cor <- function(df, c1, c2) {
  value <- cor(df[[c1]], df[[c2]])
  round(value, 3)
}