#!/usr/bin/env Rscript
# One command builds everything:
#   Rscript run_pipeline.R                    # load data, build, test, render CHI's next opponent
#   Rscript run_pipeline.R --skip-load        # reuse data/nfl.duckdb (fast, for SQL work)
#   Rscript run_pipeline.R --no-render        # stop after the data tests
#   Rscript run_pipeline.R --date=2026-12-15  # pretend today is this date
#   Rscript run_pipeline.R --team=DET         # scout DET's next opponent instead
#   Rscript run_pipeline.R --opponent=GB --week=16   # render one specific matchup for the team
#   Rscript run_pipeline.R --update           # midweek refresh: injuries, lines, weather only
#   Rscript run_pipeline.R --focal-only       # skip the one-pagers for every other team

source("R/pipeline.R")

arg <- function(name, default = NULL) {
  hit <- grep(paste0("^--", name, "(=|$)"), commandArgs(trailingOnly = TRUE), value = TRUE)
  if (length(hit) == 0) return(default)
  if (!grepl("=", hit[1])) return(TRUE)
  sub(paste0("^--", name, "="), "", hit[1])
}

team     <- arg("team", Sys.getenv("FOCAL_TEAM", "CHI"))
run_date <- as.Date(arg("date", Sys.getenv("REPORT_DATE", as.character(Sys.Date()))))
db_path  <- "data/nfl.duckdb"

con <- connect_db(db_path)
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

if (!isTRUE(arg("skip-load", FALSE))) {
  season <- nflreadr::most_recent_season()
  load_raw_data(con, (season - 2):season)
}
load_manual_trades(con)
load_stadiums(con)
load_gamebook_weather(con)
if (!isTRUE(arg("skip-load", FALSE)) || !dbExistsTable(con, "raw_weather_hourly")) {
  fetch_weather(con, run_date)
}
build_models(con)
run_data_tests(con)

# Update runs (Thursday, Saturday, Sunday and Monday mornings; see
# .github/workflows/weekly-report.yml) refresh the live page's data for the
# week already published: injury reports, lines and the game-day forecast.
# They render no report and leave the archive alone.
if (isTRUE(arg("update", FALSE))) {
  week <- find_update_week(con, run_date)
  # Also the league's current week when the focal team is on bye that week.
  weeks <- unique(rbind(week, find_league_week(con, run_date)))
  if (nrow(weeks) == 0) {
    message("Update: no published week with games still to play. Nothing to refresh.")
    quit(save = "no", status = 0)
  }
  for (i in seq_len(nrow(weeks))) {
    export_site_data(con, weeks$season[i], weeks$week[i], team)
    export_predictions(con, weeks$season[i], weeks$week[i], run_date)
    message(sprintf("Update: refreshed %d week %d", weeks$season[i], weeks$week[i]))
  }
  quit(save = "no", status = 0)
}

if (isTRUE(arg("no-render", FALSE))) quit(save = "no")

opponent <- arg("opponent")
if (!is.null(opponent)) {
  week <- as.integer(arg("week"))
  games <- dbGetQuery(con, "SELECT * FROM stg_team_games WHERE team = ? AND opponent = ? AND week = ?
                            ORDER BY season DESC LIMIT 1", params = list(team, opponent, week))
  if (nrow(games) == 0) stop("No game found: ", team, " vs ", opponent, " week ", week)
} else {
  games <- tryCatch(find_next_game(con, team, run_date), error = function(e) {
    message(conditionMessage(e), "\nFalling back to every matchup in the next scheduled week.")
    find_next_week_matchups(con, run_date)
  })
}
if (nrow(games) == 0) {
  # Off-season (e.g. after the Super Bowl): nothing to do, and not an error.
  message("Nothing scheduled on or after ", run_date, ". No report this week.")
  quit(save = "no", status = 0)
}

for (i in seq_len(nrow(games))) {
  check_trades(con, games[i, ])
  write_draft_notes(con, games[i, ])
}

# All 32 teams for the report week, for the live page. When the focal team is
# on bye, the league's current week comes first, so the page still has this
# weekend's games for every other team.
league <- find_league_week(con, run_date)
if (nrow(league) == 1 && (league$season != games$season[1] || league$week != games$week[1])) {
  export_site_data(con, league$season, league$week, team)
  export_predictions(con, league$season, league$week, run_date)
}
export_site_data(con, games$season[1], games$week[1], team)
export_report_cards(con, games$season[1])
export_predictions(con, games$season[1], games$week[1], run_date)

# Every game in the live page's week (the league's current week), for the
# one-pager each team's scouting page links to. Read now, before the
# connection closes.
league_games <- if (nrow(league) == 1 && !isTRUE(arg("focal-only", FALSE))) {
  dbGetQuery(con, "SELECT game_id, season, week, game_type, gameday, team, opponent, is_home
                   FROM stg_team_games WHERE season = ? AND week = ?
                   ORDER BY gameday, game_id, is_home", params = list(league$season, league$week))
} else NULL

# Close the write connection so Quarto can open the database read-only.
dbDisconnect(con, shutdown = TRUE)
on.exit()

slugs <- character()
for (i in seq_len(nrow(games))) {
  message(sprintf("Scouting %s for %s, %d week %d (%s)", games$opponent[i], games$team[i],
                  games$season[i], games$week[i], format(games$gameday[i])))
  slugs <- c(slugs, render_report(games[i, ], db_path))
}
if (!is.null(league_games)) render_league_reports(league_games, db_path, skip = games)
# Feature the report rendered first: the focal team's game, or the earliest
# game of the week in the playoff fallback.
build_site(latest = slugs[1])
