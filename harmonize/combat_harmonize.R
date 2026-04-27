#!/usr/bin/env Rscript
# combat_harmonize.R
#
# Run ComBat harmonization on diffusion-metric matrices (features x subjects).
#
# Reference:
#   https://github.com/Jfortin1/ComBatHarmonization
#
# Prerequisites:
#   - Input matrices exported as tab-delimited text files, one per metric:
#       <matrixDir>/<metric>_matrix.txt
#     where rows = imaging features, columns = participants.
#   - A batch ID file with one batch/site/scanner label per participant column.
#   - (Optional) A design/covariates file for biological variables to preserve.
#
# Notes:
#   - For MATLAB/Python implementations, inputs must be finite (no NA/NaN).
#   - For R implementations, missing values can be handled, but constant rows
#     and rows with all missing values should be removed prior to ComBat.
#
# Created by Idy Chou on 22 Nov 2024

suppressPackageStartupMessages({
  library(data.table)
})

# ----------------------- User-configurable parameters -----------------------
topDir    <- "/path/to/processed_data"     # EDIT ME
matrixDir <- file.path(topDir, "combat")
outDir    <- matrixDir

# Batch/site/scanner id (one per subject column, in the same order as matrix columns)
idFile    <- file.path(topDir, "site_id.txt")  # EDIT ME

# Optional covariates file (CSV). Set to NULL to run without biological covariates.
designFile <- file.path(topDir, "demo_clin_data.csv") # or NULL
vars       <- c("Group", "Age", "Sex")                    # columns in designFile

# Metrics to harmonize
metrics <- c("fd", "log_fc", "fdc")

# ComBat options (neuroCombat supports additional args; keep defaults unless needed)
# parametric <- TRUE/FALSE, etc. (see neuroCombat documentation)
# ---------------------------------------------------------------------------

sep <- paste(rep("-", 55), collapse = "")

# ------------------------------ Dependencies --------------------------------
# Prefer: install these once in your environment, not inside the script.
# install.packages(c("data.table", "devtools"))
# devtools::install_github("jfortin1/neuroCombat_Rpackage")

if (!requireNamespace("neuroCombat", quietly = TRUE)) {
  stop(
    "Package 'neuroCombat' is not installed.\n",
    "Install it once, e.g.:\n",
    "  devtools::install_github('jfortin1/neuroCombat_Rpackage')"
  )
}
# ---------------------------------------------------------------------------

# ------------------------------ Helper funcs --------------------------------
read_batch_ids <- function(path) {
  if (!file.exists(path)) stop("Batch ID file not found: ", path)
  # Accept one-column txt/tsv/csv; fread is flexible
  x <- data.table::fread(path, header = FALSE)
  ids <- unlist(x[[1]])
  if (length(ids) == 0) stop("No batch IDs read from: ", path)
  ids
}

build_design_matrix <- function(designFile, vars, nSub) {
  if (is.null(designFile)) return(NULL)
  if (!file.exists(designFile)) stop("Design file not found: ", designFile)

  design_df <- read.csv(designFile, header = TRUE, stringsAsFactors = FALSE)

  missing_vars <- setdiff(vars, names(design_df))
  if (length(missing_vars) > 0) {
    stop("Design file is missing required columns: ", paste(missing_vars, collapse = ", "))
  }

  design_df <- design_df[, vars, drop = FALSE]

  # Basic row count check (common failure mode)
  if (nrow(design_df) != nSub) {
    stop(
      "Row mismatch: design file has ", nrow(design_df),
      " rows but matrix has ", nSub, " subjects (columns). ",
      "Ensure the same subject order."
    )
  }

  # Build formula like: ~ Group + Age + Sex
  fml <- as.formula(paste("~", paste(vars, collapse = " + ")))
  model.matrix(object = fml, data = design_df)
}
# ---------------------------------------------------------------------------

# ------------------------------ Main routine --------------------------------
if (!dir.exists(matrixDir)) stop("matrixDir not found: ", matrixDir)
if (!dir.exists(outDir)) dir.create(outDir, recursive = TRUE)

for (metric in metrics) {
  inFile  <- file.path(matrixDir, sprintf("%s_matrix.txt", metric))
  outFile <- file.path(outDir, sprintf("%s_matrix_harmonized.txt", metric))

  if (!file.exists(inFile)) {
    warning("Input matrix not found, skipping metric '", metric, "': ", inFile)
    next
  }
  if (file.exists(outFile)) {
    message("Output exists, skipping metric '", metric, "': ", outFile)
    next
  }

  cat(sprintf("%s\nReading %s matrix...\n%s\n", sep, metric, sep))
  dat_dt <- data.table::fread(inFile, header = FALSE, data.table = FALSE)
  dat <- as.matrix(dat_dt)

  # Validate matrix
  if (!is.numeric(dat)) storage.mode(dat) <- "double"
  if (any(!is.finite(dat))) {
    stop(
      "Input matrix contains NA/NaN/Inf for metric '", metric, "'. ",
      "Please clean the matrix before running ComBat."
    )
  }

  nVox <- nrow(dat)
  nSub <- ncol(dat)
  cat("Matrix size: ", nVox, " features x ", nSub, " subjects\n", sep, "\n", sep, "\n", sep, "\n", sep, "\n", sep, "\n", sep, "\n", sep, "\n", sep, "\n", sep, "\n", sep, "\n", sep, "\n", sep, "\n", sep, "\n", sep, "\n", sep, "\n", sep, "\n", sep, "\n", sep, "\n", sep, "\n", sep, "\n", sep, "\n", sep, "\n", sep, "\n", sep, "\n", sep, "\n", sep, "\n")

  # Batch IDs
  batch <- read_batch_ids(idFile)
  if (length(batch) != nSub) {
    stop(
      "Batch ID length mismatch for metric '", metric, "': ",
      "batch IDs = ", length(batch), ", matrix columns = ", nSub, ". ",
      "Ensure idFile has one entry per subject column, in the same order."
    )
  }

  # Optional covariates
  mod <- build_design_matrix(designFile = designFile, vars = vars, nSub = nSub)

  cat(sprintf("%s\nRunning ComBat harmonization for %s...\n%s\n", sep, metric, sep))
  if (is.null(mod)) {
    output <- neuroCombat::neuroCombat(dat = dat, batch = batch)
  } else {
    output <- neuroCombat::neuroCombat(dat = dat, batch = batch, mod = mod)
  }

  # Save harmonized matrix
  write.table(
    output$dat.combat,
    file = outFile,
    sep = "\t",
    col.names = FALSE,
    row.names = FALSE,
    quote = FALSE
  )

  cat(sprintf("%s\nSaved harmonized %s matrix:\n  %s\n%s\n", sep, metric, outFile, sep))
}

cat("Done.\n")
# ---------------------------------------------------------------------------
