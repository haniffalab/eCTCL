# Load required libraries
library(ggplot2)
library(dplyr)

# -----------------------------
# Define shared colour palette and theme
# -----------------------------

main_col <- "#00796B"     # Teal for CTCL / MF
accent_col <- "#80CBC4"   # Light teal for subtypes
muted_col <- "grey80"     # For background bars

theme_viva <- theme_minimal(base_size = 13) +
  theme(
    panel.grid.major.y = element_blank(),
    legend.position = "none",
    plot.title = element_text(face = "bold", size = 14, hjust = -0.5),
    plot.subtitle = element_text(size = 11, hjust = 1),
    plot.caption = element_text(size = 9, hjust = 1),
    axis.title = element_text(size = 12)
  )

# -----------------------------
# Plot 1: Incidence comparison
# -----------------------------

temp <- c("All cancers", "All lymphomas", "Non-Hodgkin lymphomas", "CTCL")
incidence_data <- data.frame(
  Disease = factor(x = temp, levels = temp),
  # Incidence = c(450, 20, 18, 0.5)
  Incidence = c(196, 7.2 + 1, 7.2, 0.8)
)

incidence_data$Highlight <- ifelse(
  incidence_data$Disease == "CTCL", "CTCL", "Other"
)

caption_str <- c(
  "Sources: WCRF, Huang et al. 2022, Tang et al. 2025, Cai et al. 2022"
)
subtitle_str <- "Age-standardized incidence rate (ASIR) per 100,000 people (aproximate)."
p1 <- ggplot(
    incidence_data,
    aes(x = Disease, y = Incidence, fill = Highlight)
  ) +
    geom_bar(stat = "identity", width = 0.7) +
    scale_y_continuous(expand = expansion(mult = c(0, 0.1))) +
    coord_flip() +
    scale_fill_manual(values = c("CTCL" = main_col, "Other" = muted_col)) +
    geom_text(
      aes(label = Incidence),
      hjust = -0.1, size = 4, colour = "black"
    ) +
    labs(
      title = "CTCL compared to other cancers",
      subtitle = subtitle_str, width = 40,
      caption = caption_str,
      y = "Incidence rate", x = NULL
    ) +
    theme_viva

# https://www.wcrf.org/preventing-cancer/cancer-statistics/global-cancer-data-by-country

# -----------------------------
# Plot 2: CTCL subtype composition (donut)
# -----------------------------

ctcl_data <- data.frame(
  Subtype = c(
    "Mycosis fungoides (MF)", "Sézary syndrome (SS)", "CD30+ LPD", "Others"
  ),
  Proportion = c(0.65, 0.10, 0.20, 0.05)
)

ctcl_data <- ctcl_data %>%
  arrange(desc(Subtype)) %>%
  mutate(
    fraction = Proportion / sum(Proportion),
    ymax = cumsum(fraction),
    ymin = c(0, head(ymax, n = -1)),
    labelPosition = (ymax + ymin) / 2,
    label = paste0(Subtype, "\n", round(Proportion * 100), "%")
  )

p2 <- ggplot(ctcl_data, aes(ymax = ymax, ymin = ymin, xmax = 4, xmin = 3, fill = Subtype)) +
  geom_rect(color = "white") +
  coord_polar(theta = "y") +
  xlim(c(2, 5)) +  # extended to make room for labels
  # Connector lines
  geom_segment(
    aes(
      x = 4, xend = 4.3,
      y = labelPosition, yend = labelPosition
    ),
    color = "grey70", linewidth = 0.4
  ) +
  # External labels
  geom_text(
    aes(x = 4.5, y = labelPosition, label = label),
    color = "black", size = 3.5, lineheight = 0.9, hjust = 0
  ) +
  scale_fill_manual(values = c(
    "Mycosis fungoides (MF)" = main_col,
    "Sézary syndrome (SS)" = accent_col,
    "CD30+ LPD" = "#4DB6AC",
    "Others" = "#B2DFDB"
  )) +
  labs(title = "CTCL subtype composition") +
  theme_void(base_size = 13) +
  theme(
    legend.position = "none",
    plot.title = element_text(face = "bold", size = 14, hjust = 0.5)
  )


# -----------------------------
# Export for PowerPoint
# -----------------------------

ggsave("figures/CTCL_incidence_viva.png", p1, width = 6, height = 4, dpi = 300)
ggsave("figures/CTCL_subtypes_viva.png", p2, width = 4, height = 4, dpi = 300)
