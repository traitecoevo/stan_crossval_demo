download_baad <- function(destination_filename) {
  url <-
    "https://github.com/dfalster/baad/releases/download/v0.9.0/baad.rds"
  download(url, destination_filename, mode="wb")
  # download function from package downloader provides wrapper
  # to download file so that works for https and across platforms
}

clean_data <- function(data, response, covariate) {
  rm_na <- substitute(!is.na(y) & !is.na(x), list(y = as.name(response), x = as.name(covariate)))
  dat <- data$data %>%
    filter_(rm_na) %>%
    filter(growingCondition =='FW') %>%
    group_by(speciesMatched) %>%
    mutate(n_ind = n()) %>%
    ungroup() %>%
    filter(n_ind >=10) %>% # Only select species with at least 10 individuals
    group_by(location) %>%
    mutate(n_site = n()) %>%
    ungroup() %>%
    filter(n_site >=10) %>% # Only select sites with at least 10 individuals
    mutate(sp_id = as.numeric(factor(speciesMatched)),
           site_id = as.numeric(factor(location))) %>%
    arrange(sp_id, site_id) %>%
    select_('location', 'n_site','site_id','n_ind', 'speciesMatched', 'sp_id', 'map', 'mat', response, covariate)
}

make_trainheldout <- function(data) {
  lapply(seq_along(data), function(i)
         extract_trainheldout_set(data, i))
}

split_into_kfolds <- function(data, k=10) {
  # make dataset an even multiple of 10
  data <- data[seq_len(floor(nrow(data) / k) * k), ]
  # execute the split
  # use an ordered vector so that all species distributed
  # approx. equally across groups
  fold <- rep(seq_len(k), nrow(data)/k)
  split(data, fold)
}

extract_trainheldout_set <- function(data, k=NA) {
  # by default train on whole dataset
  i_train <- seq_len(length(data))
  if (is.na(k)) {
    i_heldout <- NA
    res <- rbind_all(data[i_train])
  } else {
    i_train <- setdiff(i_train, k)
    i_heldout <- k

    res <- list(
    train = rbind_all(data[i_train]),
    heldout  = rbind_all(data[i_heldout]))
  }
  return(res)
}

make_trainheldout <- function(data) {
  lapply(seq_along(data), function(i)
         extract_trainheldout_set(data, i))
}

## Really ugly working around something I've not worked out how to do
## in remake (1 function -> n file outputs)
export_data <- function(data, filename) {
  filename_fmt <- sub("\\.rds$", "_%s.rds", filename)
  filename_sub <- sprintf(filename_fmt, seq_along(data))
  for (i in seq_along(data)) {
    saveRDS(data[[i]], filename_sub[[i]])
  }
}