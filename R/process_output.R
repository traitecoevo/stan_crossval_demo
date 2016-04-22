
# Prevents under and overflow when calculating mean log likelihoods.
log_sum_exp <- function(x) {
  max(x) + log(sum(exp(x - max(x))))
}

# Merge chains related to a given model/kfold combination
combine_stan_chains <- function(files) {
  rstan::sflist2stanfit(lapply(files, readRDS))
}

# Compile all models related to a given analyses
compile_models <- function(comparison) {
  if(!comparison %in% c("without_random_effects","with_random_effects")) {
    stop('comparison can only be one of the following: 
                      "without_random_effects","with_random_effects"')
  }
  tasks <- tasks_2_run(comparison)
  sets <- split(tasks,  list(tasks$comparison,tasks$model,tasks$growth_measure,tasks$rho_combo,tasks$kfold), sep='_', drop=TRUE)
  
  fits <- lapply(sets, function(s) combine_stan_chains(s[['filename']]))
  pars <- lapply(sets,  function(s) s[1, c("comparison","model","growth_measure","rho_combo","kfold")])
  
  list(model_info=pars, fits=fits)
}

# Compile multiple analyses at once
compile_multiple_comparisons <- function(comparison) {
  sapply(comparison, function(x) compile_models(x), simplify = FALSE)
}

# Examine model diagnostics for single comparison
kfold_diagnostics <- function(comparison) {
  fits <- comparison$fits
  info <- comparison$model_info
  out1 <- bind_rows(lapply(fits, function(x) {
    summary_model <- summary(x)$summary
    sampler_params <- get_sampler_params(x, inc_warmup=FALSE)
    data.frame(
      min_n_eff = min(summary_model[, 'n_eff']),
      max_rhat = max(summary_model[, 'Rhat']),
      n_bad_rhat = length(which(summary_model[, 'Rhat'] > 1.1)),
      n_divergent = sum(sapply(sampler_params, function(y) y[,'n_divergent__'])),
      max_treedepth = max(sapply(sampler_params, function(y) y[,'treedepth__'])))
  }))
  
  out2 <- suppressWarnings(bind_rows(lapply(info, function(x) {
    data.frame(
      comparison = x$comparison,
      model = x$model,
      growth_measure = x$growth_measure,
      rho_combo = x$rho_combo,
      kfold = as.integer(x$kfold))
  })))
  
  res <- cbind(out2,out1) %>%
    arrange(comparison, model, growth_measure, rho_combo, kfold)
  
  row.names(res) <- NULL
  return(res)
}

# Examine model diagnostics for multiple analysis
multi_analysis_kfold_diagnostics <- function(list_of_analyses) {
  out <- suppressWarnings(bind_rows(lapply(list_of_analyses, function(x) {
    kfold_model_diagnostics(x)})))
  row.names(out) <- NULL
  return(out)
}

# Extract Log Loss samples for single comparison
extract_loglik_samples <- function(comparison) {
  fits <- comparison$fits
  info <- plyr::ldply(comparison$model_info, .id='modelid')
  samples <- lapply(fits, function(x) 
    rstan::extract(x, pars = c('loglik_heldout')))
  
  res <- plyr::ldply(lapply(samples, function(x) {
    tidyr::gather(data.frame(x),'loglik','estimate')}), .id='modelid')
  
  left_join(info, res, 'modelid') %>%
    select(-modelid)
}

# Extract log likelihood samples for multiple analyses.
extract_multi_comparison_loglik_samples <- function(list_of_comparisons){
  samples <- lapply(list_of_comparisons, extract_loglik_samples)
  plyr::ldply(samples, .id='modelid') %>%
    select(-modelid)
}
# Summarise log likelihood samples
summarise_loglik_samples <- function(samples) {
  samples %>%
    group_by(comparison, model, growth_measure, rho_combo, kfold, logloss) %>%
    summarise(kfold_logloss = mean(log_sum_exp(estimate))) %>%
    ungroup() %>%
    group_by(comparison, model, growth_measure, rho_combo, logloss) %>%
    summarise(mean = mean(kfold_logloss),
              st_err = sd(kfold_logloss)/sqrt(n())) %>%
    mutate(ci = 1.96 * st_err,
           `2.5%` = mean - ci,
           `97.5%` = mean + ci) %>%
    ungroup()
}

#
get_times <- function(comparison) {
   fits <- comparison$fits
  info <- plyr::ldply(comparison$model_info, .id='modelid')
  times <- lapply(fits, function(x) 
    rstan::get_elapsed_time(x))
  
  res <- plyr::ldply(lapply(times, function(x) {
    tidyr::gather(data.frame(x),'warmup','sample')}), .id='modelid')
  
  left_join(info, res, 'modelid') %>%
    select(-modelid) %>%
    mutate(total_hours = ((warmup + sample)/3600))
}


summarise_times <- function(times) {
  res <- times %>%
    group_by(comparison, model, growth_measure, rho_combo) %>%
    summarise(mn = median(total_hours))
  return(res)
}
