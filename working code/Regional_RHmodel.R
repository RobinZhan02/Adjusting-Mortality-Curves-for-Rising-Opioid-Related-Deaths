library(gnm)
library(forecast)
library(StMoMo)
library(demography)
library(ggplot2)
library(tidyverse)
library(reshape2) # For data transformation
library(gridExtra)
library(parallel)

# load dataset
region_data <- readRDS("../data/wonder_opioid/allcause_stmomo_monthly.rds")

# prepare data
# Function to subset StMoMo data to ages 25-65
subset_stmomo_ages <- function(stmomo_data, age_min = 25, age_max = 65) {
  age_idx <- which(stmomo_data$ages %in% age_min:age_max)

  stmomo_data$Dxt  <- stmomo_data$Dxt[age_idx, ]
  stmomo_data$Ext  <- stmomo_data$Ext[age_idx, ]
  stmomo_data$ages <- stmomo_data$ages[age_idx]

  return(stmomo_data)
}

# Apply to all four regions (overwrite original objects)
Midwest_data   <- subset_stmomo_ages(region_data[["Midwest"]])
Northeast_data <- subset_stmomo_ages(region_data[["Northeast"]])
South_data     <- subset_stmomo_ages(region_data[["South"]])
West_data      <- subset_stmomo_ages(region_data[["West"]])

# Forecast
## get rate function
get_fc_rates_vec <- function(fc, ages) {
  r <- fc$rates
  if (is.null(dim(r))) {
    v <- r
  } else {
    v <- r[, 1]
  }
  v <- as.numeric(v)
  names(v) <- rownames(as.matrix(fc$rates)) %||% names(fc$rates) # optional, but safer

  # best: just reorder by ages using names when available
  if (!is.null(names(fc$rates)) || !is.null(rownames(as.matrix(fc$rates)))) {
    nm <- if (!is.null(names(fc$rates))) names(fc$rates) else rownames(as.matrix(fc$rates))
    names(v) <- nm
    v <- v[as.character(ages)]
  }
  v
}

## One-month ahead forecast function
rh_roll_1mo_forecast <- function(mort_data, start_year = 2010, end_year = 2021) {

  # ---- fixed settings ----
  ages_fit <- 25:65
  max_try  <- 6

  # scale to monthly units (same as fit_RH_rr)
  mort_data$years <- mort_data$years * 12
  mort_data$ages  <- mort_data$ages  * 12

  # update row names (ages) and column names (years) of Dxt and Ext
  rownames(mort_data$Dxt) <- as.character(mort_data$ages)
  colnames(mort_data$Dxt) <- as.character(mort_data$years)
  rownames(mort_data$Ext) <- as.character(mort_data$ages)
  colnames(mort_data$Ext) <- as.character(mort_data$years)

  # now subset to ages of interest
  ages_fit_mo <- ages_fit * 12
  mort_data$Dxt <- mort_data$Dxt[as.character(ages_fit_mo), ]
  mort_data$Ext <- mort_data$Ext[as.character(ages_fit_mo), ]
  # change the mort_data$ages
  mort_data$ages <- ages_fit*12

  # RH model definition
  RHnp_mod <- rh(link = "log", cohortAgeFun = "NP")

  # ---- evaluation months ----
  time_num   <- mort_data$years   # in monthly units now
  eval_idx   <- which(time_num >= start_year * 12 & time_num < end_year * 12)
  origin_idx <- eval_idx - 1

  eval_time   <- time_num[eval_idx]
  origin_time <- time_num[origin_idx]

  # yearly versions for output naming only
  eval_time_yr   <- eval_time   / 12
  origin_time_yr <- origin_time / 12

  # ---- initialize storage lists ----
  sum_list      <- vector("list", length(origin_time))
  names(sum_list) <- as.character(origin_time_yr)

  sum_list_best <- vector("list", length(origin_time))
  names(sum_list_best) <- as.character(origin_time_yr)

  # ---- output matrix ----
  mx_hat_rh_ar <- matrix(NA_real_,
                         nrow = length(ages_fit),
                         ncol = length(eval_idx),
                         dimnames = list(as.character(ages_fit),
                                         as.character(eval_time_yr)))

  # ---- rolling forecast loop ----
  for (i in seq_along(eval_idx)) {

    T_mo <- origin_time[i]       # origin in monthly units (for StMoMo)
    T_yr <- origin_time_yr[i]    # origin in yearly units (for naming)
    set.seed(296 + T_mo)

    cat("\n--- Origin Year:", T_yr, "| Forecast Year:", eval_time_yr[i], "---\n")

    # data up to origin
    years_fit_mo <- time_num[1:origin_idx[i]]

    # yearly versions for naming
    years_fit_yr <- years_fit_mo / 12

    # cohorts for this origin (monthly units for computation, yearly for naming)
    cohorts_fit_mo <- (min(years_fit_mo) - max(ages_fit_mo)):(max(years_fit_mo) - min(ages_fit_mo))
    cohorts_fit_yr <- cohorts_fit_mo / 12

    # ---- column names in yearly units ----
    cn_i <- c(
      "conv", "fc_ok",
      paste0("ax_",    ages_fit),        # yearly ages 25:65
      paste0("bx1_",   ages_fit),
      paste0("bx2_",   ages_fit),
      paste0("kt_",    years_fit_yr),    # yearly kt
      paste0("gc_",    cohorts_fit_yr),  # yearly gc
      paste0("mx_fc_", ages_fit)         # yearly ages
    )

    # ---- initialize summary matrices for this origin ----
    sum_mat <- matrix(NA_real_,
                      nrow = max_try,
                      ncol = length(cn_i),
                      dimnames = list(paste0("iter_", 1:max_try), cn_i))

    sum_mat_best <- matrix(NA_real_,
                           nrow = 1,
                           ncol = length(cn_i),
                           dimnames = list("iter_1", cn_i))

    # ---- random restart ----
    best_loglik <- -Inf
    best_fc     <- NULL

    for (j in seq_len(max_try)) {
      # 1) try fitting
      fitRH_j <- tryCatch(
        fit(RHnp_mod,
            data      = mort_data,
            ages.fit  = ages_fit_mo,
            years.fit = years_fit_mo,
            control = gnm::gnm.control(start.iter = 4)),
        error = function(e) NULL
      )

      # 2) skip if failed
      if (is.null(fitRH_j) || isTRUE(fitRH_j$fail)) {
        cat("\n--- Iteration: ", j, "Model Fit Fail", "---\n")
        sum_mat[j, "conv"]  <- 0
        sum_mat[j, "fc_ok"] <- 0
        next
      }

      # 3) fill parameters (index using monthly, name using yearly)
      # ax
      sum_mat[j, paste0("ax_", ages_fit)] <-
        as.numeric(fitRH_j$ax[as.character(ages_fit_mo)])

      # bx
      bx1 <- fitRH_j$bx
      bx2 <- fitRH_j$b0x
      sum_mat[j, paste0("bx1_", ages_fit)] <-
        as.numeric(bx1[as.character(ages_fit_mo), 1])
      sum_mat[j, paste0("bx2_", ages_fit)] <-
        as.numeric(bx2[as.character(ages_fit_mo)])

      # kt (convert column names from monthly to yearly)
      ky_mo <- as.integer(colnames(fitRH_j$kt))
      ky_yr <- ky_mo / 12
      sum_mat[j, paste0("kt_", ky_yr)] <- as.numeric(fitRH_j$kt[1, ])

      # gc (convert names from monthly to yearly)
      gc       <- fitRH_j$gc
      gc_names_yr <- as.integer(names(gc)) / 12
      sum_mat[j, paste0("gc_", gc_names_yr)] <- as.numeric(gc)

      # 4) check convergence
      conv_j <- isTRUE(fitRH_j$conv)
      sum_mat[j, "conv"] <- as.numeric(conv_j)
      if (!conv_j) {
        cat("\n--- Iteration: ", j, "Does not converged ---\n")
        sum_mat[j, "fc_ok"] <- 0
        next
      }

      cat("\n--- Iteration: ", j, "Converged ---\n")
      # 5) try forecasting
      fcRH_j <- tryCatch(
        forecast(fitRH_j, h = 1, kt.method = "mrwd", gc.order = c(1, 1, 0)),
        error = function(e) NULL
      )

      if (is.null(fcRH_j)) {
        sum_mat[j, "fc_ok"] <- 0
        cat("\n--- Iteration: ", j, "Forecast Fail", "---\n")
        next
      }

      # 6) record forecast status and rates (index monthly, name yearly)
      cat("\n--- Iteration: ", j,"Forecast Success", "---\n")
      sum_mat[j, "fc_ok"] <- 1
      sum_mat[j, paste0("mx_fc_", ages_fit)] <-
        as.numeric(fcRH_j$rates[as.character(ages_fit_mo)])

      # 7) update best
      ll_j <- fitRH_j$loglik
      if (ll_j > best_loglik & !is.null(fcRH_j)) {
        best_loglik  <- ll_j
        best_fc      <- fcRH_j
        sum_mat_best[1, ] <- sum_mat[j, ]

        # store forecast rates with yearly column name
        mx_hat_rh_ar[, as.character(eval_time_yr[i])] <-
          get_fc_rates_vec(best_fc, ages_fit)
      }
    }

    # store summary matrices using yearly origin as key
    sum_list[[as.character(T_yr)]]      <- sum_mat
    sum_list_best[[as.character(T_yr)]] <- sum_mat_best
  }

  # ---- return ----
  return(list(
    mx_hat_rh_ar  = mx_hat_rh_ar,
    eval_time     = eval_time_yr,
    origin_time   = origin_time_yr,
    sum_list      = sum_list,
    sum_list_best = sum_list_best
  ))
}
stop("stopping here")


## Model and ForecastR
RH_Midwest2010 <- rh_roll_1mo_forecast(Midwest_data)
RH_Northeast  <- rh_roll_1mo_forecast(Northeast_data)
RH_South      <- rh_roll_1mo_forecast(South_data)
RH_West       <- rh_roll_1mo_forecast(West_data)

# save separately
saveRDS(RH_Midwest,   file = "rh_monthly_Midwest.rds")
saveRDS(RH_Northeast, file = "rh_monthly_Northeast.rds")
saveRDS(RH_South,     file = "rh_monthly_South.rds")
saveRDS(RH_West,      file = "rh_monthly_West.rds")
