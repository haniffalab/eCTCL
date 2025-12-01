#!/usr/bin/env R

# ------------------------------------------------------------------------------
# title: Comparing Xenium panels.
# purpose: We are fetching panels to compare the overapping genes and the
#           cell types they target.
#
# created: 2025-02-04 Tue 08:53:59 GMT
# updated: 2025-08-18
# version: 0.0.9
# status: Prototype
#
# maintainer: Ciro Ramírez-Suástegui
# author:
#   - name: Ciro Ramírez-Suástegui
#     affiliation: The Wellcome Sanger Institute
#     email: cs59@sanger.ac.uk, cramsuig@gmail.com
# ------------------------------------------------------------------------------
# Exectute:
# FNAME=code/panel_overlaps.R; chmod +x ${FNAME}; mkdir -p .logs;
# LNAME=$(echo "${FNAME/%.*/}" | sed 's|'"$(dirname ${PWD})/"'||' | tr '/' '.')
# Rscript ${FNAME} 2>&1 | tee -a .logs/${FNAME/\//.}_$(date +%Y%m%d%-H%M%S)

################################################################################
## Environment setup ###########################################################
################################################################################

# Quick installations --------------------------------------
source("code/utils.R")
# Basic packages -------------------------------------------
# Logging configuration ------------------------------------
source("code/logger.R")
# In-house/developing --------------------------------------
source("code/plotting.R")
# overlap_list
url0 <- "https://raw.githubusercontent.com/cramsuig/"
url <- paste0(url0, "handy_functions/refs/heads/master/devel/overlap.R")
source(url)
# Tool (packaged) modules ----------------------------------
`%>%` <- dplyr::`%>%`

################################################################################
logger("Global configuration") #################################################
################################################################################

glue <- stringr::str_glue
indata_name <- "panels-10x"
action_name <- "overlaps"
result_name <- sprintf(
  "%s_%s", indata_name, action_name
)

inputs_path <- "./data"
extent_strn <- "csv"
inputs_fold <- file.path(inputs_path, "xenium-panels")

output_resu <- file.path("./results", glue("{result_name}"))
output_figs <- file.path("./results", glue("{result_name}"))
output_file <- file.path(
  inputs_path, "processed", glue("{indata_name}_{action_name}.{extent_strn}")
)

outputs_list <- list()

temp <- sapply(ls(), function(x) class(get(x))) %in% c("list", "character")
temp <- ls()[temp & !grepl("opt", ls())]
str(sapply(temp, function(x) get(x)))

################################################################################
logger("Loading data") #########################################################
################################################################################

logger_info("Loading data.")
inputs_files <- list.files(inputs_fold, pattern = "*.csv", full.names = TRUE)
panels_df <- lapply(inputs_files, readr::read_csv)
names(panels_df) <- gsub("_metadata|-.*", "", basename(inputs_files))

################################################################################
logger("Pre-processing") #######################################################
################################################################################

panels_list <- lapply(panels_df, function(x) {
  # Ensembl, gene_id; Gene, gene_name
  y <- x %>%
    dplyr::select(
      dplyr::starts_with("Gene", ignore.case = FALSE),
      dplyr::starts_with("gene_name", ignore.case = FALSE)
    ) %>% c()
  y[[1]]
})
str(panels_list)

################################################################################
logger("Main") #################################################################
################################################################################

logger("Calculating overlaps.", 60, cyan)
res_overlap <- overlap_list(panels_list, v = TRUE)
str(res_overlap)

smax <- max(sapply(res_overlap, length))
outputs_list[["overlaps_table"]] <- sapply(
  X = res_overlap,
  FUN = function(x) {
    y <- x[1:smax]
    y[is.na(y)] <- ""
    y
  }
) %>% tibble::as_tibble()

################################################################################
logger("Post-processing") ######################################################
################################################################################

logger("Generating Venn Diagram (ggvenn)", 60, cyan)
color_palette <- RColorBrewer::brewer.pal(
  name = "Set3", n = length(panels_list)
)
`%+replace%` <- ggplot2::`%+replace%`
outputs_list[["overlaps_ggvenn"]] <- ggvenn::ggvenn(
  data = panels_list,
  fill_color = color_palette,
  stroke_size = 0.5, set_name_size = 5,
  show_percentage = TRUE
) +
  theme_global()$theme +
  ggplot2::theme_void()

logger("Generating Euler diagram (eulerr)", 60, cyan)
diagram <- eulerr::euler(panels_list)
fname <- file.path(output_resu, glue("overlaps_euler.png"))
# create directory if it does not exist
if (!dir.exists(dirname(fname))) {
  dir.create(dirname(fname), recursive = TRUE)
}
png(fname);
plot(
  diagram, counts = TRUE, font = 1, cex = 1, alpha = 0.5,
  fill = color_palette,
  labels = list(size = 10, alpha = 0.5),
  quantities = list(size = 10),
  main = "Overlapping genes in Xenium panels"
)
graphics.off()

# outputs_list[["overlaps_euler_do_call"]] <- list(
#   "do.call" = list(
#     what = plot,
#     args = list(
#       diagram, counts = TRUE, font = 1, cex = 1, alpha = 0.5,
#       fill = color_palette,
#       labels = list(size = 10, alpha = 0.5),
#       quantities = list(size = 10),
#       main = "Overlapping genes in Xenium panels"
#     )
#   ),
#   type = ".png"
# )

# outputs_list[["overlaps_euler_ggplotify"]] <- ggplotify::as.ggplot(diagram) +
#   theme_global()$theme + ggplot2::theme_void()

outputs_list[["overlaps_euler_gg"]] <- ggeulerr(panels_list) +
  ggplot2::scale_fill_manual(values = color_palette) +
  ggplot2::labs(title = "Overlapping genes in Xenium panels") +
  theme_global()$theme + ggplot2::theme_void()

logger("Generating UpSet plot (UpSetR)", 60, cyan)
p <- UpSetR::upset(
  UpSetR::fromList(panels_list),
  sets = names(panels_list),
  order.by = "freq",
  main.bar.color = "black",
  sets.bar.color = color_palette,
  point.size = 3.5
)
fname <- file.path(output_resu, glue("overlaps_upset.png"))
png(fname);
print(p)
graphics.off()

intersect_all_previous <- c(
  "CCL19", "CCND1", "CCR7", "CD3E", "CD68", "CD79A", "CD83", "CD8A", "CDK1",
  "CENPF", "CLEC10A", "CXCL12", "CXCR4", "GATA2", "ID4", "IL2RA", "IRF4",
  "IRF8", "KIT", "LCK", "MKI67", "MZB1", "NOTCH3", "PDGFRA", "PLVAP", "RGS5",
  "SOX17", "STMN1", "UBE2C", "IDO1"
)

smax <- max(nchar(names(res_overlap))) + 1
for (i in names(res_overlap)) {
  smax_i <- max(c(smax, nchar(i) + 1))
  y <- paste("##", i, "##", base::strrep("%", smax_i - nchar(i)), "\n")
  temp <- sum(res_overlap[[length(res_overlap)]] %in% res_overlap[[i]])
  cat(y, "In my overlaps ", temp, "\n", sep = "")
  cat(
    "Previous' all overlap in this set:",
    sum(intersect_all_previous %in% res_overlap[[i]]), "\n"
  )
}

################################################################################
logger("Conclusion") ###########################################################
################################################################################

# difference between sets
temp <- setdiff(res_overlap[[length(res_overlap)]], intersect_all_previous)
temp <- paste(temp, collapse = ", ")
logger_info(glue("Missing in previous overlap: {temp}"))

################################################################################
logger("Saving") ###############################################################
################################################################################

do.call(
  output_save_list,
  c(list(
    OUTPUT_LIST = outputs_list,
    OUTPUT_RESU = output_resu,
    width = 5.7 * 4, height = 4.3 * 4,
    unit = "cm"
  ), theme_global()$args_ggsave)
)