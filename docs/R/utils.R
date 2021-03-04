rmse <- function(obs, est) {
  sqrt(mean((est - obs) ^ 2))
}

prmse <- function(obs, est) {
  rmse <- sqrt(mean((est - obs) ^ 2))
  prmse <- rmse / mean(obs) * 100
  return(prmse)
}

mape <- function(obs, est) {
  mean(abs(obs - est))
}
