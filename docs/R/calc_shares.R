#' Calculate smooth mean data.
#' 
#' 
#' 
#' @param 
# calc_mean_share <- function(df_table, avg, group, bin_width = 0.2){
#   
#   df <- df_table %>%
#     mutate_("group" = group, "avg" = avg ) %>%
#     
#     # break averages into steps
#     mutate(bin = round(avg / bin_width) * bin_width) %>%
#     
#     # calculate average share at each point %>%
#     group_by(bin, group) %>%
#     summarise(share = mean(share))
#     
#   return(df)
# } 
calc_mean_share <- function(df_table, avg, group, bin_width = 0.2){
  
  df <- df_table %>%
    mutate(group = !!as.name(group), avg = !!as.name(avg)) %>%
    
    # break averages into steps
    mutate(bin = round(avg / bin_width) * bin_width) %>%
    
    # calculate average share at each point %>%
    group_by(bin, group) %>%
    summarise(share = mean(share))
  
  return(df)
} 
 


fit_models <- function(df_table, avg, group, x, degree = 9){
  
  df_table$group <- df_table[[group]]
  df_table$avg <- df_table[[avg]]
  
  models <- df_table %>% 
    group_by(group) %>% 
    do(
      poly3 = lm(share ~ poly(avg, degree = degree, raw = TRUE), 
                 data = .)
    ) 
  
  # make lookup table
  a <- do.call( rbind,  
    lapply(models$poly3, function(m)   
      predict.lm(m, newdata = data.frame(avg = x) ) ) 
    )
  
  # name columns and rows
  rownames(a) <- names(table(df_table$group))
  colnames(a) <- x
  
  # must be between 0 and 1
  a <- ifelse(a < 0, 0, a)
  a <- ifelse(a > 1, 1, a)
  
  # first row must be uniform
  # a[,1] <- c(1, rep(0, nrow(a) - 1))

  # round
  a <- round(a, digits = 4)
  
  as.data.frame(t(a)) %>% as_tibble() %>%
    mutate(avg = as.numeric(colnames(a))) %>%
    gather(group, share, -avg)
  
}
  
smooth_shares <- function(df, x, y, group, lambda = 0.8) {
  
  
  smooth <- df %>%
    mutate_("x" = x, "y" = y, "group" = group) %>%
    group_by(group) %>%
    do(smooth = smooth.spline(.$x, .$y, spar = lambda))
  
  smoothdf <- lapply(smooth$smooth, 
                     function(sx) data_frame(avg = sx$x, share = sx$y))
  
  # label the dfs, bind, and return
  for(i in 1:length(smoothdf)){
    smoothdf[[i]]$group = smooth$group[i] 
  }
  smoothdf <- rbind_all(smoothdf)
  
}