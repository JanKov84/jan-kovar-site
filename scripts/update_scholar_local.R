#!/usr/bin/env Rscript

# Local-only updater. No API keys, package installation, or other data sources.

parse_scholar_metrics <- function(doc) {
  page_text <- rvest::html_text(doc)
  block_elements <- rvest::html_elements(
    doc, 'form[action*="sorry"], #captcha, #recaptcha, .g-recaptcha'
  )
  if (length(block_elements) > 0L || grepl(
    "unusual traffic|automated queries|not a robot|verify (that )?you are (a )?human",
    page_text, ignore.case = TRUE
  )) {
    stop("Google Scholar returned a CAPTCHA or block page.", call. = FALSE)
  }

  values <- trimws(rvest::html_text(rvest::html_elements(doc, ".gsc_rsb_std")))
  if (length(values) < 3L) {
    stop("Expected at least three .gsc_rsb_std values on the Scholar page.", call. = FALSE)
  }
  # Accept whole counts, including correctly grouped thousands separators.
  if (!all(grepl("^([0-9]+|[0-9]{1,3}(,[0-9]{3})+)$", values[c(1L, 3L)]))) {
    stop("Scholar citations and h-index must be non-negative whole numbers.", call. = FALSE)
  }
  stats <- suppressWarnings(as.integer(gsub(",", "", values, fixed = TRUE)))
  citations <- stats[1L]
  h_index <- stats[3L]
  if (anyNA(c(citations, h_index)) || citations < 0L || h_index < 0L) {
    stop("Scholar citations or h-index are outside the supported integer range.", call. = FALSE)
  }
  list(
    citations = citations,
    h_index = h_index,
    updated_at = as.character(Sys.Date())
  )
}

fetch_scholar_metrics <- function() {
  previous_options <- options(
    HTTPUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
  )
  on.exit(options(previous_options), add = TRUE)
  scholar_url <- "https://scholar.google.com/citations?user=IAWEh-4AAAAJ&hl=en"
  request_warnings <- character()
  doc <- tryCatch(
    withCallingHandlers(
      rvest::read_html(scholar_url),
      warning = function(warning) {
        request_warnings <<- c(request_warnings, conditionMessage(warning))
        invokeRestart("muffleWarning")
      }
    ),
    error = function(error) {
      detail <- paste(unique(c(request_warnings, conditionMessage(error))), collapse = " | ")
      stop("Google Scholar retrieval failed: ", detail, call. = FALSE)
    }
  )
  parse_scholar_metrics(doc)
}

write_scholar_atomic <- function(metrics, output_path) {
  output_dir <- dirname(output_path)
  if (!dir.exists(output_dir) && !dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)) {
    stop("Could not create the citation data directory.", call. = FALSE)
  }
  # Same-directory rename replaces the target without deleting good data first.
  temporary_path <- tempfile(pattern = ".scholar-", tmpdir = output_dir, fileext = ".json")
  on.exit(unlink(temporary_path), add = TRUE)
  jsonlite::write_json(metrics, temporary_path, auto_unbox = TRUE, pretty = TRUE)
  if (!file.rename(temporary_path, output_path)) {
    stop("Could not replace scholar.json; existing data was retained.", call. = FALSE)
  }
}

update_scholar_local <- function(output_path) {
  for (package in c("rvest", "jsonlite")) {
    if (!requireNamespace(package, quietly = TRUE)) {
      stop("Required R package is not installed: ", package, call. = FALSE)
    }
  }
  metrics <- fetch_scholar_metrics()
  write_scholar_atomic(metrics, output_path)
  message(sprintf(
    "Scholar update succeeded: citations=%d, h_index=%d, updated_at=%s",
    metrics$citations, metrics$h_index, metrics$updated_at
  ))
  message("Wrote: ", normalizePath(output_path, winslash = "/", mustWork = TRUE))
  invisible(metrics)
}

if (sys.nframe() == 0L) {
  tryCatch({
    script_argument <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
    if (length(script_argument) != 1L) {
      stop("Run this script using Rscript.", call. = FALSE)
    }
    script_path <- normalizePath(sub("^--file=", "", script_argument), mustWork = TRUE)
    output_path <- file.path(dirname(dirname(script_path)), "data", "citations", "scholar.json")
    update_scholar_local(output_path)
  }, error = function(error) {
    message("Scholar update failed: ", conditionMessage(error))
    quit(save = "no", status = 1L)
  })
}
