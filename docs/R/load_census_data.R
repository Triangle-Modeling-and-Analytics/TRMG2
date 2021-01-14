# This function is not generalized, but will get the pertinent Census 
# data for the Triangle region.
#
# Returns a list of three simple feature shapes:
# acs_bg: acs block group info
# dec_bg: decennial block group info
# dec_block: decennial block info

load_census_data <- function(state = "NC", acs_year = 2018){
  
  library(tidycensus)
  library(tidyverse)
  library(sf)
  
  # read in the model study area
  tazs <- st_read("data/input/tazs/tazs 2020-12-08.shp")
  suppressWarnings(
    model_boundary <- tazs %>%
      mutate(temp = 1) %>%
      group_by(temp) %>%
      summarize(count = n()) %>%
      st_buffer(.0001)
  )
  counties <- unique(tazs$COUNTY)

  
  bg_file <- "data/input/census_data/shapes/acs_blockgroups.shp"
  if (!file.exists(bg_file)){
    # Read table of census variables and their names/geographies
    # https://api.census.gov/data/2018/acs/acs5/variables.html
    acs_vars <- read_csv("data/input/census_data/acs_bg_variables.csv")
    # Get census data from API
    acs_raw <- get_acs(
      geography = "block group", state = state, year = acs_year,
      county = counties, variables = acs_vars$variable, geometry = TRUE
    )
    
    # Reduce the shapefile to only those blockgroups that touch the model
    # boundary. Using st_intersection alone will modify/crop the edge block
    # groups, which is not desired here.
    model_boundary <- st_transform(model_boundary, st_crs(acs_raw))
    intersect_bg <- acs_raw[st_intersects(acs_raw, model_boundary, sparse = FALSE), ]
    
    # Join variable names, sum any repeats, and then spread. Vehicle variable
    # names are repeated because the household numbers come from a table that
    # lists them by owner/renter.
    acs_tbl <- intersect_bg %>%
      as.data.frame() %>%
      left_join(acs_vars, by = "variable") %>%
      mutate(
        name = case_when(
          name %in% c(
            "m_u5", "m_u9", "m_u14", "m_u17",
            "f_u5", "f_u9", "f_u14", "f_u17"
          ) ~ "age_child",
          name %in% c(
            "m_u66", "m_u69", "m_u74", "m_u79", "m_u84", "m_o85",
            "f_u66", "f_u69", "f_u74", "f_u79", "f_u84", "f_o85"
          ) ~ "age_senior",
          grepl("f_", name) ~ "age_other",
          grepl("m_", name) ~ "age_other",
          TRUE ~ name
        )
      ) %>%
      group_by(GEOID, name) %>%
      summarize(estimate = sum(estimate)) %>%
      spread(key = name, value = estimate) %>%
      # After review, the total vehicle estimates from table B25046 are missing
      # in some zones. Where it is missing, use a simple equation to calculate.
      mutate(
        veh_tot_temp = 
          veh0 * 0 + 
          veh1 * 1 + 
          veh2 * 2 + 
          veh3 * 3 + 
          veh4 * 4 + 
          veh5 * 5,
        veh_tot = ifelse(is.na(veh_tot), veh_tot_temp, veh_tot)
      ) %>%
      select(-veh_tot_temp)
    
    acs_bg <- intersect_bg %>%
      group_by(GEOID) %>%
      slice(1) %>%
      ungroup() %>%
      select(GEOID) %>%
      as.data.frame() %>%
      left_join(acs_tbl, by = "GEOID") %>%
      st_as_sf() %>%
      st_make_valid() %>%
      mutate(County = substr(GEOID, 1, 5)) %>%
      relocate(County, .after = GEOID)
    
    st_write(acs_bg, bg_file)
  } else {
    acs_bg <- st_read(bg_file, quiet = TRUE)
  }
  
  # ACS tracts
  acs_file <- "data/input/census_data/shapes/acs_tracts.shp"
  if (!file.exists(acs_file)){
    # Read table of census variables and their names/geographies
    acs_vars <- read_csv("data/input/census_data/acs_tract_variables.csv")
    # Get census data from API
    acs_raw <- get_acs(
      geography = "tract", state = state, year = acs_year,
      county = counties, variables = acs_vars$variable, geometry = TRUE
    )
    
    # Reduce the shapefile to only those tracts that touch the model
    # boundary. st_intersection alone will modify/crop the edge block groups, 
    # which is not desired here.
    model_boundary <- st_transform(model_boundary, st_crs(acs_raw))
    intersect_tract <- acs_raw[st_intersects(acs_raw, model_boundary, sparse = FALSE), ]
    
    # Join variable names, sum any repeats, and then spread
    acs_tbl <- intersect_tract %>%
      as.data.frame() %>%
      left_join(acs_vars, by = "variable") %>%
      group_by(GEOID, name) %>%
      summarize(estimate = sum(estimate)) %>%
      spread(key = name, value = estimate)
    acs_tract <- intersect_tract %>%
      group_by(GEOID) %>%
      slice(1) %>%
      ungroup() %>%
      select(GEOID) %>%
      as.data.frame() %>%
      left_join(acs_tbl, by = "GEOID") %>%
      st_as_sf() %>%
      st_make_valid() %>%
      mutate(County = substr(GEOID, 1, 5)) %>%
      relocate(County, .after = GEOID)
    
    st_write(acs_tract, acs_file)
  } else {
    acs_tract <- st_read(acs_file, quiet = TRUE)
  }
  
  # same thing for decennial block group variables
  dec_file <- "data/input/census_data/shapes/dec_blockgroups.shp"
  if (!file.exists(dec_file)){
    dec_vars <- read_csv("data/input/census_data/dec_bg_variables.csv")
    decennial_raw <- get_decennial(
      year = 2010, geography = "block group", state = state,
      county = counties, variables = dec_vars$variable, geometry = TRUE
    )
    model_boundary <- st_transform(model_boundary, st_crs(decennial_raw))
    decennial_shp <- decennial_raw[
      st_intersects(decennial_raw, model_boundary, sparse = FALSE), 
      ]
    decennial_tbl <- decennial_shp %>%
      as.data.frame() %>%
      left_join(dec_vars, by = "variable") %>%
      select(-variable, -NAME) %>%
      spread(key = name, value = value)
    decennial_shp <- st_as_sf(decennial_tbl) %>%
      st_make_valid()
    
    st_write(decennial_shp, dec_file)
  } else {
    decennial_shp <- st_read(dec_file, quiet = TRUE)
  }
  
  # The decennial block file below is not needed.
  
  # dec_block_file <- "data/input/census_data/shapes/dec_blocks.shp"
  # if (!file.exists(dec_block_file)){
  #   block_vars <- data_frame(
  #     variable = c("H003002", "P016001", "P042001"),
  #     name = c("hh", "hh_pop", "gq_pop")
  #   )
  #   dec_raw <- get_decennial(
  #     year = 2010, geography = "block", state = state,
  #     county = counties, variables = block_vars$variable, geometry = TRUE
  #   )
  #   model_boundary <- st_transform(model_boundary, st_crs(dec_raw))
  #   dec_blocks <- dec_raw[st_intersects(dec_raw, model_boundary, sparse = FALSE), ]
  #   block_tbl <- dec_blocks %>%
  #     as.data.frame() %>%
  #     left_join(block_vars, by = "variable") %>%
  #     select(-variable, -NAME) %>%
  #     spread(key = name, value = value)
  #   dec_blocks <- st_as_sf(block_tbl) %>%
  #     st_make_valid()
  #   
  #   st_write(dec_blocks, dec_block_file)
  # } else {
  #   dec_blocks <- st_read(dec_block_file, quiet = TRUE)
  # }
  
  result <- list()
  result$acs_bg <- acs_bg
  result$acs_tract <- acs_tract
  result$dec_bg <- decennial_shp
  # result$dec_block <- dec_blocks
  return(result)
}