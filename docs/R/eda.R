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
      samples = map_dbl(data, function(df) nrow(df)),
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
      r_seniors = map_dbl(data, function(df) {
        s <- df %>%
          group_by(hhid) %>%
          summarize(
            trips = sum(trip_weight_combined) / first(hh_weight_combined),
            num_seniors = first(num_seniors)
          )
        my_cor(s, "trips", "num_seniors")
      }),
      r_kids = map_dbl(data, function(df) {
        s <- df %>%
          group_by(hhid) %>%
          summarize(
            trips = sum(trip_weight_combined) / first(hh_weight_combined),
            # child_present = first(child_present)
            num_children = first(num_children)
          )
        my_cor(s, "trips", "num_children")
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

#' Similar to eda() but analyzes from the perspective of the person

person_eda <- function(df, tour_type = "tour_type", homebased = "homebased",
                purpose = "purp_scheme", duration = "dur_scheme",
                person_df = per_add_flags, hh_df = hh_add_seniors) {
  
  # Avoid the complication of programming with dplyr by creating new columns
  df$tour_type <- df[[tour_type]]
  df$homebased <- df[[homebased]]
  df$purpose <- df[[purpose]]
  df$duration <- df[[duration]]
  
  count_trips <- df %>%
    filter(tour_type != "H") %>%
    unite(c(tour_type, homebased, purpose, duration), col = "trip_type") %>%
    group_by(personid, trip_type) %>%
    summarize(trip_weight = sum(trip_weight_combined, na.rm = TRUE))
  
  per_add_trips <- person_df %>%
    select(personid) %>%
    left_join(count_trips, by = "personid") %>%
    expand(personid, trip_type) %>%
    filter(!is.na(trip_type)) %>%
    left_join(count_trips, by = c("personid", "trip_type")) %>%
    mutate(trip_weight = replace_na(trip_weight, 0)) %>%
    left_join(person_df, by = "personid") %>%
    select(-hh_weight_combined) %>%
    left_join(hh_df, by = "hhid") %>%
    mutate(trip_weight = trip_weight / hh_weight_combined)
  
  # Perform the EDA
  eda <- per_add_trips %>%
    group_by(trip_type) %>%
    nest() %>%
    mutate(
      samples = map_dbl(data, function(df) {
        nrow(df %>% filter(trip_weight > 0))
      }),
      wTrips = map_dbl(data, function(df) {
        round(sum(df$trip_weight * df$hh_weight_combined, na.rm = TRUE), 0)
      }),
      r_othpers = map_dbl(data, function(df) {
        s <- df %>%
          group_by(personid) %>%
          mutate(hhsize = hhsize - 1) %>%
          summarize(
            trips = sum(trip_weight),
            hhsize = first(hhsize)
          )
        my_cor(s, "trips", "hhsize")
      }),
      r_is_worker = map_dbl(data, function(df) {
        s <- df %>%
          group_by(personid) %>%
          summarize(
            trips = sum(trip_weight),
            is_worker = first(is_worker)
          )
        my_cor(s, "trips", "is_worker")
      }),
      r_othworkers = map_dbl(data, function(df) {
        s <- df %>%
          group_by(personid) %>%
          mutate(num_workers = num_workers - is_senior) %>%
          summarize(
            trips = sum(trip_weight),
            num_workers = first(num_workers)
          )
        my_cor(s, "trips", "num_workers")
      }),
      r_is_senior = map_dbl(data, function(df) {
        s <- df %>%
          group_by(personid) %>%
          summarize(
            trips = sum(trip_weight),
            is_senior = first(is_senior)
          )
        my_cor(s, "trips", "is_senior")
      }),
      r_othseniors = map_dbl(data, function(df) {
        s <- df %>%
          group_by(personid) %>%
          mutate(num_seniors = num_seniors - is_senior) %>%
          summarize(
            trips = sum(trip_weight),
            num_seniors = first(num_seniors)
          )
        my_cor(s, "trips", "num_seniors")
      }),
      r_is_kid = map_dbl(data, function(df) {
        s <- df %>%
          group_by(personid) %>%
          summarize(
            trips = sum(trip_weight),
            is_child = first(is_child)
          )
        my_cor(s, "trips", "is_child")
      }),
      r_othkids = map_dbl(data, function(df) {
        s <- df %>%
          group_by(personid) %>%
          mutate(num_children = num_children - is_child) %>%
          summarize(
            trips = sum(trip_weight),
            num_children = first(num_children)
          )
        my_cor(s, "trips", "num_children")
      }),
      r_hhincome = map_dbl(data, function(df) {
        s <- df %>%
          group_by(personid) %>%
          summarize(
            trips = sum(trip_weight),
            hh_income_midpt = first(hh_income_midpt)
          )
        my_cor(s, "trips", "hh_income_midpt")
      }),
      r_hhveh = map_dbl(data, function(df) {
        s <- df %>%
          group_by(personid) %>%
          summarize(
            trips = sum(trip_weight),
            num_vehicles = first(num_vehicles)
          )
        my_cor(s, "trips", "num_vehicles")
      })
      # The other summaries from eda() would be the same
    ) %>%
    select(-data) %>%
    # filter(tour_type != "H") %>%
    select(trip_type, everything()) %>%
    separate(trip_type, c("tour_type", "homebased", "purpose", "duration")) %>%
    arrange(desc(tour_type), homebased, purpose, duration)
}