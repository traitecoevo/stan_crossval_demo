
# Prevents under and overflow when calculating mean log likelihoods.
log_sum_exp <- function(x) {
  max(x) + log(sum(exp(x - max(x))))
}

# stan's chain merger
combine_stan_chains <- function(files) {
  rstan::sflist2stanfit(lapply(files, readRDS))
}

# sub function to compile chains for our workflow
compile_chains <- function(comparison) {
  if(!comparison %in% c("without_random_effects","with_random_effects")) {
    stop('comparison can only be one of the following: 
                      "without_random_effects","with_random_effects"')
  }
  tasks <- tasks_2_run(comparison)
  sets <- split(tasks,  list(tasks$comparison,tasks$kfold), sep='_', drop=TRUE)
  
  fits <- lapply(sets, function(s) combine_stan_chains(s[['filename']]))
  pars <- lapply(sets,  function(s) s[1, c("comparison","kfold")])
  
  list(model_info=pars, fits=fits)
}

# Compile chains for all models
compile_models <- function(comparison= c("without_random_effects","with_random_effects")) {
  if(length(comparison) == 1) {
    compile_chains(comparison)
  }
  else {
    sapply(comparison, function(x) compile_chains(x), simplify = FALSE)
  }
}
  

# Diagnostic function
diagnostics <- function(model) {
  fits <- model$fits
  info <- model$model_info
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
      kfold = as.integer(x$kfold))
  })))
  
  res <- cbind(out2,out1) %>%
    arrange(comparison, kfold)
  
  row.names(res) <- NULL
  return(res)
}

# Examine model diagnostics for all analysis
kfold_diagnostics <- function(model) {
  if(is.null(model$fits)) { #Check to see if object is multi model 
    out <- suppressWarnings(bind_rows(lapply(model, function(x) {
      diagnostics(x)})))
    row.names(out) <- NULL
  }
  else {
    out <- diagnostics(model)
  }
  return(out)
}

# sub function to extract log likelihood samples
loglik_samples <- function(model) {
  fits <- model$fits
  info <- plyr::ldply(model$model_info, .id='modelid')
  samples <- lapply(fits, function(x) 
    rstan::extract(x, pars = c('total_loglik_heldout')))
  
  res <- plyr::ldply(lapply(samples, function(x) {
    tidyr::gather(data.frame(x),'loglik','estimate')}), .id='modelid')
  
  left_join(info, res, 'modelid') %>%
    select(-modelid)
}

# Extract log likelihood samples for all models.
extract_loglik_samples <- function(model) {
  if(is.null(model$fits)) { #Check to see if object is multi model 
  samples <- lapply(model, loglik_samples)
  plyr::ldply(samples, .id='modelid') %>%
    select(-modelid)
  }
  else { 
    loglik_samples(model)
  }
}
# Summarise log likelihood samples
summarise_loglik_samples <- function(samples) {
  samples %>%
    group_by(comparison, kfold, loglik) %>%
    summarise(kfold_loglik = mean(log_sum_exp(estimate))) %>%
    ungroup() %>%
    group_by(comparison, loglik) %>%
    summarise(mean = mean(kfold_loglik),
              st_err = sd(kfold_loglik)/sqrt(n())) %>%
    mutate(ci = 1.96 * st_err,
           `2.5%` = mean - ci,
           `97.5%` = mean + ci) %>%
    ungroup()
}