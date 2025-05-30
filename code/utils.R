#!/usr/bin/env R

# ------------------------------------------------------------------------------
# created: 2024-12-06 Fri 15:25:00 GMT
# updated: 2024-12-06
# version: 0.0.9
# status: Prototype
#
# maintainer: Ciro Ramírez-Suástegui
# author:
#   - name: Ciro Ramírez-Suástegui
#     affiliation: The Wellcome Sanger Institute
#     email: cs59@sanger.ac.uk, cramsuig@gmail.com
# ------------------------------------------------------------------------------

# Finding unique substrings in a list of strings
find_substring <- function(x) {
  # we need to create a matrix of columns equal to the longest string
  # and rows equal to the number of strings
  # then we fill the matrix with the characters of each string
  # and we compare the columns to find the unique characters
  # in each position
  m_left <- matrix(NA, nrow = length(x), ncol = max(nchar(x)))
  for (i in seq_along(x)) {
    m_left[i, 1:nchar(x[i])] <- strsplit(x[i], "")[[1]]
  }
  y <- sapply(x, function(i) {
    paste0(rev(strsplit(i, "")[[1]]), collapse = "")
  })
  m_right <- matrix(NA, nrow = length(y), ncol = max(nchar(x)))
  for (i in seq_along(y)) {
    m_right[i, 1:nchar(y[i])] <- strsplit(y[i], "")[[1]]
  }
  m_left_lengths <- apply(m_left, MARGIN = 2, function(i) {
    length(unique(i[!is.na(i)]))
  })
  m_right_lengths <- apply(m_right, MARGIN = 2, function(i) {
    length(unique(i[!is.na(i)]))
  })
  substr_start <- min(which(m_left_lengths > 1))
  substr_end <- min(which(m_right_lengths > 1))
  output <- list()
  output$name <- sapply(x, function(i) {
    substr(i, substr_start, nchar(i) - (substr_end - 1))
  })
  output$prefix <- substr(x[1], 1, substr_start - 1)
  output$suffix <- substr(x[1], nchar(x[1]) - (substr_end - 2), nchar(x[1]))
  return(output)
}

# inputs_file <- "data/20240815__115640__SGP177_SKI_run1"
# `%>%` <- dplyr::`%>%`
# metrics_files <- inputs_file %>%
#   list.dirs(recursive = FALSE) %>%
#   stringr::str_subset("0032785|FFPE") %>%
#   basename()

# unname(find_substring(metrics_files))