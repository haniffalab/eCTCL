#!/usr/bin/env R

# ------------------------------------------------------------------------------
# title: Comparing Xenium panels.
# purpose: We are fetching panels to compare the overapping genes and the
#           cell types they target.
#
# created: 2025-02-04 Tue 08:53:59 GMT
# updated: 2025-02-04
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
# FNM=code/comparison_overlaps_panel
# Rscript ${FNM}.R 2>&1 | tee -a .logs/${FNM/\//.}_$(date +%Y%m%d%-H%M%S)

## Environment setup ## %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# Quick installations --------------------------------------
# Basic packages -------------------------------------------
# Logging configuration ------------------------------------
if (!requireNamespace("logging", quietly = TRUE))
  install.packages("logging", repos = "https://cloud.r-project.org")
if (requireNamespace("crayon", quietly = TRUE)) {
  red <- crayon::red
  yellow <- crayon::yellow
  cyan <- crayon::cyan
} else {
  red <- yellow <- cyan <- c
}
logging::basicConfig()
logger <- function(i, tail_n = 60, color = cyan) {
  tail_n <- max(c(tail_n, nchar(i) + 1))
  y <- paste("##", color(i), "##", base::strrep("%", tail_n - nchar(i)), "\n")
  logging::loginfo(y)
}
logging::loginfo(red("Verbosity activated."))
# In-house/developing --------------------------------------
url0 <- "https://raw.githubusercontent.com/cramsuig/"
url <- paste0(url0, "handy_functions/refs/heads/master/devel/overlap.R")
source(url)
# Tool (packaged) modules ----------------------------------
`%>%` <- dplyr::`%>%`

## Global configuration ## %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
glue <- stringr::str_glue
indata_name <- "panels-10x"
action_name <- "comparisons_overlapping"
result_name <- sprintf(
  "%s_%s_%s", indata_name, action_name, format(Sys.time(), "%Y%m%d-%H%M%S")
)

inputs_path <- "./data"
extent_strn <- "csv"
inputs_file <- file.path(
  inputs_path, "xenium-panels", glue("{indata_name}.{extent_strn}")
)

output_resu <- file.path("./results", glue("{result_name}"))
output_figs <- file.path("./results", glue("{result_name}"))
output_name <- gsub(glue(".{extent_strn}"), "", basename(inputs_file))
output_file <- file.path(
  inputs_path, "processed", glue("{output_name}_{action_name}.{extent_strn}")
)

outputs_list <- list()

temp <- sapply(ls(), function(x) class(get(x))) %in% c("list", "character")
temp <- ls()[temp & !grepl("opt", ls())]
str(sapply(temp, function(x) get(x)))

## Loading data ## %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
logging::loginfo("Downloading data.")
pfix <- "https://cdn.10xgenomics.com/raw/upload/v"
sfix <- "software-support/Xenium-panels/"
inputs_urls <- c(
    glue("{pfix}1699308550/{sfix}hSkin_panel_files/Xenium_hSkin_v1_metadata.csv"),
    glue("{pfix}1706911412/{sfix}hImmuno_Oncology_panel_files/Xenium_hIO_v1_metadata.csv"),
    glue("{pfix}1715726653/{sfix}/5K_panel_files/XeniumPrimeHuman5Kpan_tissue_pathways_metadata.csv")
)

for (i in seq_along(inputs_urls)) {
  file_name <- file.path(inputs_path, "xenium-panels", basename(inputs_urls[i]))
  if (file.exists(file_name)) {
    logging::loginfo(glue("File {file_name} already exists."))
    next
  }
  logging::loginfo(glue("Downloading {file_name}."))
  download.file(inputs_urls[i], file_name, mode = "wb")
}

logging::loginfo("Loading data.")
panels_df <- lapply(inputs_urls, readr::read_csv)
names(panels_df) <- gsub("_metadata|.csv", "", basename(inputs_urls))

## Pre processing ## %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
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

## Main routine ## %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
logger("Calculating overlaps.")
res_overlap <- overlap_list(panels_list, v = TRUE)
str(res_overlap)

smax <- sapply(res_overlap, length)
outputs_list[["overlaps"]] <- sapply(
  X = res_overlap,
  FUN = function(x) {
    y <- x[1:smax]
    y[is.na(y)] <- ""
    return(y)
  }
) %>% tibble::as_tibble()

## Post processing ## %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
intersect_all_elias <- c(
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
  cat("Elias' overlap", sum(intersect_all_elias %in% res_overlap[[i]]), "\n")
}

## Conclusions ## %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# difference between sets
temp <- setdiff(res_overlap[[length(res_overlap)]], intersect_all_elias)
temp <- paste(temp, collapse = ", ")
logging::loginfo(glue("Missing in Elias' overlap: {temp}"))

## Save ## %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
logging::loginfo("Saving results.")
if (!dir.exists(output_resu)) {
  dir.create(output_resu, recursive = TRUE)
}
readr::write_csv(
  x = outputs_list[["overlaps"]],
  file = glue("{output_resu}/overlaps.csv")
)
