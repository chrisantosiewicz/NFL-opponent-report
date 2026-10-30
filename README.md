# nfl-opponent-report

Every Tuesday during the NFL season, an automated pipeline pulls the latest NFL play-by-play, runs a set of SQL models in DuckDB, and publishes a one-page tendency report on the Chicago Bears' next opponent.

**Status:** pipeline built Oct 26, 2026 (models, tests, report, workflow). First automated report Tue Dec 15, 2026.

**Stack:** R (nflreadr) → DuckDB → `.sql` models run through DBI → data tests (queries that must return zero rows) → parameterized Quarto one-pager (HTML, plus PDF printed by headless Chrome) → GitHub Actions Tuesday cron → GitHub Pages with an archive.

## Run it

```sh
Rscript run_pipeline.R              # load data, build models, run tests, render CHI's next opponent
Rscript run_pipeline.R --skip-load  # reuse data/nfl.duckdb (fast while editing SQL)
Rscript run_pipeline.R --no-render  # stop after the data tests
Rscript run_pipeline.R --date=2026-12-15            # as if today were Dec 15
Rscript run_pipeline.R --opponent=GB --week=16      # one specific matchup
```

Needs R, Quarto, and the packages in `DESCRIPTION` (pinned in `renv.lock`: run `renv::restore()`).

## How it fits together

| Step | File | Output |
|------|------|--------|
| Load | `R/pipeline.R` `load_raw_data()` | `raw_pbp`, `raw_schedules`, `raw_teams` in `data/nfl.duckdb` |
| Staging | `sql/models/01_stg_plays.sql`, `02_dim_team.sql`, `03_stg_team_games.sql` | one row per scrimmage play with situation flags; 32 teams; one row per team per game |
| Tendencies | `sql/models/10_team_game_tendencies.sql` | counts and sums per team, game and situation |
| Rolling | `sql/models/11_team_rolling.sql` | season-to-date and last-4-games running totals (window frames) |
| Snapshot | `sql/models/12_tendency_snapshot.sql` | what was known before each week (as-of join; no leakage) |
| Ranks | `sql/models/13_tendency_ranks.sql`, `14_last_season_ranks.sql` | metric values, n, league rank, percentile; last season's ranks |
| "3 things" | `sql/models/15_three_things.sql` | top/bottom 10% on 30+ plays, one per situation |
| Trade check | `sql/models/04_team_alias.sql` … `06_stg_trades.sql`, `16_trade_impact.sql`, `17_trade_feed_status.sql`; `R/pipeline.R` `check_trades()` | every player who joined or left a team in-season, his usage before the move, games since; warnings in the run log; "Roster changes" box on the report |
| Tests | `sql/tests/*.sql` | each must return zero rows, or the run stops |
| Report | `report/opponent_report.qmd` | `site/reports/<season>-week<NN>-<OPP>.html` / `.pdf` |
| Site | `R/pipeline.R` `build_site()` | `site/index.html`: latest report + archive |
| Automation | `.github/workflows/weekly-report.yml` | Tuesday run, Wednesday retry, publish to Pages |

If any step fails in GitHub Actions, nothing is published, so the last good report stays live and GitHub emails the failure.

If the Bears have no game left, the pipeline scouts both teams in every game of the next scheduled week (the playoffs).

## Definitions (locked Oct 25, 2026)

| Item | Definition |
|------|-----------|
| Scrimmage plays | Pass or run plays only. Exclude kneels, spikes, and no-play penalties. |
| Win-probability filter | Neutral splits (early downs, 3rd down, red zone) use plays with 5% ≤ `wp` ≤ 95% (`wp` = possession team's pre-snap win probability). |
| Situational splits | 2-minute and trailing by 8+ never use the WP filter. |
| Early downs | 1st and 2nd down |
| 3rd down | Short 1–3, medium 4–6, long 7+ yards to go |
| Red zone | Ball at the opponent's 20 or closer (`yardline_100 <= 20`) |
| 2-minute | Last 2:00 of either half (`half_seconds_remaining <= 120`) |
| Trailing by 8+ | `score_differential <= -8` |
| Window | Splits and ranks use the current season up to the report's week. Earlier seasons supply league baselines only. |
| Last-season ranks | Full-season 2025 league rank shown next to each 2026 rank where applicable, with a caveat when the opponent changed play callers. |
| Leakage | A report for week N uses only games before week N. |
| "3 things to know" | A metric in the league's top or bottom 10% with at least 30 plays. |
| In-season move | A player who changed teams from the season's first game on (offseason trades excluded). Sources: nflverse trade feed, `config/trades_manual.csv`, and weekly rosters (53-man or reserve list one week, another team's the next). |
| Regular (⚠) | Before the move, with the old team: 50%+ of dropbacks, 15%+ of targets, 30%+ of carries, or 60%+ of offensive or defensive snaps. |

## Trades during the season

nflverse's trade feed can lag by months (on Oct 30, 2026 its newest trade was from April), so the check has two other sources:

1. **`config/trades_manual.csv`**: add a row per player when a trade happens (date, from, to, name, position; PFR id optional). Picks go in `notes`. Once nflverse publishes the trade, the manual row is ignored automatically.
2. **Weekly rosters**: a player who shows up on a new team's roster is caught even if nobody typed the trade in. The run log then says "Seen in weekly rosters but not in any trade list", which is your cue to add it to the CSV (or ignore it if it was a waiver claim).

Every run prints each move involving the Bears or the opponent, and a GitHub Actions warning when one of the opponent's regulars moved. The report shows the same moves in a "Roster changes" box above "3 things to know" and says how many of the opponent's games came before the move.

## Data credit

Play-by-play, schedule, trade, roster and snap-count data from [nflverse](https://github.com/nflverse) (nflreadr / nflfastR), used under its open license.
