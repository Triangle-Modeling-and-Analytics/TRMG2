# trip_type <- "N_NH_OME_All_sov"
# trips_df <- trips
# boost = TRUE

estimate_nhb <- function(trips_df, trip_type, equiv = NULL, 
                         dependent_vars = NULL, boost = FALSE) {
  
  # Determine the correct logsum to use and create a table
  v <- str_split(trip_type, "_")[[1]]
  logsum_type <- ifelse(
    v[length(v)] %in% c("sov", "hov2", "hov3", "pay", "auto"), "nearby_sov", NA
  )
  logsum_type <- ifelse(
    v[length(v)] == "walkbike", "walk", logsum_type
  )
  logsum_type <- ifelse(
    v[length(v)] == "lb", "transit", logsum_type
  )
  logsum_tbl <- read_csv(
    "data/input/nhb/logsums.csv",
    col_types = cols(
      .default = col_double(),
      Type = col_character(),
      AreaType = col_character()
    )
  ) 
  logsum_tbl$logsum <- logsum_tbl[[paste0("access_", logsum_type)]]
  logsum_tbl <- logsum_tbl %>% select(TAZ, logsum)
  logsum_tbl <- logsum_tbl %>%
    mutate(logsum = pmax(.1, logsum))
  
  add_y <- trips_df
  add_y$trip_type <- ifelse(add_y$trip_type == trip_type, "y", add_y$trip_type)
  tour_str = substr(trip_type, 1, 1)
  
  add_logsum <- add_y %>%
    left_join(logsum_tbl, by = c("p_taz" = "TAZ"))
  
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

  combine_tbl <- bind_rows(temp1, temp2) %>%
    select(-keep) %>%
    filter(
      trip_type == "y" | !grepl("_NH_", trip_type)
    )
  
  avg_logsum <- combine_tbl %>%
    group_by(personid, tour_num) %>%
    summarize(logsum = mean(logsum, na.rm = TRUE))
  
  est_tbl <- combine_tbl %>%
    group_by(personid, tour_num, trip_type) %>%
    summarize(trips = sum(trip_weight_combined)) %>%
    left_join(avg_logsum, by = c("personid", "tour_num")) %>%
    pivot_wider(names_from = trip_type, values_from = trips) %>%
    relocate("y", .before = personid) %>%
    ungroup() %>%
    mutate(
      across(everything(), ~ifelse(is.na(.x), 0, .x)),
    )

  if (!is.null(dependent_vars)) {
    est_tbl <- est_tbl[, c("y", c("personid", "tour_num", "logsum", dependent_vars))]
  }
  
  # model <- lm(y ~ . - logsum + 0, data = est_tbl)
  model <- lm(y ~ . - personid - tour_num - logsum + 0, data = est_tbl)
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
    rename(estimated_as = term, term = trip_type_orig)
  
  result <- list()
  
  # Boosting
  if (boost) {
    resid_tbl <- est_tbl %>%
      mutate(
        ln_y = ifelse(log(y) < -1, -1, log(y)),
        y_hat = model$fitted.values,
        y_hat = pmax(0, y_hat),
        ln_y_hat = ifelse(log(y_hat) < -1, -1, log(y_hat)),
        diff = ln_y - ln_y_hat,
        ln_A = ifelse(log(logsum) < -1, -1, log(logsum))
      ) %>%
      rename(A = logsum) %>%
      # filter(!(y == 0 & y_hat == 0)) %>%
      # filter(y != 0) %>%
      select(y, y_hat, ln_y, ln_y_hat, diff, A, ln_A)
    boost_model <- lm(diff ~ ln_A, data = resid_tbl)
    gamma <- boost_model$coefficients[[2]]
    alpha <- exp(boost_model$coefficients[[1]])
    
    # Combined model
    cor_tbl <- resid_tbl %>%
      mutate(y_hat_boosted = y_hat * A ^ gamma * alpha) %>%
      select(y, y_hat, y_hat_boosted)
    alpha_scaled <- alpha * sum(cor_tbl$y_hat) / sum(cor_tbl$y_hat_boosted)
    cor_tbl <- resid_tbl %>%
      mutate(y_hat_boosted = y_hat * A ^ gamma * alpha_scaled) %>%
      select(y, y_hat, A, y_hat_boosted)
    adj_r_sq <- cor(cor_tbl[, c("y", "y_hat_boosted")])[1,2] ^ 2
    
    p_tbl <- est_tbl %>%
      select(logsum) %>%
      mutate(
        y = alpha_scaled * logsum ^ gamma,
        trip_type = trip_type
      )
    p <- ggplot(p_tbl) +
      geom_point(aes(x = logsum, y = y), color = "blue") +
      labs(
        title = "NHB Trip-Making and Accessibility",
        y = "Effect on NHB Trip Rate",
        x = "Nearby Accessibility"
      ) +
      theme(plot.title = element_text(hjust = 0.5))
    
    boost_coeffs <- broom::tidy(boost_model) %>%
      mutate(p.value = round(p.value, 5))
    boost_coeffs$term[1] <- "alpha"
    boost_coeffs$estimate[1] <- alpha_scaled
    boost_coeffs$term[2] <- "gamma"
    
    add_orig_types <- bind_rows(add_orig_types, boost_coeffs)
    
    result$p_tbl <- p_tbl
    result$p <- p
  }
  
  result$r_sq <- round(adj_r_sq, 2)
  result$tbl <- add_orig_types
  return(result)
}

# trip_type <- "N_NH_OME_All_sov"
# trips_df <- trips
# coeffs = model3$tbl


apply_nhb_zonal <- function(trips_df, trip_type, coeffs) {
  
  output <- list()
  
  # Determine the correct logsum to use and create a table
  v <- str_split(trip_type, "_")[[1]]
  logsum_type <- ifelse(
    v[length(v)] %in% c("sov", "hov2", "hov3", "pay", "auto"), "nearby_sov", NA
  )
  logsum_type <- ifelse(
    v[length(v)] == "walkbike", "walk", logsum_type
  )
  logsum_type <- ifelse(
    v[length(v)] == "lb", "transit", logsum_type
  )
  logsum_tbl <- read_csv(
    "data/input/nhb/logsums.csv",
    col_types = cols(
      .default = col_double(),
      Type = col_character(),
      AreaType = col_character()
    )
  ) 
  logsum_tbl$logsum <- logsum_tbl[[paste0("access_", logsum_type)]]
  logsum_tbl <- logsum_tbl %>% select(TAZ, logsum)
  logsum_tbl <- logsum_tbl %>%
    mutate(logsum = pmax(.1, logsum))
  
  # Aggregate trip ends
  hb_attrs <- trips_df %>%
    filter(homebased == "HB" & tour_type != "H") %>%
    group_by(a_taz, trip_type) %>%
    summarize(trips = sum(trip_weight_combined)) %>%
    pivot_wider(names_from = "trip_type", values_from = "trips")
  nh_prods <- trips_df %>%
    filter(homebased == "NH") %>%
    group_by(p_taz) %>%
    summarize(nh_prods = sum(trip_weight_combined))
  nh_attrs <- trips_df %>%
    filter(homebased == "NH") %>%
    group_by(a_taz) %>%
    summarize(nh_attrs = sum(trip_weight_combined))
  
  # Combine data frames
  combined <- logsum_tbl %>%
    left_join(nh_prods, by = c("TAZ" = "p_taz")) %>%
    left_join(nh_attrs, by = c("TAZ" = "a_taz")) %>%
    left_join(hb_attrs, by = c("TAZ" = "a_taz")) %>%
    mutate(
      # across(nh_prods:W_HB_EK12_All_bike, ~ifelse(is.na(.x), 0, .x))
      across(everything(), ~ifelse(is.na(.x), 0, .x))
    ) %>%
    mutate(nh_total = nh_prods + nh_attrs) %>%
    relocate(nh_total, .after = nh_attrs)
  
  # extract alpha/gamma if they exist
  alpha_exists <- any(coeffs$term == "alpha")
  if (alpha_exists) {
    alpha <- coeffs$estimate[which(coeffs$term == "alpha")]
    gamma <- coeffs$estimate[which(coeffs$term == "gamma")]
    remove_alpha <- coeffs %>%
      filter(!(term %in% c("alpha", "gamma")))
  } else {
    remove_alpha <- coeffs
  }
  
  # Apply regression model
  result <- combined
  result$y_hat <- 0
  for (i in 1:nrow(remove_alpha)) {
    term <- remove_alpha$term[[i]]
    coeff <- remove_alpha$estimate[[i]]
    
    result$y_hat <- result$y_hat + result[[term]] * coeff
  }
  result <- result %>%
    relocate(y_hat, .after = TAZ)
  output$tbl <- result
  output$r_sq <- cor(result$y_hat, result$nh_total) ^ 2
  output$prmse <- prmse(result$nh_total, result$y_hat)
  output$mape <- mape(result$nh_total, result$y_hat)
  
  # Apply boosted model
  if (alpha_exists) {
    result$y_hat_boost <- result$y_hat * (result$logsum ^ gamma * alpha)
    result <- result %>%
      relocate(y_hat_boost, .after = y_hat)
    output$tbl <- result
    output$r_sq <- cor(result$y_hat_boost, result$nh_total) ^ 2
    output$prmse <- prmse(result$nh_total, result$y_hat_boost)
    output$mape <- mape(result$nh_total, result$y_hat_boost)
  }
  
  return(output)
}
