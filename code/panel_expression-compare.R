#!/usr/bin/env R

`!!` <- rlang::`!!`
glue <- stringr::str_glue
`%>%` <<- dplyr::`%>%`

parse_args_ <- function() {
  option_list <- list(
    optparse::make_option(c("-i", "--input"),
      type = "character",
      help = "Input path."
    ),
    optparse::make_option(c("-g", "--group"),
      type = "character",
      help = paste(
        "Columns where group information is stored.",
        "1: broad (eg, technology), 2: narrow (eg, condition), 3: subject"
      )
    ),
    optparse::make_option(c("-t", "--table"),
      type = "character",
      help = "Table of overlaps."
    ),
    optparse::make_option(c("-c", "--colors"),
      type = "character", default = NULL,
      help = "File with colors for annotation."
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

source_require(c(
  "ggplot2",
  "code/logger.R", # logger_info
  "code/utils.R", # output_save_*, show_variables, input_fetch_path
  "code/plotting.R" # plot_bars
))

de_func <- function(data, group_var, test = "t.test") {
  y_label <- "frac(mu[max], mu[min])"
  if (length(table(data[[group_var]])) > 2L) {
    test <- NULL
    x_label <- paste(
      "'Effect size' ~ bgroup('(', max[list(i,j)] ~",
      "group('|', mu[i]-mu[j], '|'), ')')"
    )
  } else {
    x_label <- "'Effect size' ~ bgroup('(', group('|', mu[a]-mu[b], '|'), ')')"
  }
  de_list <- lapply(split(data, data$feature), function(.x) {
    de_ <- list(feature = .x$feature[1], pval = NA, es = NA, fc = NA)
    n_groups <- length(unique(.x[[group_var]]))
    if (n_groups < 2L) {
      warning(glue("{n_groups} group(s) found for {.x$feature[1]}, skipping"))
      return(de_)
    }
    test_formula <- as.formula(paste("value ~", group_var))
    if (is.null(test)) {
      y <- aov(test_formula, data = data)
      de_$pval <- summary(y)[[1]][["Pr(>F)"]][1]
    } else if (test == "t.test" && n_groups == 2L) {
      de_$pval <- t.test(test_formula, data = .x)$p.value
    } else if (test == "wilcox.test" && n_groups == 2L) {
      de_$pval <- wilcox.test(test_formula, data = .x)$p.value
    }
    means <- tapply(.x$value, .x[[group_var]], mean)
    de_$hmean <- max(means)
    if (length(means) == 2L) {
      de_$es <- abs(diff(means))
    } else {
      # only show the message for the last 10 features
      temp <- c
      if (!.x$feature[1] %in% tail(data$feature, 10)) temp <- suppressMessages
      de_$ep2 <- temp(effectsize::epsilon_squared(y)$Epsilon2)
      de_$es <- max(abs(diff(means)))
    }
    # sort and divide means to get fold change, higher is first
    fc <- sort(tapply(.x$value, .x[[group_var]], mean), decreasing = TRUE)
    de_$fc <- fc[1] / fc[length(fc)]
    de_
  })
  out_list <- list(df = NULL, plot = NULL)
  out_list$df <- de_list %>%
    dplyr::bind_rows() %>%
    dplyr::arrange(pval) %>%
    dplyr::mutate(padj = p.adjust(pval, method = "BH")) %>%
    dplyr::arrange(padj, desc(es))
  # Plotting scatterplot of es vs fc
  out_list$plot <- ggplot2::ggplot(out_list$df, ggplot2::aes(x = es, y = fc)) +
    ggplot2::geom_point() +
    theme_global()$theme
  if (diff(range(out_list$df$fc, na.rm = TRUE)) > 10) {
    out_list$plot <- out_list$plot +
      ggplot2::scale_y_log10(breaks = scales::extended_breaks(n = 10))
    y_label <- paste("log[10] ~ bgroup('(',", y_label, " , ')')")
  }
  out_list$plot <- out_list$plot +
    ggplot2::labs(x = parse(text = x_label), y = parse(text = y_label))
  if ("ep2" %in% colnames(out_list$df)) {
    y_label <- "'Effect size (' ~ epsilon^2 ~ ')'"
    out_list$p2 <- ggplot2::ggplot(out_list$df, ggplot2::aes(x = es, y = ep2)) +
      ggplot2::geom_point() +
      ggplot2::labs(x = parse(text = x_label), y = parse(text = y_label)) +
      theme_global()$theme
  }
  return(out_list)
}

panel_expression_comparison <- function(args, ...) {
  ## Variables ## --------------------------------------------------------------
  args <- c(args, list(...))
  input_files <- input_fetch_path(
    args$input, pattern = "annotated.csv",
    full.names = TRUE, verbose = args$verbose
  )
  args_groups <- unlist(strsplit(args$group, ",")) # 2 should be a subset of 1
  output_path <- output_fetch_path(args$output, input_files)
  output_list <- list()

  show_variables()

  ## Loading data ## -----------------------------------------------------------
  logger_info(glue("Fetching overlaps:\n {args$table}"))
  overlap_df <- readr::read_csv(args$table)
  temp <- paste("", paste(input_files, collapse = "\n "))
  logger_info(glue("Loading data from:\n {temp}"))
  start <- Sys.time()
  emdata_df <- lapply(
    X = input_files,
    FUN = readr::read_csv
  ) %>% dplyr::bind_rows()
  temp <- format(difftime(Sys.time(), start, unit = "min"))
  logger_info(paste("Elapsed:", temp))

  ## Preprocessing ## ##########################################################
  emdata_df$nucleus_ratio <- emdata_df$nucleus_area / emdata_df$cell_area
  pp <- plot_violin(
    data = emdata_df,
    x_var = args_groups[3],
    y_var = c(
      "total_counts", "n_genes_by_counts", "nucleus_ratio",
      "log1p_total_counts", "log1p_n_genes_by_counts"
    ),
    face_var = args_groups[1],
    fill_color = args$colors
  )
  for (i in names(pp)) output_list[[i]] <- pp[[i]]

  # Fetching feature names
  features_p <- which(grepl("conf_score", colnames(emdata_df)))
  features_v <- colnames(emdata_df)[(features_p + 1):ncol(emdata_df)]
  temp <- sapply(features_v, function(x) any(is.numeric(emdata_df[[x]])))
  logger_info(glue("Dropping {sum(!temp)} non-numeric from features list:"))
  cat(stringr::str_wrap(paste(features_v[!temp], collapse = ', ')), "\n")
  features_v <- features_v[temp]

  # Calculate mean expression per condition for each feature
  emdata_pivot_df <- emdata_df %>%
    dplyr::group_by(
      !!rlang::sym(args_groups[1]),
      !!rlang::sym(args_groups[2]),
      !!rlang::sym(args_groups[3])
    ) %>%
    dplyr::summarise(dplyr::across(
      .cols = tidyselect::all_of(features_v),
      .fns = list(mean = ~ mean(.x, na.rm = TRUE)),
      .names = "{.col}"
    )) %>%
    tidyr::pivot_longer(
      cols = tidyselect::all_of(features_v),
      names_to = "feature",
      values_to = "value"
    ) %>%
    dplyr::select(-!!rlang::sym(args_groups[2])) %>%
    dplyr::ungroup()

  ## Main code ## ##############################################################
  # We are iterating over each overlap column
  for (overlap_i in grep("~", colnames(overlap_df), value = TRUE)) {
    logger_info(glue("Processing: {overlap_i}"))
    overlap_v <- overlap_df[[overlap_i]][!is.na(overlap_df[[overlap_i]])]
    plot_df <- emdata_pivot_df[emdata_pivot_df$feature %in% overlap_v, ]
    plot_df <- plot_df[!is.na(plot_df$value), ]
    logger_info(glue("Found {length(unique(plot_df$feature))} features"))

    print(knitr::kable(
      x = table(plot_df[args_groups[1]]), format = "simple",
      caption = "Panel distribution"
    ))
    if (nrow(plot_df) == 0 || length(unique(plot_df[[args_groups[1]]])) < 2L) {
      next
    }

    # running tests to fetch DE features
    test <- de_func(plot_df, group_var = args_groups[1])
    temp <- test$df$padj <= 0.05 & test$df$hmean > 0.1
    de_v <- head(test$df[which(temp), ]$feature, 20)
    panel_comb_list <- combn(
      unique(unlist(plot_df[[args_groups[1]]])), 2, simplify = FALSE
    )
    feature_pairs_list <- sapply(
      X = panel_comb_list,
      FUN = function(panel_comb) {
        plot_subset_df <- plot_df[plot_df[[args_groups[1]]] %in% panel_comb, ]
        if (nrow(plot_df) == nrow(plot_subset_df)) {
          feature_out_v <- head(de_v, 10)
        } else {
          ttest <- de_func(
            plot_subset_df, group_var = args_groups[1], test = "t.test"
          )
          temp <- ttest$df$padj <= 0.05 #& (ttest$df$es > 0.2)
          feature_out_v <- head(ttest$df[which(temp), ]$feature, 10)
          panel_comb_name <- paste(panel_comb, collapse = "-vs-")
          path_base <- glue("_{overlap_i}/{panel_comb_name}")
          temp <- "scatter_es_fc___dots__"
          output_list[[glue("{path_base}_{temp}")]] <<- ttest$plot
          filename <- glue("{path_base}_de_ttest")
          output_list[[filename]] <<- ttest$df
        }
        feature_out_v
      }
    )
    feature_show_v <- unique(c(de_v, unlist(feature_pairs_list)))

    logger_info(glue("Generating box plots")) # --------------------------------
    pp <- plot_boxes(
      data = plot_df[plot_df$feature %in% feature_show_v, ],
      x_var = args_groups[1], y_var = "value", face_var = "feature"
    )
    output_list[[glue("_{overlap_i}/de_test")]] <- test$df
    output_list[[glue("_{overlap_i}/scatter_es_fc___dots__")]] <- test$plot
    if (!is.null(test$p2)) {
      output_list[[glue("_{overlap_i}/scatter_es_ep2___dots__")]] <- test$p2
    }
    for (i in names(pp)) output_list[[glue("_{overlap_i}/{i}")]] <- pp[[i]]

    logger_info(glue("Generating scatter plots")) # ----------------------------
    for (panel_comb in panel_comb_list) {
      panel_comb_name <- paste(panel_comb, collapse = "-vs-")
      logger_info(glue(" * {panel_comb_name}"))
      plot_subset_df <- plot_df[plot_df[[args_groups[1]]] %in% panel_comb, ]
      pp <- c(
        plot_scatter( # all in one plot
          data = plot_subset_df,
          axes = args_groups[1], values = "value",
          color_var = "feature", shape_var = args_groups[3],
          feature_show = unlist(feature_pairs_list),
          dev = 0.2
        ),
        plot_scatter( # faceted plot
          data = plot_subset_df,
          axes = args_groups[1], values = "value",
          color_var = "feature", shape_var = args_groups[3],
          facet_var = args_groups[3],
          feature_show = unlist(feature_pairs_list),
          dev = 0.2
        )
      )
      for (i in names(pp)) output_list[[glue("_{overlap_i}/{i}")]] <- pp[[i]]
    }
  }

  ## Saving ## #################################################################
  do.call(
    output_save_list,
    c(list(
      OUTPUT_LIST = output_list[!grepl("scatter_h", names(output_list))],
      OUTPUT_RESU = output_path,
      width = 5.7 * 3, height = 4.3 * 3,
      unit = "cm"
    ), theme_global()$args_ggsave)
  )
  do.call(
    output_save_list,
    c(list(
      OUTPUT_LIST = output_list[grepl("scatter_h", names(output_list))],
      OUTPUT_RESU = output_path,
      width = 5.7 * 2, height = 4.3 * 2,
      unit = "cm"
    ), theme_global()$args_ggsave)
  )
  do.call(
    output_save_list,
    c(list(
      OUTPUT_LIST = output_list[grepl("violin", names(output_list))],
      OUTPUT_RESU = "results/quality_control",
      width = 5.7 * 4, height = 4.3 * 2,
      unit = "cm"
    ), theme_global()$args_ggsave)
  )
}

# source("code/panel_expression-compare.R")
if (identical(environment(), globalenv()) && !interactive()) {
  args <- parse_args_()
  if (interactive()) {
    args$input <- "results/panels-10x_overlaps"
    args$group <- "panel_type,sample_id_object,donor_id"
    args$table <- "results/panels-10x_overlaps/overlaps_table.csv"
    args$colors <- "data/metadata/ruoyan_2024_suspension_cell_type_colour.csv"
  }

  logger_info("Starting panel expression comparison")
  panel_expression_comparison(args)
  logger_info("Run completed successfully.")
}
