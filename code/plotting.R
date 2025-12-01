#!/usr/bin/env Rscript

# ------------------------------------------------------------------------------
# purpose: Gather plotting functions.
# created: 2025-10-14 Tue 00:52:43 BST
# updated: 2025-10-14
# author:
#   - name: Ciro Ramírez-Suástegui
#     affiliation: The Wellcome Sanger Institute
#     email: cs59@sanger.ac.uk, cramsuig@gmail.com
# ------------------------------------------------------------------------------

format_title <- function(text) {
  # Replace underscores/hyphens and trim whitespace
  text <- gsub("_|-", " ", trimws(text))

  # Convert to Title Case (like str.title())
  # tools::toTitleCase capitalizes each word
  text <- tools::toTitleCase(tolower(text))

  # Custom replacements (case-insensitive)
  spec <- c(
    " id" = " ID",
    "rna" = "RNA",
    "umap" = "UMAP",
    "tsne" = "t-SNE",
    "pca" = "PCA",
    "ann " = "Annotation "
  )

  for (k in names(spec)) {
    text <- gsub(k, spec[[k]], text, ignore.case = TRUE)
  }

  text
}

################################################################################
# Themes #######################################################################
#region ########################################################################

`%+replace%` <- ggplot2::`%+replace%`

#' Matplotlib-inspired ggplot2 theme
#'
#' @return A list containing `theme`, `scale_color`, and `scale_fill`
#' @export
#'
#' @examples
#' p + theme_global()$theme + theme_global()$scale_color
#' ggsave("plot.png", p, !!!theme_global()$args_ggsave)
theme_global <- function() {
  rel <- ggplot2::rel
  theme_custom <- ggplot2::theme_minimal() +
    ggplot2::theme(
      # font.size: 8
      text = ggplot2::element_text(size = 8),
      # axes.titlesize: "medium"
      axis.title = ggplot2::element_text(size = rel(1.0)),
      # figure.titlesize: "medium"
      plot.title = ggplot2::element_text(size = rel(1.0)),
      plot.subtitle = ggplot2::element_text(size = rel(1.0)),

      # figure.labelsize: "small"
      axis.text = ggplot2::element_text(size = rel(0.8)),

      # grid.linestyle: "dotted"
      # grid.color: "#f2f2f2"
      panel.grid.major = ggplot2::element_line(
        color = "#f2f2f2", linetype = "dotted"
      ),
      panel.grid.minor = ggplot2::element_line(
        color = "#f2f2f2", linetype = "dotted"
      ),

      # figure.frameon: False
      panel.border = ggplot2::element_blank(),
      panel.background = ggplot2::element_blank(),

      # figure.autolayout: True
      # handled implicitly by tight margins
      plot.margin = ggplot2::margin(0.1, 0.1, 0.1, 0.1),

      # patch.linewidth: 0.01
      plot.background = ggplot2::element_rect(fill = NA, linewidth = 0.01),

      # Legend adjustments (no direct rcParam equivalent) —I think it is lying
      legend.background = ggplot2::element_blank(),
      legend.text = ggplot2::element_text(size = rel(0.8)),
      legend.title = ggplot2::element_text(size = rel(0.8)),
      legend.key = ggplot2::element_blank(),
      legend.position = "none"
    )

  # image.cmap: "viridis"
  scale_color_c <- ggplot2::scale_colour_viridis_c()
  scale_fill_c <- ggplot2::scale_fill_viridis_c()

  # Return list for easy usage
  list(
    theme = theme_custom,
    scale_color_c = scale_color_c,
    scale_fill_c = scale_fill_c,
    # savefig.* mappings (for use with ggsave)
    args_ggsave = list(
      dpi = 300,               # savefig.dpi
      bg = "transparent",      # savefig.transparent
      limitsize = FALSE        # savefig.bbox = "tight"
    )
  )
}

if (utils::packageVersion("ggplot2") < "4.0.0") {
  warning("ggplot2 >= 4.4.0 is required to use 'set_theme()'")
} else {
  theme_old <- ggplot2::get_theme()
  ggplot2::set_theme(theme_global()$theme)
}

theme_fix_size <- function(x) {
  if ("size" %in% names(x)) {
    x["size"] <- as.character(x["size"])
  }
  x
}

theme_set <- function(theme_list = NULL) {
  theme_list_mods <- lapply(
    X = theme_list,
    FUN = function(x) {
      y <- paste0("ggplot2::", x[1])
      y_old <- ggplot2::get_geom_defaults(eval(parse(text = y)))
      if (!is.na(x[2]) && grepl("geom_", x[1])) {
        ggplot2::update_geom_defaults(gsub("geom_", "", x[1]), as.list(x[-1]))
        y_out <- dplyr::bind_rows(
          theme_fix_size(y_old),
          theme_fix_size(ggplot2::get_geom_defaults(eval(parse(text = y))))
        )
      } else {
        y_out <- y_old
      }
      y_out <- suppressMessages(readr::type_convert(y_out))
      y_out <- dplyr::bind_cols(default = c("old", "new")[1:nrow(y_out)], y_out)
      dplyr::bind_cols(geom = rep(x[1], nrow(y_out)), y_out)
  })
  theme_list_mods_df <- dplyr::bind_rows(theme_list_mods)

  # Only show columns where the values changed
  theme_change <- rowSums(sapply(
    X = split(theme_list_mods_df, theme_list_mods_df$geom),
    FUN = function(x) {
      y <- x[, -which(names(x) %in% c("geom"))]
      c(geom = TRUE, sapply(y, function(y) length(unique(y)) > 1))
  })) > 1
  print(theme_list_mods_df[, theme_change, drop = FALSE])
}

theme_list_user <- list(
  c("geom_text", size = 6),
  c("geom_label"),
  c("geom_point", size = 3)
)

# theme_set(theme_list = theme_list_user)

annotation_add_colours <- function(data, column, colors) {
  column_v <- unique(data[[column]])
  if (is.null(colors)) {
    colors <- setNames(scales::hue_pal()(length(column_v)), column_v)
  }
  if (file.exists(colors[1])) {
    colors <- readr::read_csv(
      colors[1], col_names = FALSE, show_col_types = FALSE
    )
    colors <- setNames(colors$X1, colors$X2)
  }
  colours_y <- colors[column_v]
  if (all(is.na(colours_y))) {
    temp <- paste(column_v, collapse = ", ")
    msg <- glue::glue("Values:{temp}")
    temp <- paste(names(colors), collapse = ", ")
    msg <- glue::glue("{msg}\nColors:{temp}")
    warning(glue::glue("No matching colors found for '{column}'.\n{msg}"))
    return(NULL)
  }
  if (any(is.na(colours_y))) {
    temp <- paste(column_v[is.na(colours_y)], collapse = ", ")
    warning(glue::glue("Some missing colors for '{column}': {temp}"))
    colours_y[is.na(colours_y)] <- "#bebebe"
  }
  colours_y
}

#endregion #####################################################################
# Functions ####################################################################
#region ########################################################################

plot_boxes_ <- function(data, x_var, y_var, face_var) {
  ggplot2::ggplot(
    data = data,
    mapping = ggplot2::aes(
      x = !!ggplot2::sym(x_var),
      y = !!ggplot2::sym(y_var),
      color = !!ggplot2::sym(x_var)
    )
  ) +
    ggplot2::geom_boxplot(outlier.shape = NA) +
    ggplot2::geom_jitter(color = "black", width = 0.2, alpha = 0.5) +
    ggplot2::facet_wrap(ggplot2::vars(!!ggplot2::sym(face_var))) +
    ggplot2::labs(x = NULL, y = "Mean expression") +
    theme_global()$theme
}

plot_boxes <- function(data, x_var, y_var, face_var, batch_n = 12) {
  pp <- list()
  batch_list <- split(
    x = unique(data[[face_var]]),
    f = ceiling(seq_along(unique(data[[face_var]])) / batch_n)
  )
  for (batch_i in names(batch_list)) {
    temp <- paste(batch_list[[batch_i]], collapse = ", ")
    cat(glue("- batch {batch_i}: {temp}"), "\n")
    temp <- unlist(data[[face_var]]) %in% batch_list[[batch_i]]
    p <- plot_boxes_(data[temp, ], x_var, y_var, face_var)
    filename <- glue("boxplot_{x_var}_{y_var}_{x_var}__{face_var}_{batch_i}")
    pp[[filename]] <- p
  }
  pp
}

plot_scatter <- function(
  data, axes, values, color_var, shape_var,
  facet_var = NULL, feature_show = NULL,
  dev = 0.25
) {
  axes_v <- data[[axes]] %>% unique()
  filename <- glue(
    "scatter_{axes_v[1]}_{axes_v[2]}_{color_var}__{shape_var}"
  )
  ids <- c(color_var, shape_var)
  temp <- data %>% # filtering out empty groups
    dplyr::group_by_at(ggplot2::vars(!!!ids)) %>%
    dplyr::summarise(n = dplyr::n()) %>%
    dplyr::filter(n > 1L) %>%
    dplyr::ungroup()
  plot_df <- data[data[[shape_var]] %in% temp[[shape_var]], ] %>%
    tidyr::pivot_wider(
      id_cols = c(color_var, shape_var),
      names_from = !!ggplot2::sym(axes),
      values_from = !!ggplot2::sym(values),
      values_fn = ~ mean(.x, na.rm = TRUE)
    ) %>%
    dplyr::mutate(
      dplyr::across(tidyselect::all_of(axes_v), ~ tidyr::replace_na(.x, 0))
    )
  vmax <- max(plot_df[[axes_v[1]]], plot_df[[axes_v[2]]], na.rm = TRUE)
  p <- ggplot2::ggplot(
    data = plot_df,
    mapping = ggplot2::aes(
      x = !!ggplot2::sym(axes_v[1]),
      y = !!ggplot2::sym(axes_v[2]),
      color = !!ggplot2::sym(color_var),
      shape = !!ggplot2::sym(shape_var)
    )
  ) +
    ggplot2::geom_point(alpha = 0.5) +
    ggplot2::scale_shape_manual(
      values = 1:nlevels(factor(data[[shape_var]]))
    ) + # make both axes the same to reflect distance from diagonal
    ggplot2::coord_fixed(xlim = c(0, vmax), ylim = c(0, vmax)) +
    ggplot2::labs(x = glue("{axes_v[1]} mean"), y = glue("{axes_v[2]} mean")) +
    ggplot2::geom_abline( # plot diagonal line
      slope = 1, intercept = 0, linetype = "dashed", color = "grey80"
    ) +
    theme_global()$theme +
    ggplot2::theme(legend.position = "none")
  temp <- abs(plot_df[[axes_v[1]]] - plot_df[[axes_v[2]]]) > dev * vmax
  feature_edge <- plot_df[temp, color_var] %>% unlist() %>% unique()
  if (is.null(feature_show)) feature_show <- "noneofthese"
  plot_df_ggrep <- plot_df %>%
    dplyr::filter( # fetch points where either is far from diagonal
      abs(!!ggplot2::sym(axes_v[1]) - !!ggplot2::sym(axes_v[2])) > dev * vmax |
      tidyselect::all_of(!!ggplot2::sym(color_var)) %in% feature_show
    ) %>% # column for color in ggrepel, add red to feature_show
    dplyr::mutate(
      color = ifelse(
        !!ggplot2::sym(color_var) %in% feature_show, "red", "black"
      )
    )
  if (!is.null(facet_var)) {
    filename <- glue("{filename}_{facet_var}")
    p <- p + ggplot2::facet_wrap(ggplot2::vars(!!ggplot2::sym(facet_var)))
  } else {
    plot_df_ggrep <- plot_df_ggrep %>%
      dplyr::filter(
        !duplicated(!!ggplot2::sym(color_var))
      )
  }
  p <- p + ggrepel::geom_text_repel(
    data = plot_df_ggrep,
    mapping = ggplot2::aes(
      x = !!ggplot2::sym(axes_v[1]),
      y = !!ggplot2::sym(axes_v[2]),
      label = !!ggplot2::sym(color_var)
    ),
    size = theme_global()$theme$text$size * 0.2,
    color = plot_df_ggrep$color,
    box.padding = 0.5, segment.color = "grey50",
    max.overlaps = Inf
  )
  setNames(list(p), filename)
}

plot_bars <- function(
  data,
  x_var, fill_var, facet_var = NULL,
  fill_color = NULL,
  x_order = NULL,
  x_labels = NULL
) {
  fill_color_v <- annotation_add_colours(data, fill_var, fill_color)
  if (!is.null(x_order)) {
    data[[x_var]] <- factor(data[[x_var]], levels = x_order)
  }
  p <- ggplot2::ggplot(
    data = data,
    mapping = ggplot2::aes(
      x = !!rlang::sym(x_var), fill = !!rlang::sym(fill_var)
    )
  ) +
    ggplot2::geom_bar(position = "fill") +
    ggplot2::labs(x = NULL, y = NULL) +
    theme_global()$theme +
    ggplot2::theme(
      axis.text.x = ggplot2::element_text(angle = 90, vjust = 0.5, hjust = 1)
    ) +
    ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0, 0)))
  if (!is.null(fill_color_v)) {
    p <- p + ggplot2::scale_fill_manual(values = fill_color_v)
  }
  if (!is.null(x_labels)) {
    # pasting columns specified in x_labels together
    x_labels_v <- sapply(
      X = split(data, data[[x_var]]),
      FUN = function(x) {
        paste(sapply(x_labels, function(y) {
          unique(as.character(x[[y]]))
        }), collapse = " | ")
      }
    )
    p <- p + ggplot2::scale_x_discrete(labels = x_labels_v)
  }
  if (!is.null(facet_var)) {
    p <- p + ggplot2::facet_wrap(
      ggplot2::vars(!!rlang::sym(facet_var)),
      scales = "free_x", nrow = 1
    )
  }
  # set all NULL named parameters to "", so glue works properly
  for (i in names(formals())) {
    if (is.null(eval(i))) assign(i, "")
  }
  filename <- glue::glue("barplot_{x_var}_proportion_{fill_var}___{facet_var}")
  setNames(list(p), filename)
}

plot_violin_ <- function(
  data, x_var, y_var, face_var = NULL, fill_color = NULL, y_scale = FALSE
) {
  data_downsampled <- data %>%
    dplyr::group_by(!!ggplot2::sym(x_var), !!ggplot2::sym(face_var)) %>%
    dplyr::slice_sample(n = 200, replace = FALSE) %>%
    dplyr::ungroup()
  p <- ggplot2::ggplot(
    data = data,
    mapping = ggplot2::aes(
      x = !!ggplot2::sym(x_var),
      y = !!ggplot2::sym(y_var),
      color = !!ggplot2::sym(x_var)
    )
  ) +
    ggplot2::geom_violin(alpha = 0.8) +
    ggplot2::geom_jitter(
      data = data_downsampled,
      color = "black",
      position = ggplot2::position_jitter(0.2),
      alpha = 0.5,
      size = 0.001
    ) +
    ggplot2::geom_boxplot(
      colour = "black", fill = "white", alpha = 0.25,
      width = 0.1,
      outlier.shape = NA
    ) +
    theme_global()$theme +
    ggplot2::theme(
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1)
    )
  if (diff(range(data[[y_var]], na.rm = TRUE)) > 1000 && isTRUE(y_scale)) {
    p <- p  +
      ggplot2::scale_y_continuous(
        trans = "log10",
        labels = function(b) b, # show original values
        breaks = scales::extended_breaks()
      )
  }
  if (!is.null(face_var)) {
    p <- p + ggplot2::facet_wrap(
      ggplot2::vars(!!ggplot2::sym(face_var)),
      scales = "free_x", nrow = 1
    )
  }
  color_v <- annotation_add_colours(data, x_var, fill_color)
  if (!is.null(color_v)) {
    p <- p + ggplot2::scale_color_manual(values = color_v)
  }
  p
}

plot_violin <- function(
  data, x_var, y_var, face_var = NULL, fill_color = NULL
) {
  pp <- list()
  for (y_var_i in y_var) {
    filename <- glue::glue("violin_{x_var}_{y_var_i}_{x_var}___{face_var}__")
    p <- plot_violin_(data, x_var, y_var_i, face_var, fill_color)
    pp[[filename]] <- p
  }
  pp
}

# https://gist.github.com/danlooo/d23d8bcf8856c7dd8e86266097404ded
ggeulerr <- function(
  combinations, show_quantities = TRUE, show_labels = TRUE, ...
) {
  data <-
    eulerr::euler(combinations = combinations) %>%
    plot(quantities = show_quantities) %>%
    purrr::pluck("data")
  
  tibble::tibble() %>%
    ggplot2::ggplot() +
    ggforce::geom_ellipse(
      data = data$ellipses %>% tibble::as_tibble(rownames = "Set"),
      mapping = ggplot2::aes(
        x0 = h, y0 = k, a = a, b = b, angle = 0, fill = Set
      ),
      alpha = 0.5
    ) +
    ggplot2::geom_text(
      data = {
        data$centers %>%
          dplyr::mutate(
            label = labels %>% purrr::map2(quantities, ~ {
              if (!is.na(.x) && !is.na(.y) && show_labels) {
                paste0(.x, "\n", .y)
                # paste0(.x, "\n", sprintf(.y, fmt = "%.2g"))
              } else if (!is.na(.x) && show_labels) {
                .x
              } else if (!is.na(.y)) {
                .y
              } else {
                ""
              }
            })
          )
      },
      mapping = ggplot2::aes(x = x, y = y, label = label)
    ) +
    # ggplot2::theme(panel.grid = ggplot2::element_blank()) +
    ggplot2::coord_fixed()
}

plot_heatmap_overlap <- function(x_matrix) {
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
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1),
      axis.title = ggplot2::element_blank(),
      legend.title = ggplot2::element_blank()
    )
}

#endregion #####################################################################