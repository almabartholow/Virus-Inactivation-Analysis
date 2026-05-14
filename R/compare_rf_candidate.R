#!/usr/bin/env Rscript
# Offline maintainer script — NOT part of the chlorine_tool app bundle.
# Compare a candidate rf_nonlinear (ranger + lme4) to published benchmark metrics.
# Training filters match chlorine_tool/r/train_rf_nonlinear.R and Virus_Analysis.ipynb.
#
# Usage (from repository root):
#   Rscript R/compare_rf_candidate.R Virus.xlsx
#   Rscript R/compare_rf_candidate.R Virus.xlsx chlorine_tool/artifacts/rf_nonlinear.rds
#
# One-time packages (install separately; not listed in chlorine_tool/r/install_deps.R):
#   install.packages(c("readxl", "lme4", "ranger", "caret", "randomForest"))
#
# Environment:
#   SKIP_LOO=1  — skip LOO-CV (randomForest; one fit per row; slow for large n)

args <- commandArgs(trailingOnly = TRUE)
if (!length(args)) {
  stop(
    "Usage: Rscript R/compare_rf_candidate.R <Virus.xlsx> [existing_rf_nonlinear.rds]\n",
    "  Run from the repository root (parent of chlorine_tool/ and R/).\n",
    "  Virus.xlsx — Lit_Review sheet at repo root (included in this repository)\n",
    "  optional RDS — load baseline bundle and print metrics on this Excel (sanity check)",
    call. = FALSE
  )
}

xlsx_path <- normalizePath(args[[1]], winslash = "/", mustWork = TRUE)
baseline_rds <- if (length(args) >= 2L) {
  normalizePath(args[[2]], winslash = "/", mustWork = TRUE)
} else {
  NA_character_
}

skip_loo <- identical(Sys.getenv("SKIP_LOO", ""), "1")

suppressPackageStartupMessages({
  library(readxl)
  library(lme4)
  library(ranger)
  library(caret)
  library(randomForest)
})

# ---- 1) Published deployment benchmark
# Order: R^2 (cor^2 vs Constant on ranger predictions), RMSE (OOB preds), OOB R^2,
#        k-fold R^2 (Virus_Analysis cv_rf_r2_global: randomForest 500 trees),
#        LOO-CV R^2 (Virus_Analysis cv_rf_r2_loo: randomForest 500 trees).
# Edit these to match YOUR notebook printouts if they differ from the deployment card.
BASELINE <- c(
  r2 = 0.96,
  rmse = 0.94,
  oob_r2 = 0.89,
  kfold_r2 = 0.90,
  loo_r2 = 0.89
)
CONTACT_LINE <- paste0(
  "If the candidate clearly improves on these benchmarks, contact the project maintainer ",
  "(Alma Bartholow — see repository README) before swapping production artifacts."
)

neq <- function(x, val) {
  !is.na(x) & x != val
}

#' Same Lit_Review → Faulkner frame as chlorine_tool/r/train_rf_nonlinear.R
build_cl_fit <- function(xlsx_path) {
  cl_lit <- readxl::read_excel(xlsx_path, sheet = "Lit_Review")
  if (!"Strain" %in% names(cl_lit)) {
    stop("Lit_Review must include a Strain column.", call. = FALSE)
  }
  sel_pre <-
    neq(cl_lit$Sample, "Torii_2020") &
    neq(cl_lit$Sample, "This_Study_noNH3_2") &
    neq(cl_lit$Sample, "This_Study_noNH3_3") &
    neq(cl_lit$Sample, "Chaplin") &
    neq(cl_lit$Sample, "LMM") &
    neq(cl_lit$Sample, "Bayesian") &
    neq(cl_lit$Sample, "RF") &
    neq(cl_lit$Sample, "GPR") &
    neq(cl_lit$Paper, "Kelly_1958") &
    neq(cl_lit$Paper, "EPA")
  cl_pre <- cl_lit[sel_pre, , drop = FALSE]
  sn_pre <- trimws(as.character(cl_pre$Strain))
  cl_fit <- cl_pre[!is.na(sn_pre) & tolower(sn_pre) == "faulkner", , drop = FALSE]
  if (!nrow(cl_fit)) {
    stop("No Faulkner rows after filters — check Strain spelling.", call. = FALSE)
  }
  cl_fit$pH_squared <- cl_fit$pH^2
  cl_fit$Temperature_squared <- cl_fit$Temperature^2
  lmm_random_slope <- lme4::lmer(
    Constant ~ pH + Temperature + (pH + Temperature | Paper),
    data = cl_fit
  )
  study_effects <- lme4::ranef(lmm_random_slope)$Paper
  pn <- as.character(cl_fit$Paper)
  cl_fit$StudyEffect_Intercept <- study_effects[pn, 1L]
  cl_fit$StudyEffect_pH <- study_effects[pn, 2L]
  cl_fit$StudyEffect_Temperature <- study_effects[pn, 3L]
  cl_fit
}

rf_formula <- as.formula(
  Constant ~ pH + Temperature + pH_squared + Temperature_squared +
    StudyEffect_Intercept + StudyEffect_pH + StudyEffect_Temperature
)

#' Ranger metrics (aligned with notebook cells: cor^2, RMSE on OOB preds, ranger$r.squared)
metrics_ranger <- function(rf, cl_fit) {
  y <- as.numeric(cl_fit$Constant)
  pr <- stats::predict(rf, data = cl_fit)$predictions
  r2 <- stats::cor(pr, y, use = "complete.obs")^2
  rmse_oob <- sqrt(mean((rf$predictions - y)^2, na.rm = TRUE))
  oob_r2 <- as.numeric(rf$r.squared)
  c(r2 = r2, rmse = rmse_oob, oob_r2 = oob_r2)
}

#' Virus_Analysis.ipynb — 5-fold global R² (randomForest, ntree = 500)
cv_rf_r2_global <- function(model_formula, data, k = 5L, seed = 123L, ntree = 500L) {
  set.seed(seed)
  folds <- caret::createFolds(data$Constant, k = k, list = TRUE)
  all_preds <- numeric(nrow(data))
  all_true <- numeric(nrow(data))
  for (i in seq_len(k)) {
    test_idx <- folds[[i]]
    train_data <- data[-test_idx, , drop = FALSE]
    test_data <- data[test_idx, , drop = FALSE]
    set.seed(seed + i)
    rf_model <- randomForest::randomForest(model_formula, data = train_data, ntree = ntree)
    all_preds[test_idx] <- as.numeric(stats::predict(rf_model, newdata = test_data))
    all_true[test_idx] <- as.numeric(test_data$Constant)
  }
  SSE <- sum((all_true - all_preds)^2)
  SST <- sum((all_true - mean(all_true))^2)
  1 - SSE / SST
}

#' Virus_Analysis.ipynb — LOO R² (randomForest, ntree = 500)
cv_rf_r2_loo <- function(model_formula, data, seed = 123L, ntree = 500L) {
  set.seed(seed)
  n <- nrow(data)
  preds <- numeric(n)
  for (i in seq_len(n)) {
    test_data <- data[i, , drop = FALSE]
    train_data <- data[-i, , drop = FALSE]
    set.seed(seed + i)
    rf_model_loo <- randomForest::randomForest(model_formula, data = train_data, ntree = ntree)
    preds[i] <- as.numeric(stats::predict(rf_model_loo, newdata = test_data))
  }
  y_true <- as.numeric(data$Constant)
  SSE <- sum((y_true - preds)^2)
  SST <- sum((y_true - mean(y_true))^2)
  1 - SSE / SST
}

#' Optional: caret 5-fold CV Rsquared with ranger (diagnostic; grid matches caret defaults)
caret_ranger_cv_r2 <- function(cl_fit, seed = 111L) {
  set.seed(seed)
  p <- 7L
  mtry_v <- max(1L, floor(sqrt(p)))
  tg <- expand.grid(
    mtry = mtry_v,
    splitrule = "variance",
    min.node.size = 5L
  )
  fit <- caret::train(
    rf_formula,
    data = cl_fit,
    method = "ranger",
    trControl = caret::trainControl(method = "cv", number = 5L),
    tuneGrid = tg,
    num.trees = 5000L,
    importance = "none",
    seed = seed
  )
  max(fit$results$Rsquared, na.rm = TRUE)
}

fit_candidate_ranger <- function(cl_fit, seed = 111L) {
  ranger(
    rf_formula,
    data = cl_fit,
    importance = "permutation",
    num.trees = 5000L,
    seed = seed
  )
}

print_compare <- function(label, mvec, baseline = BASELINE, show_contact = TRUE) {
  cat("\n=== ", label, " ===\n", sep = "")
  df <- data.frame(
    metric = names(baseline),
    baseline = as.numeric(baseline),
    candidate = as.numeric(mvec[names(baseline)]),
    row.names = NULL
  )
  df$delta <- df$candidate - df$baseline
  # RMSE: lower is better — positive delta = improvement
  df$delta[df$metric == "rmse"] <- df$baseline[df$metric == "rmse"] - df$candidate[df$metric == "rmse"]
  print(df, digits = 4, row.names = FALSE)

  if (!isTRUE(show_contact)) {
    cat("\n(Repro / diagnostic table only — contact line suppressed.)\n")
    return(invisible(df))
  }

  better_r2 <- mvec[["r2"]] >= baseline[["r2"]] - 1e-4
  better_rmse <- mvec[["rmse"]] <= baseline[["rmse"]] + 1e-4
  better_oob <- mvec[["oob_r2"]] >= baseline[["oob_r2"]] - 1e-4
  better_kf <- mvec[["kfold_r2"]] >= baseline[["kfold_r2"]] - 1e-4
  better_loo <- is.na(mvec[["loo_r2"]]) || mvec[["loo_r2"]] >= baseline[["loo_r2"]] - 1e-4
  n_ok <- sum(c(better_r2, better_rmse, better_oob, better_kf, better_loo))
  cat("\nScore (metrics meeting or beating baseline): ", n_ok, "/5\n", sep = "")
  if (n_ok >= 4L && better_oob && better_kf) {
    cat("\n*** ", CONTACT_LINE, " ***\n", sep = "")
  } else {
    cat("\n(No automatic \"ship it\" — review deltas and notebook diagnostics before merging.)\n")
  }
  invisible(df)
}

# ---- 2) Read data
message("Reading: ", xlsx_path)
cl_fit <- build_cl_fit(xlsx_path)
message("Training rows (Faulkner): ", nrow(cl_fit))

# ---- 3) Candidate ranger (edit fit_candidate_ranger / formula in script for experiments)
message("Fitting candidate ranger (5000 trees, seed 111) …")
rf_new <- fit_candidate_ranger(cl_fit, seed = 111L)

# ---- 4) Metrics
m <- metrics_ranger(rf_new, cl_fit)
message("Computing 5-fold R² (randomForest, notebook cv_rf_r2_global) …")
m[["kfold_r2"]] <- cv_rf_r2_global(rf_formula, cl_fit, k = 5L, seed = 123L, ntree = 500L)

if (skip_loo) {
  m[["loo_r2"]] <- NA_real_
  message("SKIP_LOO=1 — LOO-CV not computed.")
} else {
  message("Computing LOO-CV R² (randomForest, notebook cv_rf_r2_loo) …")
  m[["loo_r2"]] <- cv_rf_r2_loo(rf_formula, cl_fit, seed = 123L, ntree = 500L)
}

# Optional: caret ranger CV R² (notebook alternative); printed for context
message("Computing caret 5-fold ranger Rsquared (diagnostic) …")
caret_cv <- tryCatch(
  caret_ranger_cv_r2(cl_fit, seed = 111L),
  error = function(e) {
    warning("caret ranger CV skipped: ", conditionMessage(e))
    NA_real_
  }
)
cat("Caret 5-fold max Rsquared (ranger, diagnostic): ", format(caret_cv, digits = 4), "\n", sep = "")

print_compare("Candidate (fresh ranger on this Virus.xlsx)", m)

# ---- 5) Optional: score existing RDS on same frame
if (!is.na(baseline_rds) && nzchar(baseline_rds)) {
  message("\nLoading baseline RDS: ", baseline_rds)
  bundle <- readRDS(baseline_rds)
  rf_old <- bundle$rf
  m_old <- metrics_ranger(rf_old, cl_fit)
  m_old[["kfold_r2"]] <- cv_rf_r2_global(rf_formula, cl_fit, k = 5L, seed = 123L, ntree = 500L)
  m_old[["loo_r2"]] <- if (skip_loo) {
    NA_real_
  } else {
    cv_rf_r2_loo(rf_formula, cl_fit, seed = 123L, ntree = 500L)
  }
  print_compare(
    "Loaded RDS re-scored on this Excel (same CV seeds as candidate)",
    m_old,
    show_contact = FALSE
  )
}

message("\nDone.")
