# Single-row prediction — mirrors Virus_Analysis.ipynb grid loop (one row at a time).
# Request JSON: {"ph": 7, "temperature": 20}
# Writes JSON to stdout.

suppressPackageStartupMessages({
  library(ranger)
  library(jsonlite)
})

argv <- commandArgs(trailingOnly = TRUE)
if (length(argv) < 2) {
  stop("Usage: Rscript predict_rf_nonlinear.R <rf_nonlinear.rds> <request.json>")
}

rds_path <- normalizePath(argv[1], mustWork = TRUE)
req_path <- normalizePath(argv[2], mustWork = TRUE)

bundle <- readRDS(rds_path)
rf_nonlinear <- bundle$rf

j <- fromJSON(req_path, simplifyVector = TRUE)
ph <- as.numeric(j$ph)
temp <- as.numeric(j$temperature)

# Same columns as notebook grid when StudyEffect_* = 0
individual_row <- data.frame(
  pH = ph,
  Temperature = temp,
  pH_squared = ph^2,
  Temperature_squared = temp^2,
  StudyEffect_Intercept = 0,
  StudyEffect_pH = 0,
  StudyEffect_Temperature = 0
)

# ----- Notebook parity (per-grid-cell logic, single row) -----
set.seed(123)

prediction_output <- predict(rf_nonlinear, data = individual_row, predict.all = TRUE)
predictions <- prediction_output$predictions

# ranger returns an (n_samples x n_trees) matrix; one row => take that row as tree preds.
# If shaped as (n_trees x 1), take the column (matches quantile(mean(...)) on vector).
if (is.matrix(predictions)) {
  nt <- rf_nonlinear$num.trees
  if (nrow(predictions) == 1L && ncol(predictions) == nt) {
    predictions <- predictions[1, , drop = TRUE]
  } else if (ncol(predictions) == 1L && nrow(predictions) == nt) {
    predictions <- predictions[, 1, drop = TRUE]
  } else if (nrow(predictions) == 1L) {
    predictions <- predictions[1, , drop = TRUE]
  } else {
    predictions <- as.numeric(predictions)
  }
} else {
  predictions <- as.numeric(predictions)
}

# Notebook: conservative k = 5th percentile across trees; mean k = mean(predictions)
k_conservative <- as.numeric(stats::quantile(predictions, probs = 0.05, type = 7))
mean_k <- as.numeric(mean(predictions))

# Optional: approximate k interval from trees (not in your snippet; useful for UI)
k_lo <- as.numeric(stats::quantile(predictions, probs = 0.025, type = 7))
k_hi <- as.numeric(stats::quantile(predictions, probs = 0.975, type = 7))

num <- -log(10^-4)

# Notebook: CT_4log = ifelse(k > 0, -log(10^-4) / k, NA)
ct_from_k <- function(k) {
  if (length(k) != 1L || is.na(k) || k <= 0) {
    NA_real_
  } else {
    num / k
  }
}

CT_4log_conservative <- ct_from_k(k_conservative)
CT_4log_mean_k <- ct_from_k(mean_k)

# CT bounds from tree spread on k: high k -> low CT, low k -> high CT
ct_4log_95_low <- ct_from_k(k_hi)
ct_4log_95_high <- ct_from_k(k_lo)

out <- list(
  mean = mean_k,
  mean_trees = mean_k,
  mean_prediction = mean_k,
  conservative_constant = k_conservative,
  ci_low = k_lo,
  ci_high = k_hi,
  units = "L·mg⁻¹·min⁻¹ (inactivation rate constant)",
  log_numerator_4log = num,
  k_conservative_5pct = k_conservative,
  ct_4log_mean = CT_4log_mean_k,
  ct_4log_conservative = CT_4log_conservative,
  CT_4log = CT_4log_conservative,
  ct_4log_95_low = ct_4log_95_low,
  ct_4log_95_high = ct_4log_95_high,
  ct_units = "mg·min/L (CT for 4-log inactivation; conservative uses k = quantile(trees, 0.05) as in notebook)"
)

cat(jsonlite::toJSON(out, pretty = TRUE, auto_unbox = TRUE, na = "null"), "\n", sep = "")
