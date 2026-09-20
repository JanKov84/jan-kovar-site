#!/usr/bin/env Rscript

# Test-only citation metrics updater. It writes a small JSON artifact and does
# not modify Hugo content or templates.

suppressPackageStartupMessages({
  if (!requireNamespace("rvest", quietly = TRUE)) {
    stop("Missing dependency: rvest. Install dependencies in the workflow before running this script.")
  }
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("Missing dependency: jsonlite. Install dependencies in the workflow before running this script.")
  }
})

scholar_url <- "https://scholar.google.com/citations?user=IAWEh-4AAAAJ&hl=en"
researcher_id <- "AAJ-5694-2020"
output_path <- Sys.getenv("CITATION_METRICS_OUTPUT", unset = "citation-metrics.json")

today <- format(Sys.Date(), "%Y-%m-%d")

parse_count <- function(value) {
  value <- gsub("[^0-9]", "", as.character(value))
  if (!nzchar(value)) return(NA_real_)
  as.numeric(value)
}

h_index <- function(citations) {
  citations <- sort(as.numeric(citations), decreasing = TRUE)
  citations <- citations[is.finite(citations) & citations >= 0]
  if (!length(citations)) return(0L)
  as.integer(max(c(0L, which(citations >= seq_along(citations)))))
}

fetch_scholar <- function() {
  message("Fetching Google Scholar metrics...")
  result <- tryCatch({
    options(HTTPUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
    page <- tryCatch(
      rvest::read_html(scholar_url),
      error = function(error) stop("Google Scholar HTTP request failed: ", conditionMessage(error))
    )
    text <- paste(rvest::html_text2(page), collapse = " ")
    if (grepl("captcha|unusual traffic|not a robot|sorry", text, ignore.case = TRUE)) {
      stop("Google Scholar returned a bot-check or CAPTCHA page.")
    }
    stats <- rvest::html_elements(page, css = ".gsc_rsb_std")
    values <- rvest::html_text2(stats)
    if (length(values) < 2L) {
      stop("Google Scholar statistics selectors were not found.")
    }
    citations <- parse_count(values[[1L]])
    h <- parse_count(values[[2L]])
    if (!is.finite(citations) || !is.finite(h)) {
      stop("Google Scholar statistics were present but not numeric.")
    }
    list(citations = as.integer(citations), h_index = as.integer(h), updated_at = today)
  }, error = function(error) {
    message("Scholar fetch skipped: ", conditionMessage(error))
    NULL
  })
  result
}

fetch_wos <- function() {
  key <- Sys.getenv("WOS_STARTER_KEY", unset = "")
  if (!nzchar(trimws(key))) {
    message("WoS fetch skipped: WOS_STARTER_KEY is not set.")
    return(NULL)
  }
  if (!requireNamespace("rwosstarter", quietly = TRUE)) {
    message("WoS fetch skipped: missing dependency rwosstarter.")
    return(NULL)
  }
  message("Fetching Web of Science metrics for ResearcherID ", researcher_id, "...")
  tryCatch({
    query <- sprintf('AI=("%s")', researcher_id)
    records <- rwosstarter::wos_get_records(
      query,
      database = "WOS",
      limit = NULL,
      sleep = 1
    )
    if (!is.data.frame(records) || !"citations" %in% names(records)) {
      stop("WoS response did not contain a citations column.")
    }
    citations <- suppressWarnings(as.numeric(gsub("[^0-9.-]", "", as.character(records$citations))))
    if (!length(citations) || any(!is.finite(citations)) || any(citations < 0)) {
      stop("WoS response contained missing or non-numeric citation counts.")
    }
    list(
      citations = as.integer(sum(citations)),
      h_index = h_index(citations),
      updated_at = today
    )
  }, error = function(error) {
    safe_message <- gsub(key, "[REDACTED]", conditionMessage(error), fixed = TRUE)
    message("WoS fetch failed: ", safe_message)
    NULL
  })
}

metrics <- list()
scholar <- fetch_scholar()
if (!is.null(scholar)) metrics$scholar <- scholar
wos <- fetch_wos()
if (!is.null(wos)) metrics$wos <- wos

output_dir <- dirname(output_path)
if (!identical(output_dir, ".") && !dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
}
jsonlite::write_json(metrics, output_path, auto_unbox = TRUE, pretty = TRUE)
message("Wrote citation metrics JSON to ", normalizePath(output_path, mustWork = FALSE))
