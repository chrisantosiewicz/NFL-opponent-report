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

MAX_MOVES <- 5
KEY_MARK <- "&#9888;"  # warning sign, as an HTML entity so the R locale doesn't matter

# Roster changes panel. `moves` is trade_impact for this report: every player
# who joined or left either team this season before the game. Trades are all
# listed; moves seen only in weekly rosters are listed when the player was a
# regular, so depth churn doesn't crowd the page.
trades_panel <- function(moves, opp, focal, feed, gameday) {
  moves <- moves[moves$move_type == "trade" | moves$is_key, ]
  out <- character()
  key_opp <- moves[moves$is_key & (moves$from_team == opp | moves$to_team == opp), ]

  key_focal <- moves[moves$is_key & (moves$from_team == focal | moves$to_team == focal), ]
  any_opp <- any(moves$from_team == opp | moves$to_team == opp)
  title <- if (nrow(key_opp) > 0) {
    sprintf("Roster changes: %s %s", opp, paste(move_phrase(key_opp, opp), collapse = ", "))
  } else if (any_opp) {
    sprintf("Roster changes: no %s regulars have moved", opp)
  } else {
    sprintf("Roster changes: no in-season trades for %s", opp)
  }
  if (nrow(key_focal) > 0) {
    title <- paste0(title, "; ", focal, " ", paste(move_phrase(key_focal, focal), collapse = ", "))
  }
  out <- c(out, sprintf("<h3>%s</h3>", title))

  # At most MAX_MOVES rows keep the report on one page: regulars first, then
  # the most recent. The run log (check_trades) always lists every move.
  hidden <- max(nrow(moves) - MAX_MOVES, 0)
  moves <- utils::head(moves[order(!moves$is_key, -as.numeric(as.Date(moves$trade_date))), ], MAX_MOVES)

  if (nrow(moves) > 0) {
    # Each row is told from the side of the team in this matchup.
    side <- ifelse(moves$to_team == opp | moves$from_team == opp, opp, focal)
    joined <- moves$to_team == side
    since <- ifelse(joined, moves$to_games_since, moves$from_games_since)
    played <- ifelse(joined, moves$to_games, moves$from_games)
    rows <- data.frame(
      Date = format(as.Date(moves$trade_date), "%b %e"),
      Team = sprintf('<span class="move %s">%s %s</span>', ifelse(joined, "in", "out"),
                     side, ifelse(joined, "in", "out")),
      Player = paste0(ifelse(moves$is_key, sprintf('<span class="key" title="regular before the move">%s</span> ', KEY_MARK), ""),
                      ifelse(is.na(moves$position), "", paste0(moves$position, " ")),
                      moves$player_name),
      Move = paste0(ifelse(joined, paste("from", moves$from_team), paste("to", moves$to_team)),
                    ifelse(moves$move_type == "trade", "", " (roster)")),
      `Before the move` = vapply(seq_len(nrow(moves)), function(i) usage_phrase(moves[i, ]), ""),
      `Games since` = sprintf("%d of %d", as.integer(since), as.integer(played)),
      check.names = FALSE)
    out <- c(out, knitr::kable(rows, format = "html", escape = FALSE, row.names = FALSE,
                               table.attr = 'class="report-table"'))
  }

  if (nrow(key_opp) > 0) {
    # e.g. "SEA's numbers below cover 7 games, all 7 before Quenton Nelson
    # arrived and Christian Haynes left. The last-4 column has none after."
    joined <- key_opp$to_team == opp
    games <- max(ifelse(joined, key_opp$to_games, key_opp$from_games))
    since <- ifelse(joined, key_opp$to_games_since, key_opp$from_games_since)
    who <- paste(key_opp$player_name, ifelse(joined, "arrived", "left"))
    text <- if (length(unique(since)) == 1) {
      sprintf("%s's numbers below cover %d games, %s before %s. %s",
              opp, as.integer(games),
              if (since[1] == 0) paste("all", games) else as.character(games - since[1]),
              paste(who, collapse = " and "),
              if (since[1] == 0) "The last-4 column has none after." else
                sprintf("The last-4 column has %d after.", min(since[1], 4L)))
    } else {
      sprintf("%s's numbers below cover %d games: %s.", opp, as.integer(games),
              paste(sprintf("%d before %s", as.integer(games - since), who), collapse = "; "))
    }
    out <- c(out, sprintf('<p class="stale">%s %s</p>', KEY_MARK, text))
  }

  notes <- character()
  if (hidden > 0) notes <- c(notes, sprintf("%d more move%s in the run log.", hidden, if (hidden > 1) "s" else ""))
  if (!isTRUE(as.logical(feed$feeds_ok))) notes <- c(notes, "The trade or roster feed failed this run, so this list may be incomplete.")
  latest <- as.Date(feed$latest_feed_trade)
  if (!is.na(latest) && gameday - latest > 30) {
    notes <- c(notes, sprintf("nflverse's trade feed has nothing after %s; newer trades come from the hand-kept list and weekly rosters.",
                              format(latest, "%b %e, %Y")))
  }
  if (length(notes) > 0) out <- c(out, sprintf('<p class="n">%s</p>', paste(notes, collapse = " ")))
  paste(out, collapse = "\n")
}

# "added G Quenton Nelson" / "lost WR Marvin Harrison Jr."
move_phrase <- function(m, team) {
  paste(ifelse(m$to_team == team, "added", "lost"),
        ifelse(is.na(m$position), m$player_name, paste(m$position, m$player_name)))
}

# How much the player was used by the team he left, before the move.
usage_phrase <- function(m) {
  if (is.na(m$games_before) || m$games_before == 0) {
    return(sprintf("no snaps for %s", m$from_team))
  }
  pct <- if (m$side == "defense") m$def_snap_pct_before else m$off_snap_pct_before
  parts <- sprintf("%.0f%% of %s %s snaps, %d games", 100 * pct, m$from_team,
                   if (m$side == "defense") "def." else "off.", as.integer(m$games_before))
  share <- c(
    if (isTRUE(m$dropback_share >= 0.05)) sprintf("%.0f%% of dropbacks", 100 * m$dropback_share),
    if (isTRUE(m$target_share >= 0.05)) sprintf("%.0f%% of targets", 100 * m$target_share),
    if (isTRUE(m$carry_share >= 0.05)) sprintf("%.0f%% of carries", 100 * m$carry_share))
  paste(c(parts, share), collapse = ", ")
}
