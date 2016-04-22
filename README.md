# How to run cross-validation in stan efficiently using your local computer & docker.

Here we provide an example of how to run 10-fold cross-validation in stan by using `docker`, `remake` and `rrqueue`.

## First clone this repository
Downloading a zip directly from github or if you have `git` installed via the terminal by first navigating to the path you wish for the repository to be saved and then running:

```
git clone git@github.com:jscamac/rstan_kfold_cluster_example.git
```


### Install remake & dockertest
[remake](https://github.com/richfitz/remake) is a package that allows us to use a make-like workflow in R by specifying a series of declarative actions. In essence, this package tells R what order things should be run in to ensure all dependencies are met. 

[dockertest](https://github.com/traitecoevo/dockertest) auto generates the Dockerfile; the main configuration file is `docker/dockertest.yml`, which is declarative rather than a list of instructions.

Both packages are not currently on CRAN but can be installed using `devtools`. 
Assuming devtools is already installed, the running the following in R will install these packages, their dependencies and any other needed to run these analyses.

```
devtools::install_github("richfitz/remake")
install.packages(c("R6", "yaml", "digest", "crayon", "optparse"))
devtools::install_github("richfitz/storr")
remake::install_missing_packages()
```

NOTE: if `devtools` is not installed it can be by running `install.packages("devtools")`.


### Process data ready for analysis
Now we need to prepare, download and process the data for subsequent use with models. We've automated this using the package `remake` and its declaration file `remake.yml`. 

Ensuring you are within `stan_crossval_demo` you can enter R and run the following:

```
R # enters R
remake::make() # runs remake
```

### Install docker

Docker is a program that allows users to makes virtual machines (called containers) that contains all the software needed to run a program or analysis. As such it is a tool that can be used to guarantee some software will always run the same way, regardless of the environment it is running in. Instructions on how to install this can be found [here](https://docs.docker.com)

### Creating a docker container

Once docker is installed we can build a docker container (a virtual machine). In our case, because we want to compile rstan models we require a container with sufficient amount of memory. 
Below we quit out of R and build a docker container with 3 GB of ram and 3 CPUs in the terminal using the Docker command `docker-machine`. We call this container  `mem3GB`

```
q("no") # quits R
docker-machine create --virtualbox-memory "3000" --driver virtualbox --virtualbox-cpu-count 3 mem3GB

```
(`--virtualbox-memory "3000"` sets how much virtual memory is available to the virtual machine.
 `----virtualbox-cpu-count 3` sets the number of CPUs you wish to use from your local machine)


### Downloading or building a docker image for your container
Next we wish to add a Ubuntu operating system, R and all dependent packages to the docker container. Since building such an image can take some time, we've already done the hard work for you such that you can simply download the image from the terminal using:

```
docker pull traitecoevo/stan_crossval_demo:latest
```

However, if you've added packages to `remake.yml` or to `dockertest.yml` you are best to rebuild the image in R by ensuring your terminal is within `stan_crossval_demo and running:
```
R # enters R
dockertest::build(machine = "mem3GB")
```
This will open R and connect you to the docker container `mem3B`.


### Precompile stan models

If you have several different models to run, it is best to precompile them for use with docker prior to actually sampling the models. This can be done in R (assuming you are within `stan_crossval_demo`):

```
remake::make('models_precompiled_docker')
```

### Setting up our master
Now we need to set up a master container that will act as a database that receives results as they complete.
For this container we use a database software called `redis`. We can install this directly from dockerhub by quitting R and running the following in a terminal:

```
q("no") # quits R
eval "$(docker-machine env mem3GB)"
docker run --name stan_crossval_demo_redis -d redis
```

**Note** if you have previously started redis, you'll get an error with the previous command that looks like:
```
Error response from daemon: Conflict. The name "stan_crossval_demo_redis" is already in use by container 0e246cf9734d. You have to delete (or rename) that container to be able to reuse that name.
```
and will need to do the following:
```
eval "$(docker-machine env mem3GB)"
docker stop stan_crossval_demo_redis
docker rm stan_crossval_demo_redis
docker run --name stan_crossval_demo_redis -d redis
```

### Setting up controller
Next we set up a controller from which we can create and queue jobs from. We do using the a terminal window in the parent directory of the project and running:

```
eval "$(docker-machine env mem3GB)"
docker run --rm --link stan_crossval_demo_redis:redis -v ${PWD}:/home/data -it traitecoevo/stan_crossval_demo:latest R
```
This will load R in mem6GB and allow you to load `rrqueue`, state what R packages you require and what source code needed to run the jobs. For example:

```
library(rrqueue)
packages <- c("rstan","dplyr")
sources <- c("R/model.R",
             "R/stan_functions.R")

#Connect the controller container to the redis container.
con <- queue("rrq", redis_host="redis", packages=packages, sources=sources)

# Dataframe of jobs
tasks <- tasks_2_run(comparison=c("without_random_effects","with_random_effects"))

# Submit jobs
res <- enqueue_bulk(tasks, model_compiler, con, progress_bar = TRUE)
```
When the jobs are submitted a progress bar will appear. At this stage there should be no progress as we haven't launched any workers to do the jobs.

### Launch workers to run the analysis

Lastly, we create workers that ask for, and then undertake, jobs from the controller. Because the controller is still running, you'll need to open **new** terminal tabs (as many as the number of CPU's you've allocated to your docker container `mem6GB`) in the parent directory.

Then you run the following for each terminal:
```
eval "$(docker-machine env mem3GB)"
docker run --rm --link stan_crossval_demo_redis:redis -v ${PWD}:/home/data -t traitecoevo/stan_crossval_demo:latest rrqueue_worker --redis-host redis rrq
```

This will launch workers that will begin to run through your jobs. The progress of these jobs can be seen from the controller terminal. Also as jobs complete they will automatically be exported to your parent directory under `results`.

### Combining chains for each model
Once all jobs are complete, you will want to examine model diagnostics and posteriors. To do this we need to combine all the chains associated with a given model.

We have developed some R functions to help with this. Open R (or Rstudio) and load the source code and required packages

```
packages <- c("rstan","dplyr","tidyr")
sources <- c("R/stan_functions.R",
             "R/process_output.R")

for (p in packages) {
  library(p, character.only=TRUE, quietly=TRUE)
}
for (s in sources) {
  source(s)
}
```

Now if you are only interested in a single model and you want to compile chains per kfold you can use:

```
single_model <- compile_multiple_comparisons(comparison = "without_random_effects")
```

However, in the more likely scenario where you are comparing multiple models you can use:

```
multi_model <- compile_multiple_comparisons(comparison = c("without_random_effects","with_random_effects"))
```

These functions will return a single list with all fits for each stan model/kfold combination.

### Model diagnostics

If we are comparing many models, each with 10 kfolds, checking the diagnostics of each fit can be tedious and time consuming. In order to get around this we have written a diagnostic summary function that will give you a quick overview of how your model performed in terms of the worst convegence diagnostic (`Rhat`), the minimum effective sample size (`min_n_eff`), the number of Rhat's below 1.1 (`n_bad_rhat`), the number of divergent iterations (`n_divergent`) and the maximum_treedepth obtained `max_treedepth`. Again this can be done for a single model type or for multiple models.

```
# single model
kfold_diagnostics(single_model)

# multiple models
multi_analysis_kfold_diagnostics(multi_model)
```

### Extracting log likelihood samples
Now we want to extract the log likelihood samples from each kfold. Again this can be done for each individual model or across all models.

```
# Single model
single_model_samples <- extract_loglik_samples(single_model)

# Multiple models
multi_model_samples <- extract_multi_comparison_loglik_samples(multi_model)
```

### Summarizing log likelihood samples
Lastly we want to summaries these such that we take the average across kfolds and calculate an confidence interval. In this case the same function can be applied to both single and multi model structures.

```
summarise_loglik_samples(single_model_samples)
summarise_loglik_samples(multi_model_samples)
```





