#!/usr/bin/env Rscript
#!/usr/bin/env CODING_LANGUAGE

# ------------------------------------------------------------------------------
# __title: Script cook.
# purpose: This is a template of best practices for a well structured script.
# created: 2025-08-22 Fri 17:22:26 BST
# updated: 2025-08-22
# author:
#   - name: Ciro Ramírez-Suástegui
#     affiliation: The Wellcome Sanger Institute
#     email: cs59@sanger.ac.uk, cramsuig@gmail.com
# ------------------------------------------------------------------------------

parse_args <- function() {
  option_list <- list(
    optparse::make_option(c("-i", "--input"),
      type = "character",
      help = "Input path."
    ),
    optparse::make_option(c("-o", "--output"),
      type = "character",
      help = "Output path."
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

annotation_plot_bar <- function(input, verbose = 0) {
  ggplot2::ggplot(
    data = data,
    mapping = ggplot2::aes(x = forcats::fct_infreq(Annotation))
  ) +
    ggplot2::geom_bar(fill = "steelblue") +
    ggplot2::theme_minimal() +
    ggplot2::labs(
      title = "Annotation Distribution",
      x = "Annotation",
      y = "Count"
    ) +
    ggplot2::theme(
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1)
    )
}

annotation_plots <- function(
  x,
  ...
) {
  glue <- stringr::str_glue
  ## Variables ## --------------------------------------------------------------
  args <- c(args, list(...))
  output_name  <- tools::file_path_sans_ext(basename(args$input))
  output_path <- if (is.null(args$output)) dirname(args$input) else args$output
  output_path <- file.path(output_path, output_name)

  ## Loading data ## -----------------------------------------------------------
  logging::loginfo(glue("Loading data from:\n{args$input}"))

  ## Main code ## --------------------------------------------------------------
  output_object <- annotation_plot_bar(args$input, args$verbose)

  ## Saving ## -----------------------------------------------------------------
  if (!dir.exists(output_path)) {
    dir.create(output_path, recursive = TRUE)
  }
  readr::write_csv(output_object, glue("{output_path}.csv"))
}

if (identical(environment(), globalenv()) && !interactive()) {
  source_require(c("ggplot2", "code/logger.R", "code/utils.R"))

  args <- parse_args()

  logging::loginfo("Starting annotation_plots.")
  annotation_plots(args)
  logging::loginfo("Run completed successfully.")
}