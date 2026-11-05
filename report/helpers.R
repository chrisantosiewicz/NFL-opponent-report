# Formatting helpers and labels for the one-pager. Plain-language wording lives
# here so every panel says things the same way.

SITUATION_LABELS <- c(
  early_down     = "Early downs",
  third_short    = "3rd & 1-3",
  third_medium   = "3rd & 4-6",
  third_long     = "3rd & 7+",
  red_zone       = "Red zone",
  two_minute     = "2-minute",
  trailing_8plus = "Trailing by 8+",
  all_neutral    = "All neutral downs"
)

# "... passes {phrase}" in sentences
SITUATION_PHRASES <- c(
  early_down     = "on early downs",
  third_short    = "on 3rd & 1-3",
  third_medium   = "on 3rd & 4-6",
  third_long     = "on 3rd & 7+",
  red_zone       = "in the red zone",
  two_minute     = "in the 2-minute drill",
  trailing_8plus = "when trailing by 8+",
  all_neutral    = "on neutral downs"
)

METRIC_LABELS <- c(
  pass_rate    = "Pass rate",
  proe         = "Pass rate over expected",
  shotgun_rate = "Shotgun rate",
  epa_play     = "EPA per play",
  epa_pass     = "EPA per dropback",
  epa_run      = "EPA per run"
)

MIN_N <- 30  # below this, a number is shown but marked as a small sample

ordinal <- function(x) {
  x <- as.integer(x)
  suffix <- ifelse(x %% 100 %in% 11:13, "th",
            c("th", "st", "nd", "rd", rep("th", 6))[x %% 10 + 1])
  paste0(x, suffix)
}

fmt_value <- function(value, metric) {
  ifelse(is.na(value), "–",
  ifelse(metric %in% c("pass_rate", "shotgun_rate"), sprintf("%.0f%%", 100 * value),
  ifelse(metric == "proe", sprintf("%+.0f pts", 100 * value),
         sprintf("%+.2f", round(value, 2) + 0))))  # + 0 turns -0.00 into 0.00
}

fmt_rank <- function(rank, teams = 32) {
  ifelse(is.na(rank), "–", ordinal(rank))
}

fmt_n <- function(n) {
  ifelse(is.na(n), "–",
  ifelse(n < MIN_N, sprintf('<span class="small-n">%d*</span>', as.integer(n)),
         as.character(as.integer(n))))
}

# Rank 1 = highest value. For tendencies, "highest" is just a direction, not
# good or bad, so sentences say "most" / "fewest" instead of "best" / "worst".
rank_phrase <- function(rank, teams, metric) {
  high <- rank <= teams / 2
  pos <- if (high) rank else teams - rank + 1
  word <- switch(metric,
    pass_rate = if (high) "most pass-heavy" else "most run-heavy",
    proe = if (high) "most pass-heavy vs. expected" else "most run-heavy vs. expected",
    shotgun_rate = if (high) "most shotgun" else "most under center",
    epa_play = if (high) "most efficient offense" else "least efficient offense",
    epa_pass = if (high) "most efficient passing game" else "least efficient passing game",
    epa_run  = if (high) "most efficient running game" else "least efficient running game")
  if (pos == 1) paste0("the NFL's ", word) else paste0(ordinal(pos), "-", word)
}

# One sentence per "3 things to know" row.
three_things_sentence <- function(row) {
  sit <- SITUATION_LABELS[[row$situation]]
  val <- fmt_value(row$value, row$metric)
  avg <- fmt_value(row$league_avg, row$metric)
  what <- switch(row$metric,
    pass_rate    = sprintf("%s pass rate (league avg %s)", val, avg),
    proe         = sprintf("%s pass rate over expected", val),
    shotgun_rate = sprintf("%s in shotgun (league avg %s)", val, avg),
    epa_play     = sprintf("%s EPA per play (league avg %s)", val, avg),
    epa_pass     = sprintf("%s EPA per dropback (league avg %s)", val, avg),
    epa_run      = sprintf("%s EPA per run (league avg %s)", val, avg))
  sprintf("<strong>%s:</strong> %s, %s. <span class=\"n\">%d plays</span>",
          sit, rank_phrase(row$league_rank, row$league_teams, row$metric), what,
          as.integer(row$n))
}

# Tendency shift rule: last 4 games differ from season to date by at least
# 5 points (rates) or 0.10 (EPA), with at least MIN_N plays in the last 4.
shift_threshold <- function(metric) ifelse(grepl("^epa", metric), 0.10, 0.05)

theme_report <- function() {
  ggplot2::theme_minimal(base_size = 9) +
    ggplot2::theme(
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major.y = ggplot2::element_blank(),
      axis.title = ggplot2::element_text(size = 8, colour = "grey35"),
      legend.position = "top",
      legend.title = ggplot2::element_blank(),
      legend.margin = ggplot2::margin(0, 0, 0, 0),
      plot.margin = ggplot2::margin(2, 4, 2, 2),
      panel.spacing.x = ggplot2::unit(14, "pt")
    )
}
