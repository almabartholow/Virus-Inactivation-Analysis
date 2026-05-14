# R dependencies for chlorine_tool (run from repo root: Rscript chlorine_tool/r/install_deps.R)
#
# WINDOWS — if install says "Permission denied" on rlang.dll / vctrs.dll:
#   1) Quit RStudio and any R session (including Task Manager: end Rterm.exe / Rsessions).
#   2) Delete these folders if they exist (adjust 4.5 to your R minor version):
#        %LOCALAPPDATA%\R\win-library\4.5\rlang
#        %LOCALAPPDATA%\R\win-library\4.5\00LOCK
#   3) Run this script again (PowerShell as normal user is fine).
#
repos <- "https://cloud.r-project.org"
inst_type <- if (.Platform$OS.type == "windows") "binary" else getOption("pkgType", "both")

# rlang must update cleanly — dplyr/reformulas stack needs a recent rlang
install.packages("rlang", repos = repos, type = inst_type)
install.packages("vctrs", repos = repos, type = inst_type)

pkgs <- c("readxl", "lme4", "ranger", "jsonlite", "shiny", "DT")
install.packages(pkgs, repos = repos, type = inst_type)

message("rlang: ", packageVersion("rlang"), " | train script uses base R only (no dplyr).")
