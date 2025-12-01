#!/usr/bin/env R

# ------------------------------------------------------------------------------
# created: 2024-12-06 Fri 15:25:00 GMT
# updated: 2025-10-09
# version: 0.0.9
# status: Prototype
#
# maintainer: Ciro Ramírez-Suástegui
# author:
#   - name: Ciro Ramírez-Suástegui
#     affiliation: The Wellcome Sanger Institute
#     email: cs59@sanger.ac.uk, cramsuig@gmail.com
# ------------------------------------------------------------------------------

packages <- c(
  "optparse",
  "logging",
  "eulerr",
  "UpSetR"
)
for (pkg in packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg, repos = "https://cloud.r-project.org")
  }
}

output_save_class <- function(
  item, filename,
  flag_success = " \033[1;32m√\033[0m",
  flag_out = " \033[1;31mX\033[0m",
  verbose = 0,
  overwrite = TRUE,
  ...
) {
  kwargs <- list(...)
  # pick the first recognized class
  cls <- class(item)
  cls_possible <- c("gg", "ggplot", "spec_tbl_df", "data.frame", "list")
  cls_match <- cls[cls %in% cls_possible][1]
  # choose extension based on class
  device_name <- if (is.null(kwargs$device)) ".png" else ""
  is_complex <- FALSE
  if ("do.call" %in% names(item)) {
    is_complex <- TRUE
    if ("type" %in% names(item)) device_name <- item$type
  }
  filenamex <- switch(
    cls_match,
    "gg"           = device_name,
    "ggplot"       = device_name,
    "spec_tbl_df"  = ".csv",
    "data.frame"   = ".csv",
    "list"         = if (is_complex) device_name else ".rds",
    paste0(filename, ".out")  # default fallback
  )
  if (verbose > 0) cat(filenamex)
  filenamex <- paste0(filename, filenamex)
  if (file.exists(filenamex) && !overwrite) {
    warning(glue::glue("File '{filenamex}' exists, skipping"))
    return(" \033[1;34mX\033[0m")
  }

  if (cls_match %in% c("gg", "ggplot")) {
    suppressMessages(ggplot2::ggsave(filename = filenamex, plot = item, ...))
    flag_out <- flag_success
  } else if (cls_match %in% c("spec_tbl_df", "data.frame")) {
    # progress leaves carriage return
    readr::write_csv(item, filenamex, progress = FALSE)
    flag_out <- flag_success
  } else if (cls_match %in% c("list") && is_complex) {
    device_fun <- switch(
      device_name,
      ".png"  = grDevices::png,
      ".pdf"  = grDevices::pdf,
      ".svg"  = grDevices::svg,
      ".jpeg" = grDevices::jpeg,
      ".jpg"  = grDevices::jpeg,
      "none"
    )
    if (class(device_fun) == "function") {
      device_fun(filenamex, res = 300, ...)
    }
    do.call(
      what = item$`do.call`$what,
      c(item$`do.call`$args)
    )
    graphics.off()
    flag_out <- flag_success
  } else if (cls_match %in% c("list")) {
    saveRDS(item, filenamex)
    flag_out <- flag_success
  }
  return(flag_out)
}

output_save_list <- function(
  OUTPUT_LIST = list(),
  OUTPUT_RESU = "./results/",
  verbose = 1,
  ...
) {
  glue <- stringr::str_glue
  temp <- length(OUTPUT_LIST)
  logging::loginfo(glue("Saving {temp} files"))
  ftype <- "unknown"
  for (name_i in names(OUTPUT_LIST)) {
    item <- OUTPUT_LIST[[name_i]]
    if (grepl("^_", name_i)) {
      filename <- glue("{OUTPUT_RESU}{name_i}")
    } else {
      filename <- file.path(OUTPUT_RESU, glue("{name_i}"))
    }
    # create directory if it does not exist
    if (!dir.exists(dirname(filename))) {
      dir.create(dirname(filename), recursive = TRUE)
    }
    if (is.null(class(item))) next
    if (ftype != paste0(class(item), collapse = "/")) {
      ftype <- paste0(class(item), collapse = "/")
    }
    logging::loginfo(glue("Storing {ftype}"))
    if (verbose > 0) cat(glue("'{filename}'"))
    # add extension and save based on class() # ----------------
    eflag <- output_save_class(
      item = item, filename = filename, verbose = verbose, ...
    )
    if (verbose > 0) cat(glue("{eflag}\n\n"))
  }
}

show_variables <- function() {
  ls_ <- ls(globalenv())
  logger_whos <- sapply(X = ls_, FUN = function(x) class(get(x)))
  logger_whos <- logger_whos %in% c("list", "character")
  logger_whos <- ls_[logger_whos & !grepl("logger_whos|_df|opt", ls_)]
  str(sapply(logger_whos, function(x) get(x)), max.level = 2, vec.len = 2)
}

input_fetch_path <- function(path_file, exclude = NULL, verbose = 0, ...) {
  if (verbose > 1) cat(glue::glue("Fetching input files from: {path_file}\n\n"))
  if (file.exists(path_file) && !dir.exists(path_file)) {
    if (verbose > 1) cat("Path is to file. Returning.\n")
    return(path_file)
  }
  if (dir.exists(path_file)) {
    if (verbose > 1) cat("Using list.files().\n")
    input_files <- list.files(path = path_file, ...)
  }
  if (grepl(",", path_file)) {
    temp <- unlist(strsplit(path_file, ","))
    if (verbose > 1) cat("Found multiple input paths:\n")
    input_files <- sapply(temp, input_fetch_path, verbose = verbose, ...)
  }
  # remove names, duplicates, and excluded patterns
  input_files <- unique(unlist(input_files))
  if (!is.null(exclude)) {
    input_files <- input_files[!grepl(exclude, input_files)]
  }
  if (verbose > 1) {
    cat(glue::glue("Found {length(input_files)} input(s).\n\n"))
    print(input_files)
  }
  input_files
}

output_fetch_path <- function(args_out, args_input = NULL) {
  if (length(args_input) == 0 && is.null(args_out)) {
    stop("Input path needs to be provided if output is NULL")
  }
  if (!is.null(args_out)) if (grepl("\\/$", args_out)) return(args_out)
  output_name <- tools::file_path_sans_ext(basename(args_input))
  temp <- c("annotated", "ann", "ctcl", "merged")
  pattern_remove <- sapply(temp, function(x) {
    paste0("[_]?", x, "[_]?")
  }) %>% paste(collapse = "|")
  output_name <- gsub(pattern_remove, "", output_name)
  output_name <- paste(output_name, collapse = "_")
  output_path <- if (is.null(args_out)) dirname(args_input[1]) else args_out
  file.path(output_path, output_name)
}