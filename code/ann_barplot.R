#!/usr/bin/env Rscript

# ------------------------------------------------------------------------------
# purpose: Given a, or a list of, CSV file(s), plot some nice barplots.
# created: 2025-10-14 Tue 00:05:19 BST
# updated: 2025-10-14
# author:
#   - name: Ciro Ramírez-Suástegui
#     affiliation: The Wellcome Sanger Institute
#     email: cs59@sanger.ac.uk, cramsuig@gmail.com
# ------------------------------------------------------------------------------

parse_args_ <- function() {
  option_list <- list(
    optparse::make_option(c("-i", "--input"),
      type = "character",
      help = "Input path."
    ),
    optparse::make_option(c("-o", "--output"),
      type = "character",
      help = "Output path."
    ),
    optparse::make_option(c("-g", "--group"),
      type = "character", default = "study_id,donor_id,donor_id",
      help = "Comma-separated grouping variables: facet_var,x_var,x_order."
    ),
    optparse::make_option(c("-c", "--colors"),
      type = "character", default = NULL,
      help = "Path to CSV file with 'color,annotation'."
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

source_require(c(
  "ggplot2",
  "code/logger.R", # logger_info
  # output_save_*, show_variables, input_fetch_path, output_fetch_path
  "code/utils.R",
  "code/plotting.R" # plot_bars, theme_global
))

ann_composition_bar <- function(
  args,
  ...
) {
  glue <- stringr::str_glue
  `%>%` <<- dplyr::`%>%`
  ## Variables ## --------------------------------------------------------------
  args <- c(args, list(...))
  input_files <- input_fetch_path(
    args$input, pattern = "ann.*csv$",
    full.names = TRUE, verbose = args$verbose
  )
  output_path <- output_fetch_path(args$output, input_files)
  args_groups <- unlist(strsplit(args$group, ",")) # 2 should be a subset of 1
  output_list <- list()

  show_variables()

  ## Loading data ## -----------------------------------------------------------
  temp <- paste("", paste(input_files, collapse = "\n "))
  logger_info(glue("Loading data from:\n {temp}"))
  start <- Sys.time()
  data_df <- lapply(
    X = input_files,
    FUN = readr::read_csv
  ) %>% dplyr::bind_rows()
  temp <- format(difftime(Sys.time(), start, unit = "min"))
  logger_info(paste("Elapsed:", temp))

  ## Preprocessing ## ----------------------------------------------------------
  apply(X = combn(args_groups, 2), MARGIN = 2, FUN = function(temp) {
    y <- table(data_df[[temp[1]]], data_df[[temp[2]]]) %>%
      reshape2::melt() %>%
      dplyr::filter(value > 0) %>%
      dplyr::arrange(!!rlang::sym("Var2"))
    y$combn <- paste(temp, collapse = "~")
    y
  }) %>% dplyr::bind_rows() %>% knitr::kable(x = ., format = "simple") %>% print

  ## Main code ## --------------------------------------------------------------
  obs_keys <- grep(
    pattern = "ann_|cell_type$|majority_voting",
    x = colnames(data_df), value = TRUE
  )
  for (obs_i in obs_keys) {
    if (obs_i == args_groups[2]) next
    pp <- plot_bars(
      data = data_df,
      x_var = args_groups[2], fill_var = obs_i,
      facet_var = args_groups[1], fill_color = args$colors
    )
    output_list[[names(pp[1])]] <- pp[[1]]
    temp <- order(data_df[[args_groups[3]]])
    pp <- plot_bars(
      data = data_df,
      x_var = args_groups[2], fill_var = obs_i,
      x_order = unname(unlist(unique(data_df[temp, args_groups[2]]))),
      facet_var = args_groups[3],
      x_labels = c(args_groups[2], args_groups[1]),
      fill_color = args$colors
    )
    output_list[[names(pp[1])]] <- pp[[1]]
  }

  ## Saving ## -----------------------------------------------------------------
  do.call(
    output_save_list,
    c(list(
      OUTPUT_LIST = output_list[grepl("barplot", names(output_list))],
      OUTPUT_RESU = output_path,
      width = 5.7 * 4, height = 4.3 * 2,
      unit = "cm"
    ), theme_global()$args_ggsave)
  )
}

# source("code/ann_barplot.R")
if (identical(environment(), globalenv()) && !interactive()) {
  args <- parse_args_()
  if (interactive()) {
    args$input <- "results/panels-10x_overlaps"
    args$output <- "results/composition/spatial/"
    args$group <- "panel_type,sample_short,donor_id"
    args$colors <- "data/metadata/ruoyan_2024_suspension_cell_type_colour.csv"
  }

  logging::loginfo("Starting ann_composition_bar.")
  ann_composition_bar(args)
  logging::loginfo("Run completed successfully.")
}