create_obs_matrices <- function(df) {
  dk <- connect()
  
  for (i in 1:nrow(df)) {
    tod <- df$board_time[i]
    access <- df$access_mode[i]
    mode <- df$mode[i]
    sub_df <- df$data[[i]] %>%
      select(orig_taz, dest_taz, weight)
    
    view <- df_to_view(sub_df)
    file_name <- paste0("obs_", tod, "_", access, "_", mode, ".mtx")
    file_name <- paste0(normalizePath("data/output/obs_processing"), "\\", file_name)
    mtx <- dk$CreateMatrixFromView(
      paste(tod, access, mode),
      paste0(view, "|"),
      "orig_taz",
      "dest_taz",
      list("weight"),
      list("File Name" = file_name)
    )
    dk$CloseView(view)
  }
  
  disconnect()
}