Here we demonstrate three possible `remake` workflows that can be used to run cross validation with Rstan. The three approaches are designed so that the modelling issue can readily be scaled up or down as required. The three workflows we discuss here, from simplest to most complex include: 1) Running cross validation on your local computer; 2) Running on your local machine using `docker` and a queuing system `rrqueue`; and 3) workflow 2 but combined with Amazon's EC2 cluster.

In all workflows we treat the individual chains as job targets to be complete as opposed to an entire model object of N chains. We do this because in `stan` chains can finish at different times, and consquently, if jobs were submitted as *per model* then we'd lose efficiency as CPU workers will not be able to process to the next job until all chains are complete for a given model. Furthermore, by treating chains as the jobs targets we add additional flexibility to run as many jobs as there are CPUs.

## First clone this repository

Downloading a zip directly from github or if you have `git` installed via the terminal by first navigating to the path you wish for the repository to be saved and then running:

```
git clone git@github.com:traitecoevo/stan_crossval_demo.git
```

## Install remake
[remake](https://github.com/richfitz/remake) is a package that allows us to use a make-like workflow in R by specifying a series of declarative actions. In essence, this package tells R what order things should be run in to ensure all dependencies are met. 

```
devtools::install_github("richfitz/remake")
install.packages(c("R6", "yaml", "digest", "crayon", "optparse"))
devtools::install_github("richfitz/storr")
devtools::install_github("richfitz/remake")
remake::install_missing_packages()
devtools::install_github("traitecoevo/dockertest")
```

NOTE: if `devtools` is not installed it can be by running `install.packages("devtools")`.

## Process data ready for analysis
Now we need to download, process and split the data into 10-folds for subsequent use with stan. We've automated this using the package `remake` and its declaration file `remake.yml`.  For a tutorial of how to use `remake` please see [here](https://github.com/ropenscilabs/remake-tutorial).

Ensuring you are within `stan_crossval_demo` you can enter R and run the following:

```
R # enters R
remake::make() # runs remake
```
From here on in we have three possible workflows that a user could implement. We discuss these below.

## Simplest approach: Running cross validation on local computer

**NOTE** We could have implemented this entire workflow in a single call to `remake` by adding additional dependencies to the target `all`. However, as we are highlighting three different approaches we are set remake as a two step process: first we process the data, then we run the models and/or process the model outputs.

Now that the data is processed we can queue and simultaneously run as many jobs as there are `parallel::detectCores() - 1`. Here we parallelise our jobs by using `parallel::mclapply`. Unfortuantely, this won't work for windows users who will need to change the function `run_jobs` in `R/stan_functions` to use a windows equivalent such as `parlapply`.

Running the following in the same R terminal as above will will precompile all stan models and then run all jobs defined in the remake object `tasks`:

```
remake::make('simple')
```

This should produce a a directory within the project called `results/` which will save all the chain fits for all model types (in this case `without_random_effects` and `with_random_effects`).

Pretty impressive huh?

For details about how to process this output see `Processing your outputs` towards the end of this document.

Now... what if you want to run your cross validation in a controlled and reproducible environment? We can use docker for this!

## Middle approach: Cross validation with docker

**NOTE** If you have ran the previous approach and want to try this first refresh your remake by running the following in R:

```
remake::make('purge')
remake::make()
```

### Install docker

Docker is a program that allows users to makes virtual machines (called containers) that contains all the software needed to run a program or analysis. As such it is a tool that can be used to guarantee some software will always run the same way, regardless of the environment it is running in. Instructions on how to install this can be found [here](https://docs.docker.com).

### Create a docker container

Once docker is installed we can build a docker container (a virtual machine). In our case, because we want to compile rstan models we require a container with sufficient amount of memory. 
Below we quit out of R and build a docker container with 3 GB of ram and 3 CPUs (the exact number will depend on how many cores you are happy to use) in the terminal using the Docker command `docker-machine`. We call this container  `mem3GB`

```
q("no") # quits R
docker-machine create --virtualbox-memory "3000" --driver virtualbox --virtualbox-cpu-count 3 mem3GB
```
(`--virtualbox-memory "3000"` sets how much virtual memory is available to the virtual machine.
 `----virtualbox-cpu-count 3` sets the number of CPUs you wish to use from your local machine)


### Downloading or building a docker image for your container
Next we wish to add a Ubuntu operating system, R and all dependent packages to the docker container. Since building such an image can take some time, we've already done the hard work for you such that you can simply download the image from the terminal using:

```
eval "$(docker-machine env mem3GB)"
docker pull traitecoevo/stan_crossval_demo:latest
```

However, if you've added packages to `remake.yml` or to `dockertest.yml` you are best to rebuild the image in R by ensuring your terminal is within `stan_crossval_demo and running:
```
R # enters R
dockertest::build(machine = "mem3GB")
```
This will open R and connect you to the docker container `mem3B`.


### Precompile stan models for docker container

If you have several different models to run, it is best to precompile them for use with docker prior to actually sampling the models. This can be done in R (assuming you are within `stan_crossval_demo`):

```
R
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


## Processing your outputs
Once all jobs are complete (regardless of the approach you undertook), you will want to examine model diagnostics, posteriors and produce plots. To do this we need to combine all the chains associated with a given model.

We have incorporated these processes into remake, allowing us to do all of the above with a single remake call in R. To do this, open up a new R session in the directory `stan_crossval_demo`. (We can't use the existing R session because that is an R session opened in the docker container)

```
R
remake::make('process_output')
```

The above will compile tchains for each model, extract model diagnostics, extract log likelihoods and then calculate the mean and 95% confidence interval of log likelihoods across folds and then plots these and save the figure in `figures/`.

All the intermediate steps are saved as .remake files. You can access any step by simply calling the desired target name in the remake.yml file.

For example, if we wish to have a look at the list of compiled models we could run:

```
model_list <- remake::make('compiled_models')
```

Or maybe we want to look at a summary of model diagnoistics:

```
remake::make('model_diagnostics')
```

Or maybe we just want to see the actual values of the log likelihood summaries:

```
remake::make('loglik_summary')
```

We can also plot these log likelihood differences by running:
```
remake::make('figures/loglik_plot.pdf')
```
which will create a figure and save a pdf of it in the folder `figures/`.

In this example the model that incorporated species effects was by far the more predictive model (lower log likelihood). If we then wanted to see the effects of parameters we would rerun this model on the entire dataset and simulate response curves based on the parameter posteriors.

Hope this helps!
Good luck!







