# Train rf_nonlinear (lme4 + ranger) as in Virus_Analysis.ipynb
# Usage:
#   Rscript train_rf_nonlinear.R <path_to_Virus.xlsx> <output_dir>
#
# Writes: <output_dir>/rf_nonlinear.rds  (list: rf, meta)
#         <output_dir>/model_meta.json   (for Python to read)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
  stop("Usage: Rscript train_rf_nonlinear.R <Virus.xlsx> <output_dir>")
}
xlsx_path <- normalizePath(args[1], mustWork = TRUE)
out_dir <- args[2]
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

suppressPackageStartupMessages({
  library(readxl)
  library(lme4)
  library(ranger)
  library(jsonlite)
})

cl_lit <- read_excel(xlsx_path, sheet = "Lit_Review")
# Lit_Review filters must match Virus_Analysis.ipynb (Faulkner / LMM / rf_nonlinear block):
# filter on Sample for Torii, Chaplin, LMM, Bayesian, RF, GPR — not Paper — plus Kelly_1958, EPA, then Faulkner.
# Base-R + dplyr-compatible NA rules (same as %>% filter):
neq <- function(x, val) !is.na(x) & x != val

if (!"Strain" %in% names(cl_lit)) {
  stop("Lit_Review sheet must include a Strain column for Faulkner-only training.")
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
n_after_exclusions <- nrow(cl_pre)

sn_pre <- trimws(as.character(cl_pre$Strain))
cl_fit <- cl_pre[!is.na(sn_pre) & tolower(sn_pre) == "faulkner", , drop = FALSE]
n_faulkner <- nrow(cl_fit)
non_faulkner_excluded <- n_after_exclusions - n_faulkner
message(
  sprintf(
    "Rows after notebook-aligned exclusions (before strain): %d; after Strain == Faulkner: %d (non-Faulkner excluded: %d); distinct Paper groups: %d.",
    n_after_exclusions,
    n_faulkner,
    non_faulkner_excluded,
    length(unique(as.character(cl_fit$Paper)))
  )
)
if (non_faulkner_excluded == 0L) {
  message(
    "Faulkner filter removed 0 rows — training data are unchanged vs. 'all strains' after exclusions; expect same RF fit and predictions."
  )
}
if (n_faulkner == 0L) {
  stop("No rows left after Strain == 'Faulkner' filter. Check Lit_Review spelling/casing.")
}

cl_fit$pH_squared <- cl_fit$pH^2
cl_fit$Temperature_squared <- cl_fit$Temperature^2

lmm_random_slope <- lmer(
  Constant ~ pH + Temperature + (pH + Temperature | Paper),
  data = cl_fit
)
study_effects <- ranef(lmm_random_slope)$Paper
pn <- as.character(cl_fit$Paper)
cl_fit$StudyEffect_Intercept <- study_effects[pn, 1]
cl_fit$StudyEffect_pH <- study_effects[pn, 2]
cl_fit$StudyEffect_Temperature <- study_effects[pn, 3]

rf_nonlinear <- ranger(
  Constant ~ pH + Temperature + pH_squared + Temperature_squared +
    StudyEffect_Intercept + StudyEffect_pH + StudyEffect_Temperature,
  data = cl_fit,
  importance = "permutation",
  num.trees = 5000,
  seed = 111
)

strains <- if ("Strain" %in% names(cl_fit)) {
  sort(unique(as.character(cl_fit$Strain[!is.na(cl_fit$Strain)])))
} else {
  character(0)
}

meta <- list(
  model_type = "ranger_rf_nonlinear",
  study_effects_source = "lme4_r",
  train_rows = n_faulkner,
  train_rows_after_exclusions = n_after_exclusions,
  non_faulkner_rows_excluded = non_faulkner_excluded,
  training_scope = "Lit_Review rows after exclusions; Strain == Faulkner only (notebook-aligned).",
  source_code_url = "https://github.com/almabartholow/Virus-Inactivation-Analysis",
  source_xlsx = xlsx_path,
  feature_cols = c(
    "pH", "Temperature", "pH_squared", "Temperature_squared",
    "StudyEffect_Intercept", "StudyEffect_pH", "StudyEffect_Temperature"
  ),
  n_estimators = 5000L,
  seed = 111L,
  strains_in_training = strains,
  note = paste0(
    "Trained in R with lme4 + ranger; predictions use StudyEffect_* = 0. ",
    "Strain is not an RF feature; training rows are Faulkner-only. ",
    "Future data can support refits with extra factors (e.g. Strain) and fit comparison in R."
  )
)

bundle <- list(rf = rf_nonlinear, meta = meta)
rds_out <- file.path(out_dir, "rf_nonlinear.rds")
saveRDS(bundle, rds_out)

json_out <- file.path(out_dir, "model_meta.json")
write_json(meta, json_out, pretty = TRUE, auto_unbox = TRUE)

message("Wrote ", rds_out)
