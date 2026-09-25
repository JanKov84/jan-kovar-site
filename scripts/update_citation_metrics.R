#!/usr/bin/env Rscript

# Test-only citation metrics updater. It writes a small JSON artifact and does
# not modify Hugo content or templates.

suppressPackageStartupMessages({
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("Missing dependency: jsonlite. Install dependencies in the workflow before running this script.")
  }
})

researcher_id <- "AAJ-5694-2020"
output_path <- Sys.getenv("CITATION_METRICS_OUTPUT", unset = "citation-metrics.json")

today <- format(Sys.Date(), "%Y-%m-%d")

h_index <- function(citations) {
  citations <- sort(as.numeric(citations), decreasing = TRUE)
  citations <- citations[is.finite(citations) & citations >= 0]
  if (!length(citations)) return(0L)
  as.integer(max(c(0L, which(citations >= seq_along(citations)))))
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
wos <- fetch_wos()
if (!is.null(wos)) metrics$wos <- wos

output_dir <- dirname(output_path)
if (!identical(output_dir, ".") && !dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
}
jsonlite::write_json(metrics, output_path, auto_unbox = TRUE, pretty = TRUE)
message("Wrote citation metrics JSON to ", normalizePath(output_path, mustWork = FALSE))
