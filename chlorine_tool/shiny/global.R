# Shared paths and helpers for the chlorine_tool Shiny app.
# Run: shiny::runApp("chlorine_tool/shiny") from the repo root (or any cwd if CHLORINE_TOOL_ROOT is set).

# Keep startup minimal: shinyapps.io serves the bundle from a read-only tree and can
# fail if heavy/native deps error at attach time. readxl / ranger / DT load on demand.
suppressPackageStartupMessages({
  library(shiny)
  library(jsonlite)
})

`%||%` <- function(x, y) if (is.null(x) || (length(x) == 1L && !nzchar(as.character(x)))) y else x

resolve_chlorine_tool_root <- function() {
  env <- Sys.getenv("CHLORINE_TOOL_ROOT", "")
  if (nzchar(env) && dir.exists(env)) {
    return(normalizePath(env))
  }
  wd <- normalizePath(getwd())

  pick_with_artifacts <- function(root) {
    r <- normalizePath(root, winslash = "/", mustWork = FALSE)
    if (!nzchar(r) || !dir.exists(r)) {
      return(NULL)
    }
    if (dir.exists(file.path(r, "artifacts"))) {
      return(r)
    }
    NULL
  }

  # Repo layout: .../chlorine_tool/shiny with sibling artifacts/
  if (!is.null(p <- pick_with_artifacts(wd))) {
    return(p)
  }
  if (basename(wd) == "shiny") {
    up <- normalizePath(file.path(wd, ".."))
    if (!is.null(p <- pick_with_artifacts(up))) {
      return(p)
    }
  }
  up <- normalizePath(file.path(wd, ".."))
  if (!is.null(p <- pick_with_artifacts(up))) {
    return(p)
  }

  # shinyapps.io (and other hosts): bundle is only app/ — no parent artifacts/.
  # Use app working directory so global.R does not stop(); model/data paths stay empty until you bundle files or set CHLORINE_TOOL_ROOT.
  wd
}

CHLORINE_TOOL_ROOT <- resolve_chlorine_tool_root()
REPO_ROOT <- normalizePath(file.path(CHLORINE_TOOL_ROOT, ".."))
ARTIFACTS <- file.path(CHLORINE_TOOL_ROOT, "artifacts")
RDS_PATH <- file.path(ARTIFACTS, "rf_nonlinear.rds")
META_PATH <- file.path(ARTIFACTS, "model_meta.json")
BENCHMARK_PATH <- file.path(ARTIFACTS, "model_benchmark.json")
bench_ex_candidates <- c(
  file.path(CHLORINE_TOOL_ROOT, "model_benchmark.example.json"),
  file.path(normalizePath(file.path(CHLORINE_TOOL_ROOT, ".."), winslash = "/", mustWork = FALSE), "model_benchmark.example.json")
)
BENCHMARK_EXAMPLE <- {
  hit <- bench_ex_candidates[file.exists(bench_ex_candidates)]
  if (length(hit)) hit[[1]] else bench_ex_candidates[[1]]
}

# Local clone: .../chlorine_tool/shiny with sibling ../artifacts. Hosted bundle: only app dir.
likely_full_repo <- function() {
  wd <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  nzchar(wd) &&
    basename(wd) == "shiny" &&
    dir.exists(file.path(wd, "..", "artifacts"))
}

msg_no_model_rds <- function() {
  if (likely_full_repo()) {
    paste(
      "No rf_nonlinear.rds found. Install R packages (chlorine_tool/r/install_deps.R),",
      "put Virus.xlsx in the repository root (parent of chlorine_tool/), then run: cd chlorine_tool && python train_model.py"
    )
  } else {
    paste(
      "No trained model is published with this app yet.",
      "See the Model tab and GitHub for how maintainers train and publish updates."
    )
  }
}

msg_no_virus_xlsx <- function() {
  if (likely_full_repo()) {
    "Virus.xlsx or virus.xlsx not found in the repository root (the folder that contains chlorine_tool/)."
  } else {
    paste(
      "Spreadsheet not found.",
      "Maintainers publish Virus.xlsx with the app when updating the hosted site (see GitHub)."
    )
  }
}

msg_data_tab_hint_no_xlsx <- function() {
  if (likely_full_repo()) {
    "Place Virus.xlsx (or virus.xlsx) in the repository root — the folder that contains chlorine_tool/."
  } else {
    paste(
      "No workbook found for this deployment.",
      "Publish Virus.xlsx with the app when updating the hosted site (see GitHub)."
    )
  }
}

# Local dev: data/submissions.jsonl under tool root. shinyapps.io: app dir is read-only — use tempdir().
choose_submissions_path <- function(root) {
  default <- file.path(root, "data", "submissions.jsonl")
  d <- dirname(default)
  good <- tryCatch(
    {
      dir.create(d, recursive = TRUE, showWarnings = FALSE)
      probe <- file.path(d, ".chlorine_write_probe")
      on.exit(unlink(probe), add = TRUE)
      writeLines("ok", probe, useBytes = TRUE)
      identical(readLines(probe, warn = FALSE, encoding = "UTF-8"), "ok")
    },
    error = function(e) FALSE,
    warning = function(w) FALSE
  )
  if (isTRUE(good)) {
    return(default)
  }
  file.path(tempdir(), "chlorine_submissions.jsonl")
}

SUBMISSIONS_PATH <- choose_submissions_path(CHLORINE_TOOL_ROOT)
STATIC_DIR <- file.path(CHLORINE_TOOL_ROOT, "static")
if (dir.exists(STATIC_DIR)) {
  shiny::addResourcePath("chlorine_static", STATIC_DIR)
}

find_xlsx <- function() {
  roots <- unique(
    c(
      REPO_ROOT,
      CHLORINE_TOOL_ROOT,
      normalizePath(getwd(), winslash = "/", mustWork = FALSE),
      file.path(CHLORINE_TOOL_ROOT, "www")
    )
  )
  for (r in roots) {
    if (!nzchar(r) || !dir.exists(r)) {
      next
    }
    for (name in c("Virus.xlsx", "virus.xlsx")) {
      p <- file.path(r, name)
      if (file.exists(p)) {
        return(normalizePath(p))
      }
    }
  }
  NULL
}

read_lit_review <- function(xlsx_path) {
  loadNamespace("readxl")
  df <- readxl::read_excel(xlsx_path, sheet = "Lit_Review")
  names(df) <- trimws(as.character(names(df)))
  df
}

filter_lit_review <- function(
    df,
    strain = "",
    ph = NA_real_,
    temp = NA_real_,
    ph_tol = 0.51,
    temp_tol = 2.51
) {
  out <- df
  st <- trimws(strain %||% "")
  if (nzchar(st) && "Strain" %in% names(out)) {
    mask <- grepl(st, as.character(out$Strain), ignore.case = TRUE, fixed = TRUE)
    out <- out[mask, , drop = FALSE]
  }
  if (is.finite(ph) && "pH" %in% names(out)) {
    out <- out[!is.na(out$pH) & abs(as.numeric(out$pH) - ph) <= ph_tol, , drop = FALSE]
  }
  if (is.finite(temp) && "Temperature" %in% names(out)) {
    out <- out[
      !is.na(out$Temperature) & abs(as.numeric(out$Temperature) - temp) <= temp_tol,
      ,
      drop = FALSE
    ]
  }
  out
}

#' Same logic as chlorine_tool/r/predict_rf_nonlinear.R (in-process).
predict_rf_row <- function(rds_path, ph, temperature) {
  loadNamespace("ranger")
  bundle <- readRDS(rds_path)
  rf_nonlinear <- bundle$rf
  individual_row <- data.frame(
    pH = ph,
    Temperature = temperature,
    pH_squared = ph^2,
    Temperature_squared = temperature^2,
    StudyEffect_Intercept = 0,
    StudyEffect_pH = 0,
    StudyEffect_Temperature = 0
  )
  set.seed(123)
  prediction_output <- predict(rf_nonlinear, data = individual_row, predict.all = TRUE)
  predictions <- prediction_output$predictions
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
  k_conservative <- as.numeric(stats::quantile(predictions, probs = 0.05, type = 7))
  mean_k <- as.numeric(mean(predictions))
  k_lo <- as.numeric(stats::quantile(predictions, probs = 0.025, type = 7))
  k_hi <- as.numeric(stats::quantile(predictions, probs = 0.975, type = 7))
  num <- -log(10^-4)
  ct_from_k <- function(k) {
    if (length(k) != 1L || is.na(k) || k <= 0) {
      NA_real_
    } else {
      num / k
    }
  }
  list(
    mean = mean_k,
    ci_low = k_lo,
    ci_high = k_hi,
    units = "L·mg⁻¹·min⁻¹ (inactivation rate constant)",
    log_numerator_4log = num,
    ct_4log_mean = ct_from_k(mean_k),
    ct_4log_conservative = ct_from_k(k_conservative),
    ct_4log_95_low = ct_from_k(k_hi),
    ct_4log_95_high = ct_from_k(k_lo),
    ct_units = "mg·min/L (CT for 4-log inactivation; conservative uses k = quantile(trees, 0.05) as in notebook)"
  )
}

format_num <- function(x) {
  if (length(x) != 1L) {
    return("—")
  }
  if (is.null(x) || is.na(x) || !is.finite(as.numeric(x))) {
    return("—")
  }
  v <- as.numeric(x)
  if (abs(v) >= 1000 || (abs(v) < 0.01 && v != 0)) {
    return(formatC(v, format = "e", digits = 3))
  }
  format(round(v, 4), nsmall = 4, trim = TRUE)
}

fmt_bench_cell <- function(v) {
  if (is.null(v) || (length(v) == 1L && (is.na(v) || v == ""))) {
    return("—")
  }
  if (is.numeric(v) && is.finite(v)) {
    if (abs(v) >= 1000 || (abs(v) < 1e-4 && v != 0)) {
      return(formatC(v, format = "e", digits = 3))
    }
    return(format(round(v, 4), nsmall = 4, trim = TRUE))
  }
  as.character(v)
}

read_submissions_jsonl <- function(path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  if (!file.exists(path)) {
    return(list(submissions = list(), path = path, count = 0L))
  }
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  subs <- list()
  line_no <- 0L
  for (raw in lines) {
    line_no <- line_no + 1L
    t <- trimws(raw)
    if (!nzchar(t)) {
      next
    }
    rec <- tryCatch(fromJSON(t), error = function(e) NULL)
    if (is.list(rec)) {
      rec[["_line"]] <- line_no
      subs[[length(subs) + 1L]] <- rec
    }
  }
  list(
    submissions = subs,
    path = normalizePath(path, winslash = "/", mustWork = FALSE),
    count = length(subs)
  )
}

records_to_display_df <- function(records) {
  if (!length(records)) {
    return(data.frame())
  }
  keys <- unique(unlist(lapply(records, names)))
  keys <- keys[order(keys != "_line", keys)]
  mat <- matrix("", nrow = length(records), ncol = length(keys), dimnames = list(NULL, keys))
  for (i in seq_along(records)) {
    r <- records[[i]]
    for (j in seq_along(keys)) {
      k <- keys[j]
      val <- r[[k]]
      mat[i, j] <- if (is.null(val) || (length(val) == 1L && is.na(val))) {
        ""
      } else if (length(val) == 1L) {
        as.character(val)
      } else {
        as.character(toJSON(val, auto_unbox = TRUE))
      }
    }
  }
  as.data.frame(mat, stringsAsFactors = FALSE)
}

ensure_submissions_file <- function() {
  tryCatch(
    {
      dir.create(dirname(SUBMISSIONS_PATH), recursive = TRUE, showWarnings = FALSE)
      if (!file.exists(SUBMISSIONS_PATH)) {
        writeLines(character(), SUBMISSIONS_PATH, useBytes = TRUE)
      }
    },
    error = function(e) invisible(NULL)
  )
}

# Never called — helps rsconnect discover optional runtime deps (loadNamespace / :: alone can be missed).
register_rsconnect_pkgs <- function() {
  if (FALSE) {
    suppressPackageStartupMessages({
      library(readxl)
      library(ranger)
      library(DT)
    })
  }
}
