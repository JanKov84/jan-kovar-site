#!/usr/bin/env Rscript

# Manual GitHub-side WoS updater. It writes only data/citations/wos.json.

researcher_id <- "AAJ-5694-2020"

h_index <- function(citations) {
  sorted <- sort(as.numeric(citations), decreasing = TRUE)
  qualifying <- which(sorted >= seq_along(sorted))
  if (!length(qualifying)) return(0L)
  as.integer(max(qualifying))
}

validate_wos_metrics <- function(metrics) {
  expected_names <- c("citations", "h_index", "updated_at")
  if (!is.list(metrics) || !identical(names(metrics), expected_names)) {
    stop("WoS metrics did not match the required JSON fields.", call. = FALSE)
  }

  for (field in c("citations", "h_index")) {
    value <- metrics[[field]]
    if (!is.numeric(value) || length(value) != 1L || !is.finite(value) ||
        value < 0 || value != floor(value) || value > .Machine$integer.max) {
      stop("WoS metrics contained an invalid non-negative integer.", call. = FALSE)
    }
  }

  updated_at <- metrics$updated_at
  if (!is.character(updated_at) || length(updated_at) != 1L ||
      !grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", updated_at)) {
    stop("WoS metrics contained an invalid updated_at date.", call. = FALSE)
  }
  parsed_date <- suppressWarnings(as.Date(updated_at, format = "%Y-%m-%d"))
  if (is.na(parsed_date) || format(parsed_date, "%Y-%m-%d") != updated_at) {
    stop("WoS metrics contained an invalid updated_at date.", call. = FALSE)
  }

  invisible(metrics)
}

fetch_wos_metrics <- function() {
  if (!nzchar(trimws(Sys.getenv("WOS_STARTER_KEY", unset = "")))) {
    stop("WOS_STARTER_KEY is not set; existing wos.json was preserved.", call. = FALSE)
  }
  if (!requireNamespace("rwosstarter", quietly = TRUE)) {
    stop("Required R package rwosstarter is not installed; existing wos.json was preserved.", call. = FALSE)
  }

  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("Required R package jsonlite is not installed; existing wos.json was preserved.", call. = FALSE)
  }

  message("Fetching Web of Science records for ResearcherID ", researcher_id, "...")
  query <- sprintf('AI=("%s")', researcher_id)
  request_failed <- FALSE
  records <- tryCatch({
    response <- NULL
    # Keep package output and diagnostics out of the Actions log; they may
    # include request details. Only generic errors are reported below.
    invisible(utils::capture.output(
      response <- withCallingHandlers(
        rwosstarter::wos_get_records(
          query,
          database = "WOS",
          limit = NULL,
          sleep = 1
        ),
        message = function(message) invokeRestart("muffleMessage"),
        warning = function(warning) invokeRestart("muffleWarning")
      )
    ))
    response
  }, error = function(error) {
    request_failed <<- TRUE
    NULL
  })
  if (request_failed) {
    stop("WoS API retrieval failed; existing wos.json was preserved.", call. = FALSE)
  }

  if (!is.data.frame(records) || nrow(records) < 1L || !"citations" %in% names(records)) {
    stop("WoS API returned no usable records; existing wos.json was preserved.", call. = FALSE)
  }

  citation_text <- gsub(",", "", trimws(as.character(records$citations)), fixed = TRUE)
  if (!length(citation_text) || any(!grepl("^[0-9]+$", citation_text))) {
    stop("WoS API returned invalid citation counts; existing wos.json was preserved.", call. = FALSE)
  }
  citations <- suppressWarnings(as.numeric(citation_text))
  if (any(!is.finite(citations)) || any(citations < 0) || any(citations != floor(citations))) {
    stop("WoS API returned invalid citation counts; existing wos.json was preserved.", call. = FALSE)
  }

  total_citations <- sum(citations)
  if (!is.finite(total_citations) || total_citations < 0 ||
      total_citations != floor(total_citations) || total_citations > .Machine$integer.max) {
    stop("WoS API returned an invalid total citation count; existing wos.json was preserved.", call. = FALSE)
  }
  record_h_index <- h_index(citations)
  metrics <- list(
    citations = as.integer(total_citations),
    h_index = record_h_index,
    updated_at = format(Sys.Date(), "%Y-%m-%d")
  )
  validate_wos_metrics(metrics)
  metrics
}

write_wos_atomic <- function(metrics, output_path) {
  validate_wos_metrics(metrics)
  output_dir <- dirname(output_path)
  if (!dir.exists(output_dir) &&
      !dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)) {
    stop("Could not create the citation data directory; existing wos.json was preserved.", call. = FALSE)
  }

  temporary_path <- tempfile(pattern = ".wos-", tmpdir = output_dir, fileext = ".json")
  on.exit(unlink(temporary_path), add = TRUE)

  write_failed <- FALSE
  tryCatch({
    jsonlite::write_json(metrics, temporary_path, auto_unbox = TRUE, pretty = TRUE)
    serialized <- jsonlite::fromJSON(temporary_path, simplifyVector = FALSE)
    validate_wos_metrics(serialized)
  }, error = function(error) {
    write_failed <<- TRUE
  })
  if (write_failed) {
    stop("Could not write and validate temporary WoS JSON; existing wos.json was preserved.", call. = FALSE)
  }

  if (!file.rename(temporary_path, output_path)) {
    stop("Could not atomically replace wos.json; existing data was preserved.", call. = FALSE)
  }
}

run_wos_update <- function() {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("Required R package jsonlite is not installed; existing wos.json was preserved.", call. = FALSE)
  }
  script_argument <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(script_argument) != 1L) {
    stop("Run this script using Rscript; existing wos.json was preserved.", call. = FALSE)
  }
  script_path <- normalizePath(sub("^--file=", "", script_argument), mustWork = TRUE)
  repository_root <- dirname(dirname(script_path))
  output_path <- file.path(repository_root, "data", "citations", "wos.json")

  metrics <- fetch_wos_metrics()
  write_wos_atomic(metrics, output_path)
  message(sprintf(
    "WoS update succeeded: citations=%d, h_index=%d, updated_at=%s",
    metrics$citations, metrics$h_index, metrics$updated_at
  ))
  message("Wrote: ", normalizePath(output_path, winslash = "/", mustWork = TRUE))
  invisible(metrics)
}

if (sys.nframe() == 0L) {
  tryCatch({
    run_wos_update()
  }, error = function(error) {
    message("WoS update failed: ", conditionMessage(error))
    quit(save = "no", status = 1L)
  })
}
