
# Model without random effects

stan_model <- function() {
  list(
    pars = c("alpha","beta","sigma_obs","total_loglik_heldout"),
    model ="
    data {
      int<lower = 1> n_obs; 
      real ln_alf[n_obs];
      real ln_ht[n_obs];
      int<lower = 1> n_obs_heldout; 
      real ln_alf_heldout[n_obs_heldout];
      real ln_ht_heldout[n_obs_heldout];
    }

    parameters {
    #Estimating distances model
    real alpha;
    real beta;
    real<lower=0> sigma_obs;
  }
  model {
    real y_hat[n_obs];
    
    for (i in 1:n_obs) {
      y_hat[i] <- alpha + beta * ln_alf[i];
    }
    ln_ht ~ normal(y_hat, sigma_obs);
    
    # Priors
    alpha ~ normal(0,10);
    beta ~ normal(0,10);
    sigma_obs ~ cauchy(0,5);
  }
  generated quantities {
    real loglik_heldout;
    real total_loglik_heldout;
    real y_hat_heldout[n_obs_heldout];

    # initialize total_loglik_heldout
    total_loglik_heldout <- 0;
    
    for (i in 1:n_obs_heldout) {
      y_hat_heldout[i] <- alpha + beta * ln_alf_heldout[i];
      loglik_heldout <- normal_log(ln_ht_heldout[i], y_hat_heldout[i], sigma_obs);
      total_loglik_heldout <- total_loglik_heldout + loglik_heldout;
      # We are only monitoring the summed loglik here.
      # But above can easily be modified to give obervation log likelihood
      # However, if you are dealing with large datasets this will consume alot of memory.
    }
  }"
  )
}


# Model with random effects
stan_model_re <- function() {
  list(
    pars = c('alpha_mu','beta_mu','alpha_sigma','beta_sigma','sigma_obs','total_loglik_heldout'),
    model = "
    data {
      int<lower = 1> n_obs; 
      int<lower = 1> n_spp;
      int<lower = 1> spp[n_obs];
      real ln_alf[n_obs];
      real ln_ht[n_obs];
      int<lower = 1> n_obs_heldout; 
      int<lower = 1> n_spp_heldout;
      int<lower = 1> spp_heldout[n_obs_heldout];
      real ln_alf_heldout[n_obs_heldout];
      real ln_ht_heldout[n_obs_heldout];
    }

    parameters {
    #Estimating distances model
    real alpha[n_spp];
    real beta[n_spp];
    real alpha_mu;
    real<lower=0> alpha_sigma;
    real beta_mu;
    real<lower=0> beta_sigma;
    real<lower=0> sigma_obs;
  }
  model {
    real y_hat[n_obs];
    
    for (i in 1:n_obs) {
      y_hat[i] <- alpha[spp[i]] + beta[spp[i]] * ln_alf[i];
    }
    ln_ht ~ normal(y_hat, sigma_obs);
    
    # Priors
    alpha ~ normal(alpha_mu,alpha_sigma);
    beta ~ normal(beta_mu,beta_sigma);
    alpha_mu ~ normal(0,10);
    alpha_sigma ~ cauchy(0,5);
    beta_mu ~ normal(0, 10);
    beta_sigma ~ cauchy(0,5);
    sigma_obs ~ cauchy(0,5);
  }
  generated quantities {
    real loglik_heldout;
    real total_loglik_heldout;
    real y_hat_heldout[n_obs_heldout];

    # initialize total_loglik_heldout
    total_loglik_heldout <- 0;
    
    for (i in 1:n_obs_heldout) {
      y_hat_heldout[i] <- alpha[spp_heldout[i]] + beta[spp_heldout[i]] * ln_alf_heldout[i];
      loglik_heldout <- normal_log(ln_ht_heldout[i], y_hat_heldout[i], sigma_obs);
      total_loglik_heldout <- total_loglik_heldout + loglik_heldout;
      # We are only monitoring the summed loglik here.
      # But above can easily be modified to give obervation log likelihood
      # However, if you are dealing with large datasets this will consume alot of memory.
    }
  }"
  )
}