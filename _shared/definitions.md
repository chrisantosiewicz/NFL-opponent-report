# Definitions - the rules every model and report follows

The factory for this repo: stable across runs. Change a rule here and in the one SQL file that implements it, in the same commit (`sql/models/01_stg_plays.sql` and `sql/models/10_team_game_tendencies.sql` hold the play filter and buckets).

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

## Betting lines and predictions (added Nov 11, 2026)

Implemented in `sql/models/07_stg_market_lines.sql`, `32_elo_ratings.sql`, `33_game_predictions.sql` and `34_betting_trends.sql`.

| Item | Definition |
|------|-----------|
| Lines | nflverse schedules (`spread_line`, `total_line`, moneylines). No sportsbook API, no scraping. Finished games carry the feed's last (closing) numbers. |
| Spread sign | nflverse `spread_line` is positive when the home team is favored. It is turned once into `home_line` (betting notation, favorite negative); nothing else reads `spread_line`. |
| Market win % | Each moneyline's implied chance, divided by their sum (bookmaker's margin removed). |
| Model | Elo v1 (cloud): Chris's Elo rebuilt in SQL. 1500 start in 2017, one-third regression each season, K 20, home field +32 (0 neutral), +25 off a bye (13+ days rest). His rest adjustment is not in yet; unlike his repo, ratings include 2025. |
| Win % | Predicted home margin = 0.0422 x adjusted Elo gap; final margin normal around it (sd 13.22) rounded to whole points; a tie counts half. |
| Shown | Win % only, labeled "model estimate", next to the market's. No cover %, over % or edge: his 2019-2024 backtest found no signal there (49.1% ATS, 49.9% totals). |
| Lock | A game's win % is locked in `site/data/predictions-<season>.json` the first time a run sees it in the report week before game day, and never rewritten. Grades (right/wrong, log loss vs the market) use the final score; ties are not graded. |
| Trends | ATS, straight-up and over/under records against each game's closing line, over the same windows as the tendencies (games before the week; season and last 4). A push is its own column. Fewer than 4 games is marked small. |

## Injuries and game-day weather (added Nov 11, 2026)

Implemented in `sql/models/08_stg_injuries.sql`, `35_injury_report.sql` and `36_game_weather.sql`.

| Item | Definition |
|------|-----------|
| Injury report | nflverse `load_injuries()`: the latest version of each week's official report. A game's report is the week's own once the team files one; before that (e.g. the Tuesday run) the team's latest earlier report, labeled as such. |
| Listed | A game status (Out, Doubtful, Questionable) or a practice day that was not full (DNP, Limited). Full practice with no status = healthy, not listed. |
| Starter | Averaged 50%+ of offensive or defensive snaps in the games he played among the team's last 4 completed games before this one. |
| Injury flag | Count of listed starters: Out or Doubtful = "out", Questionable = "questionable". Shown on each team in the matchup bar. |
| New | On this report but not on the team's previous week's report. |
| Forecast | Open-Meteo hourly forecast at the stadium (`config/stadiums.csv`), averaged temperature and highest wind, gust and precipitation chance over the kickoff hour and the two after. Fetched for games in the next 7 days on every run. |
| Indoor | Schedule roof `dome` or `closed`, or a fixed-roof stadium when the schedule leaves it blank: weather neutral, no flags. A retractable roof the schedule hasn't set is treated as outdoor, with a note. |
| Weather flags | Windy = 15+ mph sustained; cold = 32F or colder; wet = 50%+ precipitation chance. |
| Weather context | Completed outdoor games since 2017 with the schedule's recorded kickoff temperature and wind: share that went under the closing total. Context next to the total, not a model input. |

## Trades during the season

nflverse's trade feed can lag by months (on Oct 30, 2026 its newest trade was from April), so the check has two other sources:

1. **`config/trades_manual.csv`**: add a row per player when a trade happens (date, from, to, name, position; PFR id optional). Picks go in `notes`. Once nflverse publishes the trade, the manual row is ignored automatically.
2. **Weekly rosters**: a player who shows up on a new team's roster is caught even if nobody typed the trade in. The run log then says "Seen in weekly rosters but not in any trade list", which is your cue to add it to the CSV (or ignore it if it was a waiver claim).

Every run prints each move involving the Bears or the opponent, and a GitHub Actions warning when one of the opponent's regulars moved. The report shows the same moves in a "Roster changes" box above "3 things to know" and says how many of the opponent's games came before the move.
