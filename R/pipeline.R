# Pipeline steps. run_pipeline.R calls these in order:
#   load_raw_data() -> build_models() -> run_data_tests() -> find_next_game()
#   -> export_site_data() -> render_report() -> build_site()

library(DBI)
library(duckdb)

# Only the play-by-play columns the models use, so the database stays small.
PBP_COLUMNS <- c(
  "game_id", "play_id", "season", "season_type", "week", "posteam", "defteam",
  "play_type", "pass", "rush", "shotgun", "no_huddle", "down", "ydstogo",
  "yardline_100", "half_seconds_remaining", "score_differential", "wp",
  "xpass", "epa", "success",
  # gsis ids of the dropback QB (incl. sacks and scrambles), ball carrier on
  # designed runs, and target: the trade check measures a player's usage with them
  "passer_id", "rusher_id", "receiver_id",
  # depth of the target, for the top-receiver model (deep = 20+ air yards),
  # and yards gained, for production allowed by position on defense
  "air_yards", "yards_gained",
  # where the play went: run lane (left/middle/right x end/tackle/guard) and
  # pass area (left/middle/right x short/deep), for play_direction
  "run_location", "run_gap", "pass_location", "pass_length"
)

# Side feeds for the trade check. Each has a fixed column list so a failed
# download can still write an empty table with the right shape.
TRADE_COLUMNS <- c("trade_id", "season", "trade_date", "gave", "received",
                   "pick_season", "pick_round", "pfr_id", "pfr_name")
SNAP_COLUMNS <- c("game_id", "season", "week", "player", "pfr_player_id", "position",
                  "team", "offense_snaps", "offense_pct", "defense_snaps", "defense_pct")
PLAYER_COLUMNS <- c("gsis_id", "pfr_id", "display_name", "position")
ROSTER_COLUMNS <- c("season", "week", "game_type", "team", "status", "full_name",
                    "position", "gsis_id", "pfr_id")

connect_db <- function(path = "data/nfl.duckdb", read_only = FALSE) {
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  dbConnect(duckdb(), dbdir = path, read_only = read_only)
}

# Pull nflverse data and write it to raw_* tables. Nothing is transformed here:
# all logic lives in the SQL models.
load_raw_data <- function(con, seasons) {
  message("Loading play-by-play for ", paste(seasons, collapse = ", "))
  pbp <- nflreadr::load_pbp(seasons)
  pbp <- as.data.frame(pbp)[, PBP_COLUMNS]
  if (nrow(pbp) == 0) stop("load_pbp() returned no rows")

  schedules <- as.data.frame(nflreadr::load_schedules(seasons))
  # Every season since 2017, for the Elo ratings (sql/models/32_elo_ratings.sql).
  schedules_history <- as.data.frame(nflreadr::load_schedules(2017:max(seasons)))
  teams <- as.data.frame(nflreadr::load_teams(current = TRUE))

  dbWriteTable(con, "raw_pbp", pbp, overwrite = TRUE)
  dbWriteTable(con, "raw_schedules", schedules, overwrite = TRUE)
  dbWriteTable(con, "raw_schedules_history", schedules_history, overwrite = TRUE)
  dbWriteTable(con, "raw_teams", teams, overwrite = TRUE)

  feeds <- rbind(
    load_side_feed(con, "raw_trades", TRADE_COLUMNS, function() {
      trades <- nflreadr::load_trades()
      trades[trades$season %in% seasons, ]
    }),
    load_side_feed(con, "raw_snap_counts", SNAP_COLUMNS, function() nflreadr::load_snap_counts(seasons)),
    load_side_feed(con, "raw_players", PLAYER_COLUMNS, function() nflreadr::load_players()),
    load_side_feed(con, "raw_rosters_weekly", ROSTER_COLUMNS, function() nflreadr::load_rosters_weekly(seasons))
  )
  dbWriteTable(con, "raw_feed_status", feeds, overwrite = TRUE)
  message(sprintf("raw_pbp: %s plays, raw_schedules: %s games",
                  format(nrow(pbp), big.mark = ","), nrow(schedules)))
  invisible(TRUE)
}

# The trade check's feeds are not worth stopping the weekly report for: if one
# fails to download, write an empty table with the same columns, and record the
# failure in raw_feed_status so the report can say the check was incomplete.
load_side_feed <- function(con, table, columns, fetch) {
  df <- tryCatch(as.data.frame(fetch()), error = function(e) {
    message("WARNING: ", table, " feed failed: ", conditionMessage(e))
    NULL
  })
  ok <- !is.null(df) && all(columns %in% names(df))
  if (!is.null(df) && !ok) {
    message("WARNING: ", table, " feed is missing columns: ",
            paste(setdiff(columns, names(df)), collapse = ", "))
  }
  df <- if (ok) df[, columns, drop = FALSE] else
    as.data.frame(setNames(replicate(length(columns), character(), simplify = FALSE), columns))
  dbWriteTable(con, table, df, overwrite = TRUE)
  message(sprintf("%s: %s rows%s", table, format(nrow(df), big.mark = ","), if (ok) "" else " (feed failed)"))
  data.frame(feed = table, ok = ok, rows = nrow(df), loaded_at = Sys.time())
}

# Trades nflverse hasn't published yet, typed in by hand (config/trades_manual.csv).
# Loaded on every run, including --skip-load, because the file lives in the repo.
# Once nflverse has a trade, its manual row is ignored (see 06_stg_trades.sql).
load_manual_trades <- function(con, path = "config/trades_manual.csv") {
  manual <- read.csv(path, colClasses = "character", na.strings = "", comment.char = "#")
  dbWriteTable(con, "raw_trades_manual", manual, overwrite = TRUE)
  message("raw_trades_manual: ", nrow(manual), " rows")
  invisible(manual)
}

# Run every .sql file in a folder, in file-name order (01_, 02_, 10_, ...).
build_models <- function(con, dir = "sql/models") {
  files <- sort(list.files(dir, pattern = "\\.sql$", full.names = TRUE))
  for (f in files) {
    sql <- paste(readLines(f, warn = FALSE), collapse = "\n")
    dbExecute(con, sql)
    message("built ", basename(f))
  }
  invisible(files)
}

# A data test is a query that must return zero rows. Any rows are failures.
run_data_tests <- function(con, dir = "sql/tests") {
  files <- sort(list.files(dir, pattern = "\\.sql$", full.names = TRUE))
  failed <- character()
  for (f in files) {
    sql <- paste(readLines(f, warn = FALSE), collapse = "\n")
    bad_rows <- dbGetQuery(con, sql)
    if (nrow(bad_rows) == 0) {
      message("PASS ", basename(f))
    } else {
      message("FAIL ", basename(f), " (", nrow(bad_rows), " rows)")
      print(utils::head(bad_rows, 10))
      failed <- c(failed, basename(f))
    }
  }
  if (length(failed) > 0) {
    stop(length(failed), " data test(s) failed: ", paste(failed, collapse = ", "))
  }
  invisible(TRUE)
}

# The focal team's next game on or after `on_date`. The report for that game
# uses the snapshot as of its week, i.e. only games from earlier weeks.
find_next_game <- function(con, team = "CHI", on_date = Sys.Date()) {
  game <- dbGetQuery(con, "
    SELECT game_id, season, week, game_type, gameday, team, opponent, is_home
    FROM stg_team_games
    WHERE team = ? AND gameday >= ?
    ORDER BY gameday
    LIMIT 1", params = list(team, as.Date(on_date)))
  if (nrow(game) == 0) {
    stop("No upcoming game for ", team, " on or after ", on_date,
         ". Season over? Pass --opponent=XXX --week=N to pick a matchup.")
  }
  game
}

# When the focal team has no game left (eliminated or season over), scout both
# sides of every game in the next scheduled week instead, so reports keep
# publishing through the playoffs.
find_next_week_matchups <- function(con, on_date = Sys.Date()) {
  dbGetQuery(con, "
    WITH next_week AS (
      SELECT season, week
      FROM stg_team_games
      WHERE gameday >= ?
      ORDER BY gameday
      LIMIT 1
    )
    SELECT g.game_id, g.season, g.week, g.game_type, g.gameday, g.team, g.opponent, g.is_home
    FROM stg_team_games g
    JOIN next_week w ON w.season = g.season AND w.week = g.week
    ORDER BY g.gameday, g.game_id, g.is_home", params = list(as.Date(on_date)))
}

# Fill {{name}} placeholders in a .sql file and run it. Values are integers,
# team abbreviations checked by the caller, or strings built here, never free text.
run_sql_template <- function(con, file, ...) {
  sql <- paste(readLines(file, warn = FALSE), collapse = "\n")
  vals <- list(...)
  for (k in names(vals)) sql <- gsub(paste0("{{", k, "}}"), vals[[k]], sql, fixed = TRUE)
  dbExecute(con, sql)
}

# "Updated" stamp for the JSON exports, made in R rather than SQL: DuckDB's
# timestamp formatting failed to bind in CI (first Actions run, Nov 5, 2026).
updated_stamp <- function() format(Sys.time(), "%Y-%m-%d %H:%M UTC", tz = "UTC")

# Data for the live page (site/scout.html): one JSON file per report week with
# every team's numbers, plus data/index.json listing the weeks on disk. Runs
# after the data tests, so it only ever exports tested tables.
export_site_data <- function(con, season, week, focal_team, site_dir = "site") {
  stopifnot(grepl("^[A-Z]{2,3}$", focal_team))
  data_dir <- file.path(site_dir, "data")
  dir.create(data_dir, showWarnings = FALSE, recursive = TRUE)
  path <- file.path(normalizePath(data_dir), sprintf("%d-week%02d.json", as.integer(season), as.integer(week)))
  run_sql_template(con, "sql/export/site_week.sql",
                   season = as.integer(season), week = as.integer(week),
                   focal_team = focal_team, path = path, updated = updated_stamp())
  run_sql_template(con, "sql/export/site_index.sql", dir = normalizePath(data_dir))
  message("exported ", path)
  invisible(path)
}

# Writes site/data/predictions-<season>.json: the model's win % for every game,
# locked. The report week's games are added the first time a run sees them
# before game day, and a locked row is never rewritten, so a later run (or a
# model change) can't change a call after the fact. Results and grades are
# filled in from the schedule on every run.
export_predictions <- function(con, season, week, run_date, site_dir = "site") {
  data_dir <- file.path(site_dir, "data")
  dir.create(data_dir, showWarnings = FALSE, recursive = TRUE)
  path <- file.path(normalizePath(data_dir), sprintf("predictions-%d.json", as.integer(season)))
  if (file.exists(path)) {
    dbExecute(con, sprintf("CREATE OR REPLACE TABLE raw_prediction_locks AS
      SELECT game_id, model_home_win, market_home_win, home_line, total_line, model_version, locked_at
      FROM (SELECT unnest(games, recursive := true) FROM read_json('%s'))", path))
  } else {
    dbExecute(con, "CREATE OR REPLACE TABLE raw_prediction_locks (game_id VARCHAR, model_home_win DOUBLE,
      market_home_win DOUBLE, home_line DOUBLE, total_line DOUBLE, model_version VARCHAR, locked_at VARCHAR)")
  }
  run_sql_template(con, "sql/export/site_predictions.sql", season = as.integer(season),
                   week = as.integer(week), run_date = format(as.Date(run_date)), path = path,
                   updated = updated_stamp())
  message("exported ", path)
  invisible(path)
}

# Writes site/data/report-cards-<season>.json: every graded matchup of the
# season (the condensed notes and what happened) for the archive page.
export_report_cards <- function(con, season, site_dir = "site") {
  data_dir <- file.path(site_dir, "data")
  dir.create(data_dir, showWarnings = FALSE, recursive = TRUE)
  path <- file.path(normalizePath(data_dir), sprintf("report-cards-%d.json", as.integer(season)))
  run_sql_template(con, "sql/export/site_report_cards.sql", season = as.integer(season), path = path,
                   updated = updated_stamp())
  message("exported ", path)
  invisible(path)
}

# The generated first draft of the staff notes for one opponent, as Markdown in
# site/notes/drafts/. The wording comes from sql/models/30_draft_notes.sql. To
# publish your own version, copy it to site/notes/ (same file name) and edit;
# the live page shows site/notes/ first and falls back to the draft.
write_draft_notes <- function(con, game, dir = "site/notes/drafts") {
  stopifnot(grepl("^[A-Z]{2,3}$", game$opponent))
  lines <- dbGetQuery(con, "
    SELECT kind, text FROM draft_notes
    WHERE season = ? AND week = ? AND team = ?
    ORDER BY line", params = list(game$season, game$week, game$opponent))
  if (nrow(lines) == 0) {
    message("No draft notes for ", game$opponent, " (no games yet this season)")
    return(invisible(NULL))
  }
  body <- ifelse(lines$kind == "h", paste("##", lines$text),
          ifelse(lines$kind == "li", paste("-", lines$text), lines$text))
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  path <- file.path(dir, paste0(report_slug(game$season, game$week, game$opponent), ".md"))
  writeLines(c(sprintf("# %s, Week %d (draft)", game$opponent, as.integer(game$week)),
               "Draft: generated from the data. Edit it and save it as site/notes/<same name> to publish your version.",
               body), path)
  message("draft notes: ", path)
  invisible(path)
}

# The trade check, printed to the run log. Lists every player who joined or
# left either team this season before this game (trades, plus moves seen in
# weekly rosters), and warns when one was a regular for the opponent: the
# report's season (and maybe last-4) numbers were built with a roster that no
# longer exists. On GitHub Actions the warnings also show as annotations on
# the run's summary page. Same rows as the report's Roster changes box.
check_trades <- function(con, game) {
  moves <- dbGetQuery(con, "
    SELECT * FROM trade_impact
    WHERE season = ? AND as_of_week = ? AND trade_date < ?
      AND (from_team IN (?, ?) OR to_team IN (?, ?))
    ORDER BY trade_date, player_name",
    params = list(game$season, game$week, as.Date(game$gameday),
                  game$team, game$opponent, game$team, game$opponent))
  status <- dbGetQuery(con, "SELECT * FROM trade_feed_status")
  if (!isTRUE(as.logical(status$feeds_ok))) {
    warn_run("Trade check incomplete: the trade or roster feed failed (see raw_feed_status)")
  }
  if (nrow(moves) == 0) {
    message("Trade check: no in-season moves involving ", game$team, " or ", game$opponent)
    return(invisible(moves))
  }
  for (i in seq_len(nrow(moves))) {
    m <- moves[i, ]
    message(sprintf("Trade check: %s %s %s %s -> %s (%s)%s", format(as.Date(m$trade_date)),
                    ifelse(is.na(m$position), "", m$position), m$player_name,
                    m$from_team, m$to_team, m$move_type, if (isTRUE(as.logical(m$is_key))) " [regular]" else ""))
  }
  key <- moves[moves$is_key & (moves$from_team == game$opponent | moves$to_team == game$opponent), ]
  if (nrow(key) > 0) {
    warn_run(sprintf("%s week %d: %s changed teams; %s's tendencies are partly from before",
                     game$opponent, game$week, paste(key$player_name, collapse = ", "), game$opponent))
  }
  roster_only <- moves[moves$move_type == "roster move" & moves$is_key, ]
  if (nrow(roster_only) > 0) {
    warn_run(sprintf("Seen in weekly rosters but not in any trade list: %s. If it was a trade, add it to config/trades_manual.csv",
                     paste(sprintf("%s (%s -> %s)", roster_only$player_name, roster_only$from_team,
                                   roster_only$to_team), collapse = ", ")))
  }
  invisible(moves)
}

warn_run <- function(text) {
  message("WARNING: ", text)
  if (identical(Sys.getenv("GITHUB_ACTIONS"), "true")) cat("::warning title=Trade check::", text, "\n", sep = "")
}

report_slug <- function(season, week, opponent) {
  sprintf("%d-week%02d-%s", as.integer(season), as.integer(week), opponent)
}

# Render the one-pager for one opponent. Writes site/reports/<slug>.html (and
# .pdf when Chrome is available) and returns the slug.
render_report <- function(game, db_path = "data/nfl.duckdb", out_dir = "site/reports") {
  slug <- report_slug(game$season, game$week, game$opponent)
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  args <- c(
    "render", "opponent_report.qmd",
    "--output", paste0(slug, ".html"),
    "-P", paste0("opponent:", game$opponent),
    "-P", paste0("focal_team:", game$team),
    "-P", paste0("season:", game$season),
    "-P", paste0("week:", game$week),
    "-P", paste0("gameday:", format(as.Date(game$gameday))),
    "-P", paste0("is_home:", tolower(as.character(game$is_home))),
    "-P", paste0("db_path:", normalizePath(db_path))
  )
  # Render from inside report/ so Quarto finds report.css and the figures.
  old_wd <- setwd("report")
  on.exit(setwd(old_wd), add = TRUE)
  status <- system2("quarto", args)
  setwd(old_wd)
  if (status != 0) stop("quarto render failed for ", slug)

  html <- file.path(out_dir, paste0(slug, ".html"))
  file.rename(file.path("report", paste0(slug, ".html")), html)
  print_pdf(html)
  message("rendered ", html)
  slug
}

# PDF = the same HTML printed by headless Chrome, so both formats match.
# Skipped (with a message) if no Chrome is installed.
print_pdf <- function(html) {
  chrome <- Sys.getenv("CHROME_PATH", unset = "")
  if (chrome == "") {
    candidates <- c("google-chrome", "google-chrome-stable", "chromium", "chromium-browser")
    found <- Sys.which(candidates)
    chrome <- unname(found[found != ""][1])
  }
  if (is.na(chrome) || chrome == "") {
    message("no Chrome found; skipping PDF")
    return(invisible(NULL))
  }
  pdf <- sub("\\.html$", ".pdf", html)
  system2(chrome, c("--headless", "--disable-gpu", "--no-sandbox",
                    "--no-pdf-header-footer",
                    paste0("--print-to-pdf=", normalizePath(dirname(pdf)), "/", basename(pdf)),
                    paste0("file://", normalizePath(html))),
          stdout = FALSE, stderr = FALSE)
  invisible(pdf)
}

# Rebuild the landing page (latest report + archive) from the reports folder.
# The archive is just every report file on disk, newest first. `latest` is the
# report the landing page features; by default the newest file by name.
build_site <- function(site_dir = "site", latest = NULL) {
  files <- list.files(file.path(site_dir, "reports"), pattern = "\\.html$")
  if (length(files) == 0) stop("no reports to publish")
  slugs <- sort(sub("\\.html$", "", files), decreasing = TRUE)
  parts <- regmatches(slugs, regexec("^(\\d{4})-week(\\d{2})-([A-Z]+)$", slugs))
  rows <- vapply(seq_along(slugs), function(i) {
    p <- parts[[i]]
    pdf <- file.exists(file.path(site_dir, "reports", paste0(slugs[i], ".pdf")))
    sprintf('<li><a href="reports/%s.html">%s Week %d: %s</a>%s</li>',
            slugs[i], p[2], as.integer(p[3]), p[4],
            if (pdf) sprintf(' · <a href="reports/%s.pdf">PDF</a>', slugs[i]) else "")
  }, character(1))
  if (is.null(latest)) latest <- slugs[1]
  if (!latest %in% slugs) stop("latest report ", latest, " not found in ", site_dir, "/reports")

  template <- paste(readLines(file.path(site_dir, "index_template.html"), warn = FALSE),
                    collapse = "\n")
  page <- gsub("{{LATEST}}", latest, template, fixed = TRUE)
  page <- sub("{{ARCHIVE}}", paste(rows, collapse = "\n"), page, fixed = TRUE)
  page <- sub("{{UPDATED}}", format(Sys.time(), "%Y-%m-%d %H:%M UTC", tz = "UTC"), page, fixed = TRUE)
  writeLines(page, file.path(site_dir, "index.html"))
  message("site index: latest = ", latest, ", ", length(slugs), " report(s) in archive")
  invisible(latest)
}
