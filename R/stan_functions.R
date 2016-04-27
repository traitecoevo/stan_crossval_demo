# This function builds a dataframe with all the comparisons needed to be run.
# We've set 10-fold by default to match how we've split the data.
tasks_2_run <- function(comparison, n_chains=3, iter=2000, path='.') {
  n_kfolds = 10
  ret <- expand.grid(
   comparison = comparison,
   iter=iter,
   chain=seq_len(n_chains),
   kfold=seq_len(n_kfolds),
   stringsAsFactors=FALSE) %>%
    arrange(comparison, kfold, chain)

  ret$modelid <- rep(1:nrow(unique(ret[,c('comparison','kfold')])),each = n_chains)
  ret <- ret %>%
    group_by(comparison) %>%
  mutate(jobid = seq_len(n()),
   filename = sprintf("%s/results/chain_fits/%s/kfold%d_chain%d.rds", path, comparison,kfold,jobid),
   fold_data = sprintf("%s/precompile/kfold_data/data_%s.rds",path, kfold))
  return(ret)
}



# Converts dataframe to list
df_to_list <- function(x) {
  attr(x, "out.attrs") <- NULL # expand.grid leaves this behind.
  unname(lapply(split(x, seq_len(nrow(x))), as.list))
}

# Compiles models and then saves outputs to specified directory
model_compiler <- function(task) {
  data <- readRDS(task$fold_data)
  dir.create(dirname(task$filename), FALSE, TRUE)
  comparison <- task$comparison

  if(comparison == "without_random_effects") {
    model <- stan_model()
  }

  if (comparison == "with_random_effects") {
    model <- stan_model_re()
  }
  
  filename <- precompile(task)
  message("Loading precompiled model from ", filename)
  model$fit <- readRDS(filename)
  
  ## Actually run the model
  res <- run_single_stan_chain(model, data,
   chain_id=task$chain,
   iter=task$iter)
  ## dump into a file.
  saveRDS(res, task$filename)
  task$filename
}

# Runs single chain
run_single_stan_chain <- function(model, data, chain_id, iter=2000,
  sample_file=NA, diagnostic_file=NA) {
  data_for_stan <- prep_data_for_stan(data)
  stan(model_code = model$model,
   fit = model$fit,
   data = data_for_stan,
   pars = model$pars,
   iter = iter,
   chains=1,
   chain_id=chain_id,
   control=list(adapt_delta=0.9,stepsize=0.01, max_treedepth =15))
}

# Prepares data for models clusterous jobs
prep_data_for_stan <- function(data) {
  ln_ht <- log(data$train$h.t)
  ln_alf <- log(data$train$a.lf)
  ln_ht_heldout <- log(data$heldout$h.t)
  ln_alf_heldout <- log(data$heldout$a.lf)
  
  list(
    n_obs = nrow(data$train),
    n_site = max(data$train$site_id),
    n_spp = max(data$train$sp_id),
    site = data$train$site_id,
    spp = data$train$sp_id,
    ln_alf = ln_alf,
    ln_ht = ln_ht,
    n_obs_heldout = nrow(data$heldout),
    n_site_heldout = max(data$heldout$site_id),
    n_spp_heldout = max(data$heldout$sp_id),
    site_heldout = data$heldout$site_id,
    spp_heldout = data$heldout$sp_id,
    ln_alf_heldout = ln_alf_heldout,
    ln_ht_heldout = ln_ht_heldout
    )
}

# Precompiles model for clustereous
precompile <- function(task) {
  path <- precompile_model_path()
  comparison <- task$comparison
  # Assemble stan model
 if(comparison == "without_random_effects") {
    model <- stan_model()
  }

  if (comparison == "with_random_effects") {
    model <- stan_model_re()
  }
  sig <- digest::digest(model)
  fmt <- "%s/%s.%s"
  dir.create(path, FALSE, TRUE)
  filename_stan <- sprintf(fmt, path, sig, "stan")
  filename_rds  <- sprintf(fmt, path, sig, "rds")
  if (!file.exists(filename_rds)) {
    message("Compiling model: ", sig)
    writeLines(model$model, filename_stan)
    res <- stan(filename_stan,iter = 0L)
    message("Ignore the previous error, everything is OK")
    saveRDS(res, filename_rds)
    message("Finished model: ", sig)
  }
  filename_rds
}

#THIS ISN'T ELEGANT BUT IT WORKS
precompile_all <- function() {
  # without random effect models
  stage1 <- tasks_2_run(comparison = 'without_random_effects',iter = 10)
  vapply(df_to_list(stage1), precompile, character(1))
  
  #with random effect models
  stage2 <- tasks_2_run(comparison = 'with_random_effects',iter = 10)
  vapply(df_to_list(stage2), precompile, character(1))
}

## Wrapper around platform information that will try to determine if
## we're in a container or not.  This means that multiple compiled
## copies of the model can peacefully coexist.
platform <- function() {
  name <- tolower(Sys.info()[["sysname"]])
  if (name == "linux") {
    tmp <- strsplit(readLines("/proc/self/cgroup"), ":", fixed=TRUE)
    if (any(grepl("docker", vapply(tmp, "[[", character(1), 3L)))) {
      name <- "docker"
    }
  }
  name
}

precompile_model_path <- function(name=platform()) {
  file.path("precompile/precompiled_models/", name)
}

precompile_docker <- function(docker_image) {
  if (FALSE) {
    ## Little trick to depend on the appropriate functions (this will
    ## be picked up by remake's dependency detection, but never run).
    precompile_all()
  }
  x<- 3
  unlink(precompile_model_path(), recursive=TRUE)
  cmd <- '"remake::dump_environment(verbose=FALSE, allow_missing_packages=TRUE); precompile_all()"'
  dockertest::launch(name=docker_image,
   filename="docker/dockertest.yml",
   args=c("r", "-e", cmd))
}