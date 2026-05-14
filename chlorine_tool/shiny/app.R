# Chlorine virus inactivation — Shiny UI (parity with chlorine_tool FastAPI + static site).
# From repo root: shiny::runApp("chlorine_tool/shiny")
# Or: setwd("chlorine_tool/shiny"); shiny::runApp(".")
# Override paths: Sys.setenv(CHLORINE_TOOL_ROOT = "C:/path/to/chlorine_tool")
#
# shinyapps.io may evaluate app.R before global.R is attached; load helpers explicitly.
# Capture app directory here — getwd() can differ later (RStudio jobs, background workers).
assign(
  ".CHLORINE_SHINY_APP_DIR",
  normalizePath(getwd(), winslash = "/", mustWork = FALSE),
  envir = .GlobalEnv
)
global_r_path <- file.path(getwd(), "global.R")
if (!file.exists(global_r_path)) {
  stop("Missing global.R in ", getwd(), call. = FALSE)
}
sys.source(global_r_path, envir = .GlobalEnv)
if (!exists("ensure_submissions_file", mode = "function", inherits = TRUE)) {
  stop("global.R did not define ensure_submissions_file()", call. = FALSE)
}
ensure_submissions_file()

ui <- fluidPage(
  tags$head(
    tags$link(rel = "stylesheet", type = "text/css", href = "chlorine_static/style.css"),
    tags$title("Chlorine virus inactivation — estimator (Shiny)")
  ),
  headerPanel("Chlorine inactivation rate estimator"),
  fluidRow(
    column(
      12,
      p(
        class = "repo-banner",
        "Project repository: ",
        tags$a(
          href = "https://github.com/almabartholow/Virus-Inactivation-Analysis",
          "https://github.com/almabartholow/Virus-Inactivation-Analysis"
        )
      ),
      p(
        class = "intro-lead",
        tagList(
          "This tool estimates a ",
          tags$strong("chlorine inactivation rate constant"),
          " (",
          tags$em("k"),
          ") from ",
          tags$strong("pH"),
          " and ",
          tags$strong("temperature"),
          ", then derives ",
          tags$strong("CT"),
          " for ",
          tags$strong("4-log"),
          " inactivation. It is for research screening—always confirm against primary sources and local regulations."
        )
      ),
      tags$details(
        class = "dev-details dev-details--header",
        tags$summary("Technical details (training data & study effects)"),
        p(
          class = "meta-info",
          HTML(
            paste0(
              "<strong>Faulkner</strong>-filtered <code>Lit_Review</code> rows (see exclusions in ",
              "<code>Virus_Analysis.ipynb</code>). At prediction time, ",
              "<strong>study effects are set to zero</strong> so the forest sees only pH, temperature, and their squares ",
              "(plus the zeroed study-effect feature columns)."
            )
          )
        )
      ),
      uiOutput("health_line"),
      p(
        class = "meta-info workflow-banner",
        tagList(
          "The full statistical analysis, data preparation, and training scripts live on ",
          tags$a(
            href = "https://github.com/almabartholow/Virus-Inactivation-Analysis",
            "GitHub"
          ),
          "."
        )
      ),
      p(
        class = "meta-info workflow-banner workflow-banner--secondary",
        tagList(
          "The live site only reflects what is in the ",
          tags$strong("published bundle"),
          ": after someone submits a study it sits in the ",
          tags$strong("Queue"),
          " until a maintainer ",
          tags$strong("merges"),
          " approved rows into ",
          tags$strong("Virus.xlsx"),
          ", ",
          tags$strong("retrains"),
          " the model, and ",
          tags$strong("redeploys"),
          " the app (",
          tags$strong("Model"),
          " → maintainers)."
        )
      )
    )
  ),
  tabsetPanel(
    id = "tabs",
    tabPanel(
      "Estimator",
      br(),
      fluidRow(
        column(
          4,
          wellPanel(
            tags$fieldset(
              tags$legend("Inputs"),
              numericInput("ph", "pH", value = 7.5, min = 0, max = 14, step = 0.1),
              numericInput("temp", "Temperature (°C)", value = 20, step = 0.5),
              actionButton("btn_estimate", "Estimate", class = "btn-primary")
            )
          )
        ),
        column(
          8,
          wellPanel(
            h3("Estimated inactivation rate constant"),
            uiOutput("estimate_panel")
          )
        )
      )
    ),
    tabPanel(
      "Data table",
      br(),
      p(
        class = "meta-info",
        tagList(
          "Browse the compiled ",
          tags$strong("literature"),
          " table shipped with this app (from the ",
          tags$strong("Virus.xlsx"),
          " workbook). Column names match the analysis spreadsheet."
        )
      ),
      p(
        class = "meta-info",
        "Rows suggested through Submit appear here only after a maintainer merges them into that workbook (not automatic)."
      ),
      p(
        class = "meta-info",
        tagList(
          "Filters: strain text search. ",
          tags$strong("Near-match windows"),
          " when pH and/or temperature are set: pH within ±0.51, temperature within ±2.51 °C. Leave pH/temperature blank to load every row."
        )
      ),
      uiOutput("data_canonical_hint"),
      fluidRow(
        column(3, textInput("filter_strain", "Strain contains", placeholder = "e.g. Coxsackie")),
        column(2, numericInput("filter_ph", "pH", value = NA)),
        column(2, numericInput("filter_temp", "Temp °C", value = NA)),
        column(2, br(), actionButton("btn_load_table", "Load / refresh", class = "btn-primary")),
        column(3, br(), actionButton("btn_sync_estimator", "Copy pH & temp from estimator", class = "btn-secondary"))
      ),
      br(),
      uiOutput("table_count"),
      DT::DTOutput("data_table")
    ),
    tabPanel(
      "Model",
      br(),
      uiOutput("model_desc"),
      p(
        class = "meta-info",
        tagList(
          "Notebook, R scripts, and raw workflow: ",
          tags$a(
            href = "https://github.com/almabartholow/Virus-Inactivation-Analysis",
            "github.com/almabartholow/Virus-Inactivation-Analysis"
          ),
          "."
        )
      ),
      h4("How predictions are served"),
      p(
        class = "meta-info",
        tagList(
          "The hosted app loads the ",
          tags$strong("Virus.xlsx"),
          " workbook and trained model files shipped with that deployment. ",
          "Changing what users see requires merging new rows into that workbook, retraining, and ",
          tags$strong("redeploying"),
          "—there is no automatic pipeline from the Queue tab."
        )
      ),
      h4("Recorded benchmarks (optional)"),
      p(
        class = "meta-info",
        "When a benchmark file is bundled with the deployment, a comparison table appears below. It documents offline evaluations only and does not change live predictions."
      ),
      uiOutput("benchmark_hint"),
      div(id = "benchmark-table-wrap", class = "table-wrap", tableOutput("benchmark_models")),
      uiOutput("benchmark_updated"),
      h4("Review queue"),
      uiOutput("model_future"),
      h4("Clone, train, and redeploy"),
      p(
        class = "meta-info",
        tagList(
          "To reproduce or extend the analysis, follow the README and ",
          tags$a(
            href = "https://github.com/almabartholow/Virus-Inactivation-Analysis/blob/main/Virus_Analysis.ipynb",
            tags$code("Virus_Analysis.ipynb")
          ),
          " on GitHub. After updating data and artifacts, redeploy the Shiny app so the public site picks up the new ",
          tags$code("Virus.xlsx"),
          " and model files."
        )
      ),
      tags$details(
        class = "dev-details dev-details--panel",
        tags$summary("For developers & maintainers"),
        h4("Maintainer workflow (new data → live site)"),
        p(
          class = "meta-info",
          tagList(
            "Submissions do ",
            tags$strong("not"),
            " touch the estimator or Data tab until you complete these steps in order:"
          )
        ),
        tags$ol(
          class = "meta-info workflow-steps",
          tags$li(
            HTML(
              paste0(
                "<strong>Queue</strong> — New rows appear on the <strong>Queue</strong> tab (JSON Lines file). ",
                "They are <strong>not</strong> in <code>Virus.xlsx</code> yet."
              )
            )
          ),
          tags$li(
            HTML(
              paste0(
                "<strong>Merge</strong> — Manually add approved rows to the master <code>Virus.xlsx</code> ",
                "literature sheet (<code>Lit_Review</code>) offline—the same sheet the Data tab reads."
              )
            )
          ),
          tags$li(
            HTML(
              paste0(
                "<strong>Retrain</strong> — Run the repository training workflow (e.g. <code>chlorine_tool/train_model.py</code> ",
                "after dependencies and data are in place, and/or the notebook pipeline) to rebuild <code>rf_nonlinear.rds</code> ",
                "and related artifacts under <code>artifacts/</code>."
              )
            )
          ),
          tags$li(
            HTML(
              paste0(
                "<strong>Redeploy</strong> — Bundle the updated <code>Virus.xlsx</code> and model files with the app ",
                "and publish a new deployment (e.g. shinyapps.io) so the hosted site serves the new bundle."
              )
            )
          )
        ),
        h4("Candidate vs baseline (in R; not on this site)"),
        p(
          class = "meta-info",
          tagList(
            "Offline comparison helper (refit on ",
            tags$code("Virus.xlsx"),
            ", metrics vs baseline): ",
            tags$a(
              href = "https://github.com/almabartholow/Virus-Inactivation-Analysis/blob/main/R/compare_rf_candidate.R",
              "https://github.com/almabartholow/Virus-Inactivation-Analysis/blob/main/R/compare_rf_candidate.R"
            ),
            " — not bundled with the Shiny app; run locally from the repository root."
          )
        ),
        tags$ul(
          class = "meta-info workflow-steps",
          tags$li(HTML("<strong>R², RMSE</strong> — holdout or CV predictions vs <code>Constant</code>.")),
          tags$li(HTML("<strong>OOB</strong> — ranger <code>prediction.error</code> / derived R².")),
          tags$li(HTML("<strong>k-fold CV R²</strong> — caret or manual folds.")),
          tags$li(HTML("<strong>LOO</strong> — small <em>n</em> only; costly for large forests."))
        ),
        p(class = "meta-info", "Do not rely on training R² alone; use OOB and/or CV before adding complexity."),
        uiOutput("benchmark_dev_instructions"),
        h4("Notebook random forest (R / ranger)"),
        p(
          class = "meta-info",
          HTML(
            "Seven features; Faulkner training rows. Study effects from <code>lmer(Constant ~ pH + Temperature + (pH + Temperature | Paper))</code>; prediction sets them to zero."
          )
        ),
        tags$pre(
          class = "code-block",
          paste0(
            "# After dependencies are installed (see repo r/install_deps.R), from chlorine_tool:\n",
            "python train_model.py\n",
            "\n",
            "# Ranger formula (nonlinear + study effects at zero for prediction):\n",
            "ranger(Constant ~ pH + Temperature + pH_squared + Temperature_squared +\n",
            "  StudyEffect_Intercept + StudyEffect_pH + StudyEffect_Temperature, ...)"
          )
        ),
        h4("Training snapshot (model_meta.json)"),
        uiOutput("model_desc_meta")
      )
    ),
    tabPanel(
      "Submit study",
      br(),
      p(
        class = "meta-info",
        tagList(
          "Send a proposed literature row for review. It is stored as a ",
          tags$strong("JSON Lines"),
          " file (one record per line)—",
          tags$strong("not"),
          " in the official spreadsheet until a maintainer merges it. There is ",
          tags$strong("no"),
          " automatic retraining. Use the ",
          tags$strong("Queue"),
          " tab to inspect or download pending rows."
        )
      ),
      p(
        class = "meta-info",
        "Complete citation, strain, and rate constant when you can; that metadata helps future model work even if the current forest only uses pH and temperature."
      ),
      textInput("sub_name", "Your name (optional)"),
      textInput("sub_email", "Email (optional)"),
      textAreaInput("sub_citation", "Citation / DOI / link", rows = 2, placeholder = "Paper reference"),
      textInput("sub_strain", "Strain / virus (optional; not in current RF)"),
      fluidRow(
        column(4, numericInput("sub_ph", "pH", value = NA)),
        column(4, numericInput("sub_temp", "Temperature °C", value = NA)),
        column(4, numericInput("sub_k", "Rate constant (optional)", value = NA))
      ),
      textAreaInput("sub_notes", "Notes", rows = 3),
      actionButton("btn_submit", "Submit", class = "btn-primary"),
      br(),
      br(),
      verbatimTextOutput("submit_feedback", placeholder = TRUE)
    ),
    tabPanel(
      "Queue",
      br(),
      p(
        class = "meta-info",
        tagList(
          "Pending rows are stored as ",
          tags$strong("JSON Lines"),
          " (easy to download and diff). After ",
          tags$strong("Refresh"),
          ", the file path appears below. Approving means merging into the master workbook offline, then using ",
          tags$strong("Data table"),
          " → Load / refresh."
        )
      ),
      fluidRow(
        column(2, actionButton("btn_queue_refresh", "Refresh", class = "btn-primary")),
        column(3, br(), downloadButton("dl_submissions", "Download JSONL"))
      ),
      br(),
      uiOutput("queue_status"),
      DT::DTOutput("queue_table")
    )
  ),
  hr(),
  tags$footer(
    p(
      class = "meta-info",
      tagList(
        "Research use—confirm against primary sources. ",
        "Data and prediction logic are documented in ",
        tags$a(
          href = "https://github.com/almabartholow/Virus-Inactivation-Analysis",
          "https://github.com/almabartholow/Virus-Inactivation-Analysis"
        ),
        "."
      )
    )
  )
)

server <- function(input, output, session) {
  rv <- reactiveValues(
    lit_df = NULL,
    lit_total = NA_integer_,
    lit_err = NULL,
    lit_filters = FALSE,
    queue_tick = 0L,
    est = NULL,
    est_err = NULL,
    est_warn = NULL,
    submit_msg = character(0)
  )

  read_model_meta <- reactive({
    if (!file.exists(META_PATH)) {
      return(list())
    }
    tryCatch(fromJSON(META_PATH, simplifyVector = TRUE), error = function(e) list())
  })

  null_if_empty <- function(x) {
    if (is.null(x) || !nzchar(trimws(as.character(x)))) {
      NULL
    } else {
      trimws(as.character(x))
    }
  }

  null_if_na_num <- function(x) {
    if (is.null(x) || length(x) != 1L || is.na(x)) {
      NULL
    } else {
      as.numeric(x)
    }
  }

  output$health_line <- renderUI({
    invalidateLater(12000, session)
    model_ok <- file.exists(RDS_PATH)
    xp <- find_xlsx()
    n_lit <- NA_integer_
    if (!is.null(xp)) {
      n_lit <- tryCatch(
        nrow(readxl::read_excel(xp, sheet = "Lit_Review", n_max = 1e6)),
        error = function(e) NA_integer_
      )
    }
    dot_class <- "status-dot bad"
    txt <- "Checking…"
    title <- ""
    if (model_ok && !is.null(xp) && !is.na(n_lit)) {
      dot_class <- "status-dot ok"
      txt <- sprintf("Model and workbook loaded. Literature table: %s row(s).", n_lit)
      title <- xp
    } else if (model_ok && !is.null(xp) && is.na(n_lit)) {
      dot_class <- "status-dot ok"
      txt <- paste0(
        "Model and workbook found, but Lit_Review could not be read (",
        "close Virus.xlsx in Excel if it is open, or check the file path). ",
        basename(xp)
      )
      title <- xp
    } else if (model_ok) {
      dot_class <- "status-dot ok"
      txt <- if (likely_full_repo()) {
        "R model loaded; Virus.xlsx missing in repo root (data table limited)."
      } else {
        "R model loaded; Virus.xlsx not bundled with this app (data table limited — add file and redeploy)."
      }
    } else {
      txt <- if (likely_full_repo()) {
        paste(
          "Model not trained — with R on PATH run `python train_model.py` from chlorine_tool",
          "(after install_deps.R and Virus.xlsx in the repo root)."
        )
      } else {
        "No trained model is published with this app yet. See the Model tab and GitHub for how maintainers ship updates."
      }
    }
    p(
      id = "health-line",
      span(class = dot_class, id = "health-dot"),
      span(id = "health-text", title = title, txt)
    )
  })

  output$data_canonical_hint <- renderUI({
    invalidateLater(12000, session)
    xp <- find_xlsx()
    if (is.null(xp)) {
      return(p(class = "meta-info data-source-line", msg_data_tab_hint_no_xlsx()))
    }
    n <- tryCatch(nrow(read_lit_review(xp)), error = function(e) NA_integer_)
    if (is.na(n)) {
      return(p(class = "meta-info data-source-line", ""))
    }
    p(
      class = "meta-info data-source-line",
      sprintf("Workbook: %s — %d literature row(s).", basename(xp), n)
    )
  })

  observeEvent(input$btn_sync_estimator, {
    updateNumericInput(session, "filter_ph", value = input$ph)
    updateNumericInput(session, "filter_temp", value = input$temp)
  })

  observeEvent(input$btn_load_table, {
    xp <- find_xlsx()
    if (is.null(xp)) {
      rv$lit_df <- NULL
      rv$lit_err <- msg_no_virus_xlsx()
      rv$lit_total <- NA_integer_
      rv$lit_filters <- FALSE
      return()
    }
    df <- tryCatch(read_lit_review(xp), error = function(e) e)
    if (inherits(df, "error")) {
      rv$lit_err <- conditionMessage(df)
      rv$lit_df <- NULL
      rv$lit_total <- NA_integer_
      return()
    }
    rv$lit_err <- NULL
    rv$lit_total <- nrow(df)
    st <- input$filter_strain %||% ""
    phv <- input$filter_ph
    tv <- input$filter_temp
    has_ph <- is.finite(phv)
    has_tv <- is.finite(tv)
    filt <- nzchar(trimws(st)) || has_ph || has_tv
    rv$lit_filters <- filt
    out <- filter_lit_review(
      df,
      strain = st,
      ph = if (has_ph) phv else NA_real_,
      temp = if (has_tv) tv else NA_real_
    )
    rv$lit_df <- out
  })

  output$table_count <- renderUI({
    if (is.null(rv$lit_df) && is.null(rv$lit_err)) {
      return(p(class = "meta-info", "Click Load / refresh to read the literature sheet."))
    }
    if (!is.null(rv$lit_err)) {
      return(p(class = "meta-info", paste("Error:", rv$lit_err)))
    }
    n <- nrow(rv$lit_df)
    tot <- rv$lit_total
    if (isTRUE(rv$lit_filters) && !is.na(tot)) {
      p(class = "meta-info", sprintf("Showing %d of %d row(s) (filters applied).", n, tot))
    } else if (!is.na(tot)) {
      p(class = "meta-info", sprintf("%d row(s) — full literature sheet.", n))
    } else {
      p(class = "meta-info", sprintf("%d row(s).", n))
    }
  })

  output$data_table <- DT::renderDT({
    if (is.null(rv$lit_df)) {
      return(DT::datatable(
        data.frame(Message = "Click Load / refresh (needs Virus.xlsx next to the published model).", stringsAsFactors = FALSE),
        options = list(dom = "t"),
        rownames = FALSE,
        selection = "none"
      ))
    }
    if (!nrow(rv$lit_df)) {
      return(DT::datatable(data.frame(), options = list(dom = "t")))
    }
    disp <- rv$lit_df
    DT::datatable(
      disp,
      options = list(
        scrollX = TRUE,
        deferRender = TRUE,
        dom = "ftip",
        pageLength = 25
      ),
      rownames = FALSE
    )
  })

  observeEvent(input$btn_estimate, {
    rv$est <- NULL
    rv$est_err <- NULL
    rv$est_warn <- NULL
    if (!file.exists(RDS_PATH)) {
      rv$est_err <- msg_no_model_rds()
      return()
    }
    ph <- suppressWarnings(as.numeric(input$ph))
    temp <- suppressWarnings(as.numeric(input$temp))
    if (!is.finite(ph) || !is.finite(temp)) {
      showNotification("Enter valid pH and temperature.", type = "warning")
      return()
    }
    out <- tryCatch(
      predict_rf_row(RDS_PATH, ph, temp),
      error = function(e) e
    )
    if (inherits(out, "error")) {
      rv$est_err <- conditionMessage(out)
      return()
    }
    rv$est <- out
    meta <- read_model_meta()
    ses <- meta[["study_effects_source"]] %||% "lme4_r"
    if (identical(ses, "lme4_r")) {
      rv$est_warn <- div(
        id = "warn-box",
        class = "warn-banner",
        tagList(
          "Method matches the published R analysis on GitHub (random forest with study-level terms in training). ",
          "Technical stack: ",
          tags$strong("Model"),
          " tab → open ",
          tags$code("For developers & maintainers"),
          "."
        )
      )
    }
  })

  output$estimate_panel <- renderUI({
    if (!is.null(rv$est_err)) {
      return(div(id = "err-box", class = "err-banner", rv$est_err))
    }
    if (!is.null(rv$est)) {
      out <- rv$est
      ct_range <- paste(format_num(out$ct_4log_95_low), "–", format_num(out$ct_4log_95_high))
      return(tagList(
        rv$est_warn,
        div(
          id = "result-body",
          class = "results-card-inner estimate-results-wrap",
          tags$table(
            class = "estimate-results-table",
            tags$caption(class = "estimate-section-caption", "Inactivation rate constant (k)"),
            tags$tbody(
              tags$tr(
                tags$th(scope = "row", "Mean (across trees)"),
                tags$td(class = "est-num est-num-primary", format_num(out$mean))
              ),
              tags$tr(
                tags$th(scope = "row", "2.5th–97.5th percentile band"),
                tags$td(class = "est-num", paste(format_num(out$ci_low), "–", format_num(out$ci_high)))
              ),
              tags$tr(
                tags$th(scope = "row", "Units"),
                tags$td(class = "est-units", out$units)
              )
            )
          ),
          tags$table(
            class = "estimate-results-table estimate-ct-table",
            tags$caption(class = "estimate-section-caption", "4-log inactivation CT"),
            tags$tbody(
              tags$tr(
                tags$th(scope = "row", "Conservative (5th pct. k)"),
                tags$td(class = "est-num est-num-primary", format_num(out$ct_4log_conservative))
              ),
              tags$tr(
                tags$th(scope = "row", "From mean k"),
                tags$td(class = "est-num", format_num(out$ct_4log_mean))
              ),
              tags$tr(
                tags$th(scope = "row", "Descriptive range (from k percentiles)"),
                tags$td(class = "est-num", ct_range)
              ),
              tags$tr(
                tags$th(scope = "row", "Units"),
                tags$td(class = "est-units", "mg·min/L")
              )
            )
          ),
          p(
            class = "estimate-footnote",
            HTML(
              "CT = \u2212ln(10<sup>\u22124</sup>)/k. Conservative CT uses the 5th percentile of k across trees. The percentile band on k is not a classical confidence interval."
            )
          )
        )
      ))
    }
    div(
      id = "result-placeholder",
      class = "meta-info",
      tagList(
        "Results use the same ",
        tags$strong("rate constant"),
        " scale as the literature table (units appear with your estimate). ",
        "Set pH and temperature, then ",
        tags$strong("Estimate"),
        "."
      )
    )
  })

  output$model_desc <- renderUI({
    tagList(
      p(
        class = "meta-info",
        tagList(
          "The deployed model is a ",
          tags$strong("random forest"),
          " trained in R. It follows the workflow in the published ",
          tags$a(
            href = "https://github.com/almabartholow/Virus-Inactivation-Analysis/blob/main/Virus_Analysis.ipynb",
            "analysis notebook"
          ),
          " on GitHub. Study-specific offsets learned during training are ",
          tags$strong("not"),
          " applied when you click ",
          tags$strong("Estimate"),
          ", so the app returns a pooled literature curve as a function of pH and temperature."
        )
      )
    )
  })

  output$model_desc_meta <- renderUI({
    meta <- read_model_meta()
    meta_bits <- character()
    if (!is.null(meta$train_rows)) {
      meta_bits <- c(meta_bits, sprintf("Training rows (Faulkner): %s.", meta$train_rows))
    }
    if (!is.null(meta$non_faulkner_rows_excluded)) {
      meta_bits <- c(meta_bits, sprintf("Non-Faulkner excluded: %s.", meta$non_faulkner_rows_excluded))
      if (isTRUE(meta$non_faulkner_rows_excluded == 0)) {
        meta_bits <- c(meta_bits, "(Same rows as all-strain post-exclusions.)")
      }
    }
    if (!is.null(meta$training_scope)) {
      meta_bits <- c(meta_bits, as.character(meta$training_scope))
    }
    if (!length(meta_bits)) {
      return(p(class = "meta-info", "No extra fields in model_meta.json (optional)."))
    }
    p(class = "meta-info", paste(meta_bits, collapse = " "))
  })

  output$model_future <- renderUI({
    p(
      class = "meta-info",
      tagList(
        "Use the ",
        tags$strong("Queue"),
        " tab to inspect or download pending rows. ",
        "They do not change the live app until a maintainer merges them into ",
        tags$code("Virus.xlsx"),
        ", retrain, and redeploy (full sequence under ",
        tags$strong("Model"),
        " → ",
        tags$code("For developers & maintainers"),
        ")."
      )
    )
  })

  output$benchmark_dev_instructions <- renderUI({
    if (file.exists(BENCHMARK_PATH)) {
      return(NULL)
    }
    ex_url <- "https://github.com/almabartholow/Virus-Inactivation-Analysis/blob/main/chlorine_tool/model_benchmark.example.json"
    tagList(
      h4("Shipping an optional benchmark table"),
      p(
        class = "meta-info",
        tagList(
          tags$em("No benchmark JSON is bundled yet."),
          " Maintainers can start from the ",
          tags$a(href = ex_url, "example JSON on GitHub"),
          ", fill in metrics from R, rename it to ",
          tags$code("model_benchmark.json"),
          ", ship it with the published model bundle, and republish the app; the comparison table will then appear above."
        )
      )
    )
  })

  output$benchmark_hint <- renderUI({
    if (!file.exists(BENCHMARK_PATH)) {
      return(NULL)
    }
    b <- tryCatch(fromJSON(BENCHMARK_PATH, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(b)) {
      return(p(class = "meta-info", "Benchmark file could not be read."))
    }
    note <- if (!is.null(b$note)) as.character(b$note)[1] else ""
    if (nzchar(note)) {
      return(p(class = "meta-info", note))
    }
    NULL
  })

  output$benchmark_updated <- renderUI({
    if (!file.exists(BENCHMARK_PATH)) {
      return(NULL)
    }
    b <- tryCatch(fromJSON(BENCHMARK_PATH, simplifyVector = TRUE), error = function(e) NULL)
    req(!is.null(b))
    parts <- c()
    if (!is.null(b$updated_at)) {
      parts <- c(parts, sprintf("Table last updated: %s", b$updated_at))
    }
    if (!length(parts)) {
      return(NULL)
    }
    p(class = "meta-info data-source-line", paste(parts, collapse = " "))
  })

  output$benchmark_models <- renderTable({
    req(file.exists(BENCHMARK_PATH))
    b <- tryCatch(fromJSON(BENCHMARK_PATH, simplifyVector = TRUE), error = function(e) NULL)
    req(!is.null(b))
    models <- b$models
    if (is.null(models)) {
      return(NULL)
    }
    if (is.data.frame(models) && !nrow(models)) {
      return(NULL)
    }
    if (is.list(models) && !length(models)) {
      return(NULL)
    }
    if (is.data.frame(models)) {
      df <- models
    } else {
      df <- as.data.frame(do.call(rbind, lapply(models, as.data.frame)), stringsAsFactors = FALSE)
    }
    cols <- c("name", "role", "r2", "rmse", "oob_r2", "kfold_r2", "loo_r2", "notes")
    present <- intersect(cols, names(df))
    tab <- df[, present, drop = FALSE]
    for (nm in names(tab)) {
      tab[[nm]] <- sapply(tab[[nm]], fmt_bench_cell)
    }
    names(tab) <- c(
      "Model", "Role", "R²", "RMSE", "OOB R²", "k-fold R²", "LOO R²", "Notes"
    )[seq_len(ncol(tab))]
    tab
  }, striped = TRUE, hover = TRUE, spacing = "s", align = "l", na = "—")

  observeEvent(input$btn_submit, {
    ensure_submissions_file()
    rec <- list(
      received_at = strftime(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      submitter_name = null_if_empty(input$sub_name),
      email = null_if_empty(input$sub_email),
      citation = null_if_empty(input$sub_citation),
      strain = null_if_empty(input$sub_strain),
      ph = null_if_na_num(input$sub_ph),
      temperature = null_if_na_num(input$sub_temp),
      constant = null_if_na_num(input$sub_k),
      notes = null_if_empty(input$sub_notes)
    )
    line <- toJSON(rec, auto_unbox = TRUE, null = "null")
    cat(line, file = SUBMISSIONS_PATH, append = TRUE, sep = "\n")
    rv$submit_msg <- sprintf("Saved to %s", normalizePath(SUBMISSIONS_PATH))
    rv$queue_tick <- rv$queue_tick + 1L
  })

  output$submit_feedback <- renderText({
    rv$submit_msg
  })

  queue_data <- reactive({
    input$btn_queue_refresh
    input$tabs
    rv$queue_tick
    read_submissions_jsonl(SUBMISSIONS_PATH)
  })

  output$queue_status <- renderUI({
    q <- queue_data()
    n <- q$count
    path <- q$path
    if (n > 0) {
      p(class = "meta-info", sprintf("%d pending · %s", n, path))
    } else {
      p(class = "meta-info", sprintf("Empty · %s", path))
    }
  })

  output$queue_table <- DT::renderDT({
    q <- queue_data()
    df <- records_to_display_df(q$submissions)
    if (!nrow(df)) {
      return(DT::datatable(data.frame(), options = list(dom = "t")))
    }
    DT::datatable(df, options = list(scrollX = TRUE, pageLength = 25), rownames = FALSE)
  })

  output$dl_submissions <- downloadHandler(
    filename = function() {
      "submissions.jsonl"
    },
    content = function(file) {
      if (!file.exists(SUBMISSIONS_PATH)) {
        writeLines(character(), file)
      } else {
        file.copy(SUBMISSIONS_PATH, file, overwrite = TRUE)
      }
    }
  )

  observeEvent(input$tabs, {
    if (identical(input$tabs, "Queue")) {
      rv$queue_tick <- rv$queue_tick + 1L
    }
  })
}

shinyApp(ui, server)
