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
  
  # Perform the EDA
  eda <- df %>%
    group_by(tour_type, homebased, purpose, duration) %>%
    nest() %>%
    mutate(
      wTrips = map_dbl(
        data, function(df) round(sum(df$trip_weight_combined, na.rm = TRUE), 0)),
      r_size = map_dbl(data, function(df) {
        model <- lm(trip_weight_combined ~ hhsize, data = df)
        round(summary(model)$r.squared, 3)
      }),
      r_senior = map_dbl(data, function(df) {
        model <- lm(trip_weight_combined ~ senior_present, data = df)
        round(summary(model)$r.squared, 3)
      }),
      r_kid = map_dbl(data, function(df) {
        model <- lm(trip_weight_combined ~ child_present, data = df)
        round(summary(model)$r.squared, 3)
      }),
      r_income = map_dbl(data, function(df) {
        model <- lm(trip_weight_combined ~ hh_income_midpt, data = df)
        round(summary(model)$r.squared, 3)
      }),
      r_veh = map_dbl(data, function(df) {
        model <- lm(trip_weight_combined ~ num_vehicles, data = df)
        round(summary(model)$r.squared, 3)
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
        model <- lm(trip_weight_combined ~ d_emp, data = df)
        round(summary(model)$r.squared, 3)
      }),
      r_ret = map_dbl(data, function(df) {
        model <- lm(trip_weight_combined ~ d_ret, data = df)
        round(summary(model)$r.squared, 3)
      }),
      r_ind = map_dbl(data, function(df) {
        model <- lm(trip_weight_combined ~ d_ind, data = df)
        round(summary(model)$r.squared, 3)
      }),
      r_off = map_dbl(data, function(df) {
        model <- lm(trip_weight_combined ~ d_off, data = df)
        round(summary(model)$r.squared, 3)
      }),
      r_svh = map_dbl(data, function(df) {
        model <- lm(trip_weight_combined ~ d_svh, data = df)
        round(summary(model)$r.squared, 3)
      }),
      r_svl = map_dbl(data, function(df) {
        model <- lm(trip_weight_combined ~ d_svl, data = df)
        round(summary(model)$r.squared, 3)
      })
    ) %>%
    unnest(cols = c(tod_summary, mode_summary)) %>%
    mutate(across(pct_bike:pct_walk, ~ifelse(is.na(.x), 0, .x))) %>%
    select(-data) %>%
    filter(tour_type != "H") %>%
    arrange(tour_type, homebased, purpose, duration)
}
