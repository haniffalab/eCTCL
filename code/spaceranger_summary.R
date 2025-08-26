#!/usr/bin/env R

# ------------------------------------------------------------------------------
# title: Summarise and visualise aggregated Ranger metrics.
#
# created: 2024-12-06 Fri 10:17:38 GMT
# updated: 2025-01-15
# version: 0.0.9
# status: Prototype
# project: Cutaneous T-cell Lymphoma (CTCL)
#
# maintainer: Ciro Ramírez-Suástegui
# author:
#   - name: Ciro Ramírez-Suástegui
#     affiliation: The Wellcome Sanger Institute
#     email: cs59@sanger.ac.uk, cramsuig@gmail.com
# ------------------------------------------------------------------------------
# Exectute:
# TEMP="/nfs/t298_imaging/0XeniumExports/20241115__150035__SGP206_run1\
# ,data/20240815__115640__SGP177_SKI_run1"
# Rscript code/spaceranger_summary.R --input ${TEMP}

## Environment setup ## @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Quick installations --------------------------------------
source("code/utils.R")
# Basic packages -------------------------------------------
# Logging configuration ------------------------------------
logging::basicConfig()
logger <- function(i, tail_n = 60, color = crayon::cyan) {
  tail_n <- max(c(tail_n, nchar(i) + 1))
  y <- paste("##", color(i), "##", base::strrep("%", tail_n - nchar(i)), "\n")
  logging::loginfo(y)
}

# https://pakillo.github.io/grateful/index.html

# In-house/developing --------------------------------------
plot_heatmap <- function(x_matrix) {
  x_matrix %>%
    dplyr::as_tibble() %>%
    dplyr::mutate(COMPARE = rownames(x_matrix)) %>%
    tidyr::pivot_longer(-COMPARE, names_to = "QUERY", values_to = "value") %>%
    dplyr::filter(!is.na(value)) %>%
    dplyr::mutate(
      COMPARE = factor(COMPARE, levels = colnames(x_matrix)),
      QUERY = factor(QUERY, levels = colnames(x_matrix))
    ) %>%
    ggplot2::ggplot(mapping = ggplot2::aes(x = QUERY, y = COMPARE)) +
    ggplot2::geom_tile(mapping = ggplot2::aes(fill = value)) +
    ggplot2::geom_text(
      mapping = ggplot2::aes(label = gsub("^0", "", round(value, 2))),
      color = "black", size = 3,
      position = ggplot2::position_nudge(y = 0.25)
    ) +
    ggplot2::geom_text(mapping = ggplot2::aes(label = gsub("^0", "", round(value, 2)))) +
    ggplot2::scale_fill_gradient(low = "white", high = "red") +
    ggplot2::theme_minimal() +
    ggplot2::theme(
      axis.text.x = ggplot2::element_text(angle = 90, hjust = 1),
      axis.title = ggplot2::element_blank(),
      legend.title = ggplot2::element_blank()
    )
}
# Tool (packaged) modules ----------------------------------
# optparse, tidyverse (ggplot2, dplyr, stringr (glue), readr)

# Fetching OPT arguments # ---------------------------------
option_list <- list(
  optparse::make_option(c("-n", "--name"),
    type = "character",
    default = "ranger",
    help = "Name of the output folder."
  ),
  optparse::make_option(c("-d", "--input"),
    type = "character",
    help = "Input path(s) of Ranger output."
  ),
  optparse::make_option(c("-v", "--verbose"),
    type = "integer", default = 0,
    help = "Verbosity level (0=quiet, 1=verbose, 2=debug)."
  )
)
opt <- optparse::parse_args(optparse::OptionParser(option_list = option_list))

## Global variables and paths ## @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%
temp <- "Summarising Ranger metrics..."
logging::loginfo(crayon::bold(crayon::red(temp)))

# Setting up variables # -----------------------------------
glue <- stringr::str_glue
indata_name <- opt$name
action_name <- "metrics-summary"
result_name <- sprintf(
  "%s_%s_%s", indata_name, action_name, format(Sys.time(), "%Y%m%d")
)

inputs_path <- "./data"
inputs_file <- unlist(stringr::str_split(opt$input, ","))
output_resu <- file.path("./results", glue("{result_name}"))
outputs_list <- list()

# show variables so far
temp <- sapply(ls(), function(x) class(get(x))) %in% c("list", "character")
temp <- ls()[temp & !grepl("opt|^temp$", ls())]
str(sapply(temp, function(x) get(x)))

## Loading data ## @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%
# List folders and filter for samples of interest
`%>%` <- dplyr::`%>%`
metrics_files <- inputs_file %>%
  list.dirs(recursive = FALSE) %>%
  # stringr::str_subset("0032785|FFPE") %>%
  list.files(pattern = "metrics_summary.csv", full.names = TRUE)

panel_files <- inputs_file %>%
  list.dirs(recursive = FALSE) %>%
  # stringr::str_subset("0032785|FFPE") %>%
  list.files(pattern = "gene_panel.json", full.names = TRUE)

# reading json files
metrics_df <- metrics_files %>% readr::read_csv()
panel_info <- panel_files %>% purrr::map(jsonlite::fromJSON)

## Pre-processing ## @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%
# remove columns with all NAs
metrics_df <- metrics_df %>% dplyr::select(-dplyr::where(~ all(is.na(.))))
outputs_list[["table"]] <- metrics_df

## Main ## @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%
# Plotting numeric metrics
temp <- sapply(metrics_df, function(x) is.numeric(x) || is.integer(x))
plot_columns <- colnames(metrics_df)[temp]
# divide by target genes (panel size)
panel_size <- sapply(panel_info, function(x) x$payload$panel$num_gene_targets )
for (i in plot_columns) {
  if (grepl("gene|transcript", i)) {
    cat(glue("Normalising '{i}' by panel size\n\n"))
    metrics_df[[glue("{i}_by_panel_size")]] <- metrics_df[[i]] / panel_size
  }
}

# also grabbing the normalised columns
temp <- grep("_by_panel_size", colnames(metrics_df), value = TRUE)
plot_columns <- unique(c(plot_columns, temp))

# Plotting bar plots for each metric
for (col in plot_columns) {
  temp <- gsub("_", "-", col)
  fname <- glue("barplot_{temp}")
  # creating bar plots
  plot_aes <- ggplot2::aes(x = region_name, y = !!rlang::sym(col))
  outputs_list[[fname]] <- ggplot2::ggplot(
    data = metrics_df, mapping = plot_aes
  ) +
    ggplot2::geom_bar(stat = "identity") +
    ggplot2::facet_wrap(facets = ~run_name + panel_name, scale = "free_x") +
    ggplot2::theme_minimal() +
    ggplot2::theme(
      axis.text.x = ggplot2::element_text(vjust = 0.5, angle = 90)
    )
}

logger("Checkig overlap between panels")
n_targets <- max(sapply(
  panel_info, function(x) x$payload$panel$num_gene_targets
))
out_df <- sapply(panel_info, function(x) {
  x$payload$targets$type$data$id[1:n_targets]
}) %>% as.data.frame()
colnames(out_df) <- metrics_df$region_name
temp <- c(colnames(out_df)) # , "All"
overlaps_comb <- matrix(nrow = length(temp), ncol = length(temp))
dimnames(overlaps_comb) <- list(temp, temp)
overlaps_comb_pct <- overlaps_comb
for (i in seq_len(ncol(out_df))) {
  for (j in seq_len(ncol(overlaps_comb))) {
    if (i == j) next
    i_values <- out_df[, i][!is.na(out_df[, i])]
    if (j == ncol(overlaps_comb)) {
      j_values <- unique(unlist(out_df[, -i][!is.na(out_df[, -i])]))
    } else {
      j_values <- out_df[, j][!is.na(out_df[, j])]
    }
    overlaps_comb_pct[i, j] <- sum(i_values %in% j_values) / length(i_values)
    overlaps_comb[i, j] <- intersect(i_values, j_values) %>% length()
  }
}

panel_intersection <- intersect(out_df[, 1], out_df[, ncol(out_df)])
temp <- !panel_info[[1]]$payload$targets$type$data$id %in% panel_intersection
head(panel_info[[1]]$payload$targets$type$data[temp, 2])

outputs_list[["overlap"]] <- plot_heatmap(overlaps_comb)
outputs_list[["overlap-percentages"]] <- plot_heatmap(overlaps_comb_pct)

## Conclusions ## @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
temp <- paste0(names(outputs_list), collapse = "\n")
logging::loginfo(glue("Produced files:\n{temp}"))
outputs_list <- outputs_list[!grepl("testplot", names(outputs_list))]

## Save ## @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%
temp <- length(outputs_list)
logging::loginfo(glue("Saving {temp} files"))
pflag <- " \033[1;32m√\033[0m"
ftype <- "unknown"
for (name_i in names(outputs_list)) {
  item <- outputs_list[[name_i]]
  fname <- file.path(output_resu, glue("{name_i}"))
  eflag <- " \033[1;31mX\033[0m"
  if (is.null(class(item))) next
  if (ftype != paste0(class(item), collapse = "/")) {
    ftype <- paste0(class(item), collapse = "/")
  }
  cat(glue("Storing {ftype}\n{fname}"))
  # create directory if it does not exist
  if (!dir.exists(dirname(fname))) {
    dir.create(dirname(fname), recursive = TRUE)
  }
  # add extension and save based on class() # ----------------
  if (any(class(item) %in% c("gg", "ggplot", "spec_tbl_df"))) {
    suppressMessages(ggplot2::ggsave(
      filename = paste0(fname, ".pdf"),
      plot = outputs_list[[name_i]],
      width = 10, height = 10
    ))
    eflag <- pflag
  } else if (any(class(item) %in% c("data.frame"))) {
    readr::write_csv(outputs_list[[name_i]], paste0(fname, ".csv"))
    eflag <- pflag
  } else if (any(class(item) %in% c("list"))) {
    eflag <- pflag
    saveRDS(outputs_list[[name_i]], paste0(fname, ".rds"))
  }
  print(glue("{eflag}"))
}

logging::loginfo(crayon::bold(crayon::red("Done.")))
