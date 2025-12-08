#!/usr/bin/env R

# ------------------------------------------------------------------------------
# title: Summarise and visualise aggregated Ranger metrics.
#.       This one is done from the perspective of the Xenium Onboard
#.       Analysis (XOA) pipeline outputs.
#
# created: 2024-12-06 Fri 10:17:38 GMT
# updated: 2025-08-26
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
source("code/plotting.R")
`%>%` <- dplyr::`%>%`
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
    ggplot2::scale_fill_gradient(low = "white", high = "red") +
    theme_global()$theme +
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
  optparse::make_option(c("-i", "--include"),
    type = "character", default = NULL,
    help = "Pattern to include."
  ),
  optparse::make_option(c("-e", "--exclude"),
    type = "character", default = NULL,
    help = "Pattern to exclude."
  ),
  optparse::make_option(c("-v", "--verbose"),
    type = "integer", default = 0,
    help = "Verbosity level (0=quiet, 1=verbose, 2=debug)."
  )
)
opt <- optparse::parse_args(optparse::OptionParser(option_list = option_list))

opt$input <- paste0(
  "/nfs/t298_imaging/0XeniumExports/",
  c(
    "20250210_SGP219_5K_DERMATLAS",
    "20250404_SGP238_5K_DERMATLAS",
    "20250602_SGP247_5K_DERMATLAS",
    "20250610_SGP245_5K_DERMATLAS",
    "20241010_SGP194_5K_BEACON",
    "20240628_KR_5K_BEACON_run1",
    "20250227_SGP218_5K_BCN+CTCL_FFPE/BEACON_FFPE",
    "20250227_SGP218_5K_BCN+CTCL_FFPE/CTCL_FFPE",
    "20250724_SGP273_5K_earlyCTCL/20250724_SGP273_5K_CTCL_Run1",
    "20250724_SGP273_5K_earlyCTCL/20251110__143927__SGP273_run2",
    "20250724_SGP273_5K_earlyCTCL/20251110__142107__SGP273_run3",
    "20250724_SGP273_5K_earlyCTCL/20251117__133339__SGP273_run4",
    "20250724_SGP273_5K_earlyCTCL/20251117__140414__SGP273_run5"
  )
)

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
inputs_file_temp <- paste0(inputs_file, collapse = "\n")
print(glue("Input files:\n{inputs_file_temp}"))
metrics_files <- inputs_file %>%
  list.dirs(recursive = TRUE) %>%
  list.files(pattern = "metrics_summary.csv", full.names = TRUE)

panel_files <- inputs_file %>%
  list.dirs(recursive = TRUE) %>%
  list.files(pattern = "gene_panel.json", full.names = TRUE)

if (!is.null(opt$include)) {
  print(glue("Including only files with pattern: {opt$include}"))
  metrics_files <- metrics_files[grepl(opt$include, metrics_files)]
  panel_files <- panel_files[grepl(opt$include, panel_files)]
}

if (!is.null(opt$exclude)) {
  print(glue("Excluding files with pattern: {opt$exclude}"))
  metrics_files <- metrics_files[!grepl(opt$exclude, metrics_files)]
  panel_files <- panel_files[!grepl(opt$exclude, panel_files)]
}

print(glue("Reading {length(metrics_files)} metrics files"))
metrics_df <- metrics_files %>% readr::read_csv()
print(glue("Reading {length(panel_files)} panel info files"))
panel_info <- panel_files %>% purrr::map(jsonlite::fromJSON)

## Pre-processing ## @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%
# remove columns with all NAs
metrics_df <- metrics_df %>% dplyr::select(-dplyr::where(~ all(is.na(.))))
metrics_df$panel_name <- gsub("Xenium Human ", "", metrics_df$panel_name)
outputs_list[["table"]] <- metrics_df
# identifying projects
sample_base_id <- gsub("[0-9]|_", "", gsub("-.*", "", metrics_df$region_name))
metrics_df$run_name_prj <- paste0(
  gsub("AF_ECZ5K_human_skin_BEACON_1", "ECZ5K_BEACON", metrics_df$run_name),
  "_", sample_base_id
)
run_names <- unique(metrics_df$run_name_prj)
# using a grey scale to highlight project's samples
highlighted <- grepl("AX$|DG$", run_names)
run_name_colors <- grDevices::grey.colors(
  length(run_names), start = 0.5, end = 0.8
)
color_base <- grDevices::colorRampPalette(c("#00796B", "#80CBC4"))
names(run_name_colors) <- run_names
run_name_colors[highlighted] <- color_base(sum(highlighted))

## Main ## @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%
# Plotting numeric metrics
temp <- sapply(metrics_df, function(x) is.numeric(x) || is.integer(x))
all_columns <- colnames(metrics_df)[temp]
# divide by target genes (panel size)
panel_size <- sapply(panel_info, function(x) x$payload$panel$num_gene_targets )
if (length(unique(panel_size)) > 1) {
  logger("Panels have different sizes, normalising by panel size")
  for (i in all_columns) {
    if (grepl("gene|transcript", i)) {
      cat(glue("Normalising '{i}' by panel size\n\n"))
      metrics_df[[glue("{i}_by_panel_size")]] <- metrics_df[[i]] / panel_size
    }
  }
} else {
  logger("Panels have the same size, no normalisation applied")
}

# also grabbing the normalised columns
temp <- grep("_by_panel_size", colnames(metrics_df), value = TRUE)
plot_columns <- unique(c(all_columns[grepl("cell", all_columns)], temp))

if (length(unique((metrics_df$region_name))) < 20) {
  logger("Plotting bars for each metric")
  for (col in plot_columns) {
    temp <- gsub("_", "-", col)
    fname <- glue("barplot_{temp}")
    # creating bars
    plot_aes <- ggplot2::aes(
      x = region_name, y = !!rlang::sym(col),
      fill = run_name_prj
    )
    outputs_list[[fname]] <- ggplot2::ggplot(
      data = metrics_df, mapping = plot_aes
    ) +
      ggplot2::geom_bar(
        stat = "identity", width = 0.8,
        position = ggplot2::position_dodge2(width = 0.8, preserve = "single")
      ) +
      ggplot2::facet_grid(
        cols = ggplot2::vars(run_name_prj, panel_name),
        scale = "free_x", space = "free",
        labeller = ggplot2::label_wrap_gen(15)
      ) +
      # ggplot2::scale_fill_grey(start = 0.5, end = 0.8) +
      ggplot2::scale_fill_manual(values = run_name_colors) +
      theme_global()$theme +
      ggplot2::theme(
        axis.text.x = ggplot2::element_text(angle = 45, hjust = 0.85)
      )
  }
}

if (length(unique((metrics_df$region_name))) > 10) {
  logger("Plotting boxplots for each metric")
  for (col in plot_columns) {
    temp <- gsub("_", "-", col)
    fname <- glue("boxplot_{temp}")
    # creating boxplots
    plot_aes <- ggplot2::aes(
      x = run_name_prj, y = !!rlang::sym(col),
      fill = run_name_prj
    )
    outputs_list[[fname]] <- ggplot2::ggplot(
      data = metrics_df, mapping = plot_aes
    ) +
      ggplot2::geom_boxplot() +
      # add points
      ggplot2::geom_jitter(
        position = ggplot2::position_jitter(width = 0.2),
        size = 2, alpha = 0.7
      ) +
      ggplot2::facet_wrap(
        ggplot2::vars(panel_name),
        scales = "free_x",
        labeller = ggplot2::label_wrap_gen(15)
      ) +
      ggplot2::scale_fill_manual(values = run_name_colors) +
      theme_global()$theme +
      ggplot2::theme(
        axis.text.x = ggplot2::element_text(angle = 45, hjust = 0.85),
        legend.position = "none"
      )
  }
}

if (length(unique((metrics_df$region_name))) > 3) {
  logger("Plotting scatters for preselected metrics")
  preselected_metrics <- grep(
    "median_genes|num_cells|median_transcripts",
    plot_columns, value = TRUE
  )
  print(preselected_metrics)
  comb_list <- combn(preselected_metrics, 2, simplify = FALSE)
  for (col_pair in comb_list) {
    logger(glue("Plotting scatter for {col_pair[1]} vs {col_pair[2]}"))
    temp <- gsub("_", "-", paste(col_pair, collapse = "_vs_"))
    fname <- glue("scatter_{temp}")
    plot_aes <- ggplot2::aes(
      x = !!rlang::sym(col_pair[1]),
      y = !!rlang::sym(col_pair[2]),
      color = run_name_prj,
    )
    outputs_list[[fname]] <- ggplot2::ggplot(
      data = metrics_df, mapping = plot_aes
    ) +
      ggplot2::geom_point(size = 3) +
      ggplot2::scale_color_manual(values = run_name_colors) +
      # adding more breaks on axes
      ggplot2::scale_x_continuous(n.breaks = 7) +
      ggplot2::scale_y_continuous(n.breaks = 7) +
      theme_global()$theme +
      ggplot2::theme(
        axis.text.x = ggplot2::element_text(angle = 45, hjust = 1),
        legend.position = "none"
      )
  }
}

if (length(unique(panel_size)) > 1) {
  logger("Checking overlap between panels")
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
}

## Conclusions ## @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
temp <- paste0(names(outputs_list), collapse = "\n")
logging::loginfo(glue("Produced files:\n{temp}"))
outputs_list <- outputs_list[!grepl("testplot", names(outputs_list))]

## Save ## @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%
if (any(grepl("barplot", names(outputs_list)))) {
  do.call(
    output_save_list,
    c(list(
      OUTPUT_LIST = outputs_list[grepl("barplot", names(outputs_list))],
      OUTPUT_RESU = output_resu,
      width = 3 * length(run_names), height = 10,
      unit = "cm"
    ), theme_global()$args_ggsave)
  )
}
if (any(grepl("boxplot", names(outputs_list)))) {
  do.call(
    output_save_list,
    c(list(
      OUTPUT_LIST = outputs_list[!grepl("barplot", names(outputs_list))],
      OUTPUT_RESU = output_resu,
      width = (4.3 * 3) + (length(run_names) * 0.3),
      height = 4.3 * 3,
      unit = "cm"
    ), theme_global()$args_ggsave)
  )
}

logging::loginfo(crayon::bold(crayon::green("Done!")))