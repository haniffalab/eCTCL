#!/usr/bin/env R

parse_args_ <- function() {
  option_list <- list(
    optparse::make_option(c("-i", "--input"),
      type = "character",
      help = "Input path."
    ),
    optparse::make_option(c("-o", "--output"),
      type = "character",
      help = "Output path. Default: same as input path."
    ),
    optparse::make_option(c("-v", "--verbose"),
      type = "integer", default = 0,
      help = "Verbosity level (0=quiet, 1=verbose, 2=debug)."
    )
  )
  optparse::parse_args(optparse::OptionParser(option_list = option_list))
}

source_require <- function(packages) {
  for (pkg in packages) {
    if (file.exists(pkg)) {
      source(pkg)
    } else {
      suppressPackageStartupMessages(library(pkg, character.only = TRUE))
    }
  }
}

panel_expression_comparison <- function(args, ...) {
  glue <- stringr::str_glue
  `%>%` <- dplyr::`%>%`

  ## Variables ## --------------------------------------------------------------
  args <- c(args, list(...))
  input_files <- args$input
  if (!file.exists(args$input)) {
    input_files <- list.files(
      path = args$input, pattern = "annotated.csv", full.names = TRUE
    )
  }
  output_name  <- tools::file_path_sans_ext(basename(args$input))
  output_path <- if (is.null(args$output)) dirname(args$input) else args$output
  output_path <- file.path(output_path, output_name, "plots")

  logger_whos <- sapply(X = ls(), FUN = function(x) class(get(x)) )
  logger_whos <- logger_whos %in% c("list", "character")
  logger_whos <- ls()[logger_whos & !grepl("logger_whos|_df|opt", ls())]
  str(sapply(logger_whos, function(x) get(x)), max.level = 2)

  ## Loading data ## -----------------------------------------------------------
  temp <- paste(" ", paste(input_files, collapse = "\n "))
  logging::loginfo(glue("Loading data from:\n {temp}"))
  start <- Sys.time()
  emdata_df <- readr::read_csv(input_files) %>% dplyr::bind_rows()
  temp <- format(difftime(Sys.time(), start, unit = "min"))
  logging::loginfo(paste("Elapsed:", temp))

  ## Main code ## --------------------------------------------------------------
  genes_v <- which(grepl("conf_score", colnames(emdata_df)))
  # Calculate mean expression per condition for each gene
  emdata_pivot_df <- emdata_df %>%
    dplyr::group_by(file_id) %>%
    dplyr::summarise(dplyr::across(
      .cols = colnames(emdata_df)[(genes_v + 1):ncol(emdata_df)],
      .fns = list(mean = ~ mean(.x, na.rm = TRUE)),
      .names = "{.col}_{.fn}"
    )) %>%
    tidyr::pivot_longer(
      cols = colnames(emdata_df)[(genes_v + 1):ncol(emdata_df)],
      names_to = "genes",
      values_to = "value"
    )

  logging::loginfo(glue("Running function_nested()"))
  for (i in stringr::str_split(args$labels, ",")) {
    logging::loginfo(glue("Barplots per: {i}"))
    plot_boxes(emdata_pivot_df, i)
  }

  ## Saving ## -----------------------------------------------------------------
  if (!dir.exists(output_path)) {
    dir.create(output_path, recursive = TRUE)
  }
  print(output_object)
  # readr::write_csv(output_object, glue("{output_path}.csv"))
}

plot_boxes <- function(data, group_var, x_var = "genes", y_var = "mean") {
  ggplot2::ggplot(
    data = data,
    mapping = ggplot2::aes_string(x = x_var, y = y_var, fill = group_var)
  ) +
    ggplot2::geom_boxplot() +
    ggplot2::labs(title = glue::glue("Boxplot of {y_var} by {group_var}"),
                  x = x_var, y = y_var) +
    ggplot2::theme_minimal()
}

if (identical(environment(), globalenv()) && !interactive()) {
  source_require(c("code/logger.R", "code/utils.R"))

  args <- parse_args_()

  logging::loginfo("Starting function_name.")
  panel_expression_comparison(args)
  logging::loginfo("Run completed successfully.")
}