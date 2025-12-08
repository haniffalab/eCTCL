#!/usr/bin/env Rscript

# ------------------------------------------------------------------------------
# purpose: Annotation distribution across panels.
# created: 2025-08-22 Fri 17:22:26 BST
# updated: 2025-09-21
# author:
#   - name: Ciro Ramírez-Suástegui
#     affiliation: The Wellcome Sanger Institute
#     email: cs59@sanger.ac.uk, cramsuig@gmail.com
# ------------------------------------------------------------------------------

`%>%` <- dplyr::`%>%`
glue <- stringr::str_glue

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
    optparse::make_option(c("-s", "--subset"),
      type = "character",
      help = "Subset of data to use."
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
  "code/logger.R", # logger_info
  # output_save_*, show_variables, input_fetch_path, output_fetch_path
  "code/utils.R",
  "code/plotting.R" # theme_global()
))

annotation_plot_bar <- function(
  data, x_var, facet_var = NULL
) {
  data_counts <- table(data[[x_var]])
  p <- ggplot2::ggplot(
    data = data,
    mapping = ggplot2::aes(x = forcats::fct_infreq(!!rlang::sym(x_var)))
  ) +
    ggplot2::geom_bar(stat = "count") +

    ggplot2::labs(x = NULL, y = "No. features") +
    ggplot2::scale_y_continuous(
      expand = ggplot2::expansion(mult = c(0, .1))
    ) +
    theme_global()$theme +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))
  # add numbers on top of bars
  if (length(data_counts) < 50) { # only if not too many bars
    p <- p + ggplot2::geom_text(
      stat = "count",
      ggplot2::aes(label = ggplot2::after_stat(count)),
      vjust = -0.5,
      size = theme_global()$theme$text$size * 0.2
    )
  }
  # scale text size if too many bars
  if (length(data_counts) > 50) {
    p <- p + ggplot2::theme(
      axis.text.x = ggplot2::element_text(
        angle = 45, hjust = 1, size = 15/min(c(length(data_counts), 50))
      )
    )
  }
  if (diff(range(data_counts, na.rm = TRUE)) > 1000) {
    p <- p + ggplot2::labs(y = parse(text = "log[10] ~ '(Count)'")) +
      ggplot2::scale_y_log10(expand = ggplot2::expansion(mult = c(0, .15)))
  }
  if (!is.null(facet_var)) {
    p <- p + ggplot2::facet_wrap(
      ggplot2::vars(!!rlang::sym(facet_var)), ncol = 1
    )
  }
  filename <- glue("barplot_{x_var}_count_{x_var}___{facet_var}__")
  filename <- stringr::str_to_lower(filename)
  return(setNames(list(p), filename))
}

function_main <- function(
  args,
  ...
) {
  ## Variables ## --------------------------------------------------------------
  args <- c(args, list(...))
  input_files <- input_fetch_path(
    path_file = args$input, pattern = "\\.csv$",
    full.names = TRUE, verbose = args$verbose
  )
  output_path <- output_fetch_path(args$output, input_files)
  output_list <- list()
  immune_cells_patterns <- paste0(c(
    "B cell|T cell|NK cell|Macrophage|Monocyte|DC",
    "|Mast|CD4|CD8|Plasma|Neutrophil|Mast|Dendritic"
  ), collapse = "")

  show_variables()

  ## Loading data ## -----------------------------------------------------------
  temp <- paste("", paste(input_files, collapse = "\n "))
  logger_info(glue("Loading data from:\n {temp}"))
  annotation_list <- lapply(input_files, readr::read_csv)
  names(annotation_list) <- tools::file_path_sans_ext(basename(input_files))
  overlap_df <- tibble::tibble(all = "all")
  if (!is.null(args$subset)) {
    logger_info(glue("Loading data subsetting:\n {args$subset}"))
    overlap_df <- readr::read_csv(args$subset)
    output_path <- paste0(
      output_path, if (grepl("\\/$", output_path)) "" else "_",
      tools::file_path_sans_ext(basename(args$subset))
    )
  }

  ## Pre-processing ## ---------------------------------------------------------
  annotation_list[["hAtlas-v1.1"]] <- annotation_list[["hAtlas-v1.1"]] %>%
    dplyr::rename(
      Annotation = cell_type,
      Gene = gene_name,
      `Ensembl ID` = gene_id
    )
  annotation_list[["hSkin-v1"]] <- annotation_list[["hSkin-v1"]] %>%
    dplyr::mutate(Annotation = stringr::str_replace_all(Annotation, "_", " "))

  annotation_df <- annotation_list %>%
    dplyr::bind_rows(.id = "Panel") %>%
    dplyr::mutate(
      Annotation = dplyr::if_else(
        is.na(Annotation), "Unannotated", Annotation
      ),
      Annotation = dplyr::if_else(
        Annotation == "", "Unannotated", Annotation
      ),
      Annotation_binary = dplyr::if_else(
        Annotation == "Unannotated", "Unannotated", "Annotated"
      ),
      Annotation_first = stringr::str_replace(Annotation, ";.*", ""),
      Annotation_immune = dplyr::if_else(
        stringr::str_detect(
          Annotation, immune_cells_patterns
        ),
        stringr::str_extract_all(Annotation, immune_cells_patterns) %>%
          sapply(function(x) {
            y <- sort(unique(x))
            synonyms <- c("CD8", "CD4", "T cell")
            if (sum(synonyms %in% x) > 1) {
              y[y %in% synonyms] <- "T cell"
            }
            y <- sort(unique(y))
            paste(y, collapse = ", ")
          }),
        "Non-immune"
      ),
      Annotation_immune = dplyr::if_else(
        Annotation == "Unannotated", "Unannotated", Annotation_immune
      )
    )
  str(table(annotation_df$Annotation_immune))

  ## Main code ## --------------------------------------------------------------
  if (!is.null(args$subset)) {
    temp <- overlap_df %>%
      dplyr::select(-dplyr::contains("hAtlas")) %>%
      unlist(use.names = FALSE) %>%
      unique() %>% # remove NA
      setdiff(NA)
    overlap_df[["non_hAtlas"]] <- temp[1:nrow(overlap_df)]
    temp <- overlap_df %>%
      dplyr::select(-hAtlas) %>%
      unlist(use.names = FALSE) %>%
      unique() %>% # remove NA
      setdiff(NA)
    overlap_df[["hSkin~hImmune_union"]] <- temp[1:nrow(overlap_df)]
  }
  for (overlap_i in colnames(overlap_df)) {
    annotation_subset_df <- annotation_df
    if (overlap_i != "all") {
      annotation_subset_df <- annotation_df %>%
        dplyr::filter(Gene %in% overlap_df[[overlap_i]])
    }
    if (nrow(annotation_subset_df) == 0) {
      logger_info(glue("No data for subset {overlap_i}, skipping."))
      next
    }
    pp <- c(
      # annotation_plot_bar(
      #   annotation_subset_df, x_var = "Annotation_first", facet_var = "Panel"
      # ),
      annotation_plot_bar(
        annotation_subset_df, x_var = "Annotation_binary", facet_var = "Panel"
      ),
      # annotation_plot_bar(
      #   annotation_subset_df, x_var = "Annotation", facet_var = "Panel"
      # ),
      annotation_plot_bar(
        annotation_subset_df, x_var = "Annotation_immune", facet_var = "Panel"
      )
    )
    for (i in names(pp)) {
      temp <- gsub("__$", glue("_{overlap_i}_"), i)
      output_list[[temp]] <- pp[[i]]
    }
  }

  logger_info("Checking overlap between panels")
  annotation_df$Annotation_immune_panel <- paste(
    annotation_df$Annotation_immune,
    annotation_df$Panel,
    sep = "  "
  )
  panel_list <- split(annotation_df$Gene, annotation_df$Annotation_immune_panel)
  n_targets <- max(sapply(
    panel_list, function(x) length(x)
  ))
  out_df <- sapply(panel_list, function(x) {
    x[1:n_targets]
  }) %>% as.data.frame()
  temp <- c(colnames(out_df)) # , "All"
  overlaps_comb <- matrix(nrow = length(temp), ncol = length(temp))
  dimnames(overlaps_comb) <- list(temp, temp)
  overlaps_comb_pct <- overlaps_comb
  check_pattern <- "T cell|CD8|CD4"
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
      # temp <- grepl(check_pattern, colnames(out_df)[i])
      # temp <- temp || grepl(check_pattern, colnames(out_df)[j])
      # if (temp) {
      #   temp <- annotation_df$Gene %in% intersect(i_values, j_values)
      #   print(annotation_df[temp, c("Gene", "Annotation_immune", "Panel")])
      # }
    }
  }

  output_list[["Annotation_immune_overlap"]] <- plot_heatmap_overlap(
    overlaps_comb
  )
  output_list[["Annotation_immune_overlap_hAtlas"]] <- plot_heatmap_overlap(
    overlaps_comb[, grepl("hAtlas", colnames(overlaps_comb))]
  )
  fname <- "Annotation_immune_overlap-percentages"
  output_list[[fname]] <- plot_heatmap_overlap(overlaps_comb_pct)


  ## Saving ## -----------------------------------------------------------------
  do.call(
    output_save_list,
    c(list(
      OUTPUT_LIST = output_list[grepl("Annotation_immune", names(output_list))],
      OUTPUT_RESU = output_path,
      width = 5.7 * 3.7, height = 4.3 * 3.4,
      unit = "cm"
    ), theme_global()$args_ggsave)
  )
  # temp <- "barplot_annotation_immune_count_annotation_immune___"
  # do.call(
  #   output_save_list,
  #   c(list(
  #     OUTPUT_LIST = output_list[grepl(temp, names(output_list))],
  #     OUTPUT_RESU = output_path,
  #     width = 5.7 * 2, height = 4.3 * 2.5,
  #     unit = "cm"
  #   ), theme_global()$args_ggsave)
  # )
  # do.call(
  #   output_save_list,
  #   c(list(
  #     OUTPUT_LIST = output_list[grepl("binary", names(output_list))],
  #     OUTPUT_RESU = output_path,
  #     width = 5.7 * 2, height = 4.3 * 2,
  #     unit = "cm"
  #   ), theme_global()$args_ggsave)
  # )
}

# source("code/panel_annotations.R")
if (identical(environment(), globalenv()) && !interactive()) {
  args <- parse_args_()
  if (interactive()) {
    args$input <- "data/xenium-panels/"
    args$subset <- "results/panels-10x_overlaps/overlaps_table.csv"
    args$output <- "results/xenium-panels/"
  }

  logger_info("Starting function_main.")
  function_main(args)
  logger_info("Run completed successfully.")
}