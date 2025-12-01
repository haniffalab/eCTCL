#!/usr/bin/env R

# ------------------------------------------------------------------------------
# __title: Choosing colours.
# purpose: We are assigning colours to each of our variables: cell type,
#          batch, etc.
# created: 2025-09-16 Tue 14:22:36 BST
# updated: 2025-09-16
# author:
#   - name: Ciro Ramírez-Suástegui
#     affiliation: The Wellcome Sanger Institute
#     email: cs59@sanger.ac.uk, cramsuig@gmail.com
# ------------------------------------------------------------------------------

#!/usr/bin/env Rscript
#!/usr/bin/env CODING_LANGUAGE

# ------------------------------------------------------------------------------
# __title: Script cook.
# purpose: This is a template of best practices for a well structured script.
# created: 2025-09-16 Tue 14:44:55 BST
# updated: 2025-09-16
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

mdata_colours <- function(
  args,
  ...
) {
  glue <- stringr::str_glue

  ## Variables ## --------------------------------------------------------------
  args <- c(args, list(...))
  output_name  <- tools::file_path_sans_ext(basename(args$input))
  output_path <- if (is.null(args$output)) dirname(args$input) else args$output
  output_path <- file.path(output_path, output_name)

  show_variables()

  ## Loading data ## -----------------------------------------------------------
  logger_info(glue("Loading data from:\n{args$input}"))
  mdata <- readr::read_csv(args$input)

  ## Main code ## --------------------------------------------------------------
  column_list <- lapply(
    X = c("sample", "batch", "condition"),
    FUN = function(x) unique(mdata[[x]])
  )

  for (i in names(column_list)) {
    cols_generator <- colorRampPalette(RColorBrewer::brewer.pal(12, "Set3"))
    cols_df <- data.frame(
      variable = column_list[[i]],
      colour = cols_generator(length(column_list[[i]]))
    )
    readr::write_tsv(cols_df, file = paste0(outputs_path, i, "_colours.tsv"))
  }

  ## Saving ## -----------------------------------------------------------------
  if (!dir.exists(output_path)) {
    dir.create(output_path, recursive = TRUE)
  }
  readr::write_csv(output_object, glue("{output_path}.csv"))
}

if (identical(environment(), globalenv()) && !interactive()) {
  source_require(c(
    "ggplot2",
    "code/logger.R", # logger_info
    "code/utils.R" # output_save_*, show_variables
  ))

  args <- parse_args_()

  logger_info("Starting mdata_colours.")
  mdata_colours(args)
  logger_info("Run completed successfully.")
}