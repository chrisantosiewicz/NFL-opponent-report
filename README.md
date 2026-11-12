# nfl-opponent-report

Every Tuesday during the NFL season, an automated pipeline pulls the latest NFL play-by-play, runs a set of SQL models in DuckDB, and publishes a one-page tendency report on the Chicago Bears' next opponent.

**Status:** pipeline built Oct 26, 2026 (models, tests, report, workflow). First automated report Tue Dec 15, 2026.

**Stack:** R (nflreadr) → DuckDB → `.sql` models run through DBI → data tests (queries that must return zero rows) → parameterized Quarto one-pager (HTML, plus PDF printed by headless Chrome) → GitHub Actions Tuesday cron → GitHub Pages with an archive.

## Run it

```sh
Rscript run_pipeline.R              # load data, build models, run tests, render CHI's next opponent
Rscript run_pipeline.R --skip-load  # reuse data/nfl.duckdb (fast while editing SQL)
Rscript run_pipeline.R --update     # refresh the published week: injuries, lines, weather
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
| Live data | `sql/export/site_week.sql`, `site_index.sql` via `export_site_data()` | `site/data/<season>-week<NN>.json` (all 32 teams) + `index.json` |
| Report | `report/opponent_report.qmd` | `site/reports/<season>-week<NN>-<OPP>.html` / `.pdf` |
| Site | `R/pipeline.R` `build_site()` | `site/index.html`: latest report + archive |
| Top target | `sql/models/18_game_windows.sql`, `19_receiver_targets.sql`, `20_top_target.sql` | who gets the ball, season vs last 4, the situations where he gets it most |
| Formation tells | `sql/models/21_formation_tells.sql` | early-down run/pass rate under center and in shotgun, vs the league |
| Defense splits | `sql/models/23_defense_splits.sql` | EPA, success rate and yards each defense allows on runs vs dropbacks by situation (early down, 3rd & short/medium/long, red zone), season and last 4, with league rank |
| Defense vs position | `sql/models/24_defense_vs_position.sql` | EPA per target and yards per game each defense allows to WRs, TEs and RBs, with league rank |
| Team yards | `sql/models/25_team_yards.sql` | rushing and passing yards per game (and per carry / dropback) for every offense and allowed by every defense, with league ranks |
| Play direction | `sql/models/26_play_direction.sql` | where each offense runs (inside / off tackle / around end, left / middle / right) and throws (short / deep x left / middle / right), and where each defense gets run and thrown on, by down and distance, with league share, yards, success rate, explosive rate, EPA and rank, plus EPA with the single best play removed |
| Score splits | `sql/models/28_score_splits.sql` | late-half, 3rd-down, red-zone and overall results by score state (trailing 9+, 1-8, tied, leading 1-8, 9+, plus tied-or-trailing and leading), with median EPA and EPA without the best play |
| Scout picks | `sql/models/29_scout_picks.sql` | the spots the notes call out (hot throw area, with "outside the hashes" when both sides qualify; run lean; softest and toughest run lanes), chosen once so the notes and report card grade the same thing |
| Draft notes | `sql/models/30_draft_notes.sql` via `write_draft_notes()` | a narrative for every matchup in two halves (stopping their offense, attacking their defense) plus "what to look for" on each side, from tendencies, top target, defensive splits, position matchups, run lanes and pass areas and roster moves; `site/notes/drafts/<slug>.md` |
| Report card | `sql/models/31_report_card.sql` | after each game, every call the notes made, in one line, next to what happened and a verdict (Hit / Miss / Mixed for tendencies; Called it / Held for threats on defense, Hit / Miss for soft spots on offense; Didn't come up) |
| Betting lines | `sql/models/07_stg_market_lines.sql` | spread, total and moneylines per game from nflverse schedules, with the market's win % |
| Elo and predictions | `sql/models/32_elo_ratings.sql`, `33_game_predictions.sql`, `export_predictions()` | Elo v1 ratings since 2017, each game's model win %, locked in `site/data/predictions-<season>.json` and graded after the game |
| Betting trends | `sql/models/34_betting_trends.sql` | ATS, straight-up and over/under records per team, season and last 4, home / away / favorite / underdog, with league ranks |
| Live page | `site/scout.html` | interactive scout: any team, Scouting and Predictions tabs, season or last 4, 32-team strips; staff notes from `site/notes/` |
| Automation | `.github/workflows/weekly-report.yml` | Tuesday run, Wednesday retry, Thursday/Saturday/Sunday/Monday morning updates (injuries, lines, weather), publish to Pages |

If any step fails in GitHub Actions, nothing is published, so the last good report stays live and GitHub emails the failure.

If the Bears have no game left, the pipeline scouts both teams in every game of the next scheduled week (the playoffs).

## Definitions and trades

The locked definitions (scrimmage plays, WP filter, situations, leakage, "3 things", in-season moves) and how to log a trade live in one place: [_shared/definitions.md](_shared/definitions.md).

Working on this repo with an agent? Start at [AGENTS.md](AGENTS.md).

## Data credit

Play-by-play, schedule, trade, roster and snap-count data from [nflverse](https://github.com/nflverse) (nflreadr / nflfastR), used under its open license.
