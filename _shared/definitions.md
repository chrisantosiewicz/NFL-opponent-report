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
| Complete game | Final score in the schedule and play-by-play loaded. A game with a score but no play-by-play yet is "awaiting": left out of every number, and the live page says so on both teams. The run stops only if a game has waited more than a day (`test_completed_games_have_plays`). |
| "3 things to know" | A metric in the league's top or bottom 10% with at least 30 plays. |
| In-season move | A player who changed teams from the season's first game on (offseason trades excluded). Sources: nflverse trade feed, `config/trades_manual.csv`, and weekly rosters (53-man or reserve list one week, another team's the next). |
| Regular (⚠) | Before the move, with the old team: 50%+ of dropbacks, 15%+ of targets, 30%+ of carries, or 60%+ of offensive or defensive snaps. |

## Betting lines and predictions (added Nov 11, 2026)

Implemented in `sql/models/07_stg_market_lines.sql`, `32_elo_ratings.sql`, `33_game_predictions.sql`, `34_betting_trends.sql` and `38_w2_predictions.sql`.

| Item | Definition |
|------|-----------|
| Lines | nflverse schedules (`spread_line`, `total_line`, moneylines). No sportsbook API, no scraping. Finished games carry the feed's last (closing) numbers. |
| Spread sign | nflverse `spread_line` is positive when the home team is favored. It is turned once into `home_line` (betting notation, favorite negative); nothing else reads `spread_line`. |
| Market win % | Each moneyline's implied chance, divided by their sum (bookmaker's margin removed). |
| Model | Elo v1 (cloud): Chris's Elo rebuilt in SQL. 1500 start in 2017, one-third regression each season, K 20, home field +32 (0 neutral), +25 off a bye (13+ days rest). His rest adjustment is not in yet; unlike his repo, ratings include 2025. |
| Win % | Predicted home margin = 0.0422 x adjusted Elo gap; final margin normal around it (sd 13.22) rounded to whole points; a tie counts half. |
| Shown | Win % only, labeled "model estimate", next to the market's. No cover %, over % or edge: his 2019-2024 backtest found no signal there (49.1% ATS, 49.9% totals). |
| Lock | A game's win % is locked in `site/data/predictions-<season>.json` the first time a run sees it in the report week before game day, and never rewritten. Grades (right/wrong, log loss vs the market) use the final score; ties are not graded. |
| W2 (added Nov 19, 2026) | Chris's newest model from his betting repo: M6 ridge plus game-day rain and wind, trained 2017-2024 (2025 held out), live weather inputs are forecasts. Not rebuilt here: the laptop runs it and commits `config/w2_predictions.csv` (newest run per game) via `_tools/w2_to_csv.py`; `sql/models/38_w2_predictions.sql` reads it. |
| W2 shown | Win % (labeled "model estimate", above Elo's), plus its predicted margin as a line (rounded to the half point) and its predicted total. Its cover and over chances are not copied or shown, and no edge is claimed. |
| W2 lock | W2's last run before kickoff is the one kept and graded (changed Nov 19, 2026; Elo still keeps its first). Until a game kicks off, each run copies W2's newest number into the game's `w2_*` fields in `predictions-<season>.json`; after kickoff they are never rewritten. `w2_locked_at` is when the kept number first appeared. |
| W2 refresh | The laptop runs `_tools/w2_refresh.ps1` (Task Scheduler: Tue 8:00, Thu 9:30, Sat 9:30, Sun 7:00, Mon 9:30 AM CT): 2026-only data refresh (schedule, live play-by-play; never 2025, no Odds API), `betting predict build-features`, then W2 for the current week (predict only, no refit), copied into `config/w2_predictions.csv` and pushed to `main`. That push starts an update run. Weeks turn over on Tuesdays. |
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
| Forecast lock | Each game's kickoff-window hours from the last fetch before kickoff are kept in `site/data/weather-locked.csv` (`lock_weather()` in `R/pipeline.R`). Once a game kicks off, or when a fetch fails, the page shows the kept forecast instead of going blank. |
| Game freeze | Once a game kicks off, its two teams' rows on the week page (scouting numbers, notes, lines, injuries, trends) stay as the last run before kickoff wrote them (`freeze_started_games()` in `R/pipeline.R`), and its one-pagers are not re-rendered (`render_report()`; a manual `--opponent` run still re-renders). Predictions lock separately; weather through the forecast lock. |
| Report-card lock | Each call the archive grades (what "We said" and every pregame number its grade uses: ranks, league averages, the picked area or lane, the named player, our offense's usual) is kept in `site/data/report-card-locks-<season>.json` (`export_report_card_locks()` in `R/pipeline.R`, added Nov 25, 2026). Every run, update runs included, rewrites the rows of games that haven't kicked off; once a game kicks off its rows are never rewritten, so the archive grades the last run before kickoff, not data nflverse revised later. Games graded before the lock existed (2026 weeks 1-11) are recomputed each run. |
| Indoor | Schedule roof `dome` or `closed`, or a fixed-roof stadium when the schedule leaves it blank: weather neutral, no flags. A retractable roof the schedule hasn't set is treated as outdoor, with a note. |
| Weather flags | Windy = 15+ mph sustained; cold = 32F or colder; wet = 50%+ precipitation chance. |
| Weather context | Completed outdoor games since 2017 with the schedule's recorded kickoff temperature and wind: share that went under the closing total, for windy, cold, rain and snow games. Rain/snow = the gamebook's kickoff sky description names it (not "chance of rain"); 2017-2023 from `reference/gamebook_weather_2017_2023.csv`, later seasons from play-by-play. The page shows rain or snow history when the forecast is wet (snow at 34F or below). Context next to the total, not a model input. |

## Attack plan and player trends (added Nov 15, 2026)

Implemented in `sql/models/22_player_trends.sql`, `09_stg_charting.sql` and `37_coverage_matchup.sql`; the attack plan on `site/scout.html` also reads `24_defense_vs_position`, `25_team_yards` and `26_play_direction`.

| Item | Definition |
|------|-----------|
| Attack plan | One offense next to the defense it plays this week: run side and lane, pass area, and position targeted, season to date, neutral downs (5-95% win probability) for direction. Sides are from the offense's view on both. |
| Soft spot / tough | The defense ranks in the worst quarter of the league there (1-8 of 32 in EPA allowed) / the best quarter (25-32). |
| Player picks | Per team: the QB with the most passing yards, the 2 backs with the most carries, the 4 WR/TE with the most targets, season to date. |
| Player stats | From play-by-play: receiving = targets, catches, yards on catches; rushing = every carry with a rusher listed, scrambles included; passing = completions and yards on them. Per-game = over the games the player had a stat. Can differ slightly from official box scores. |
| Prop trends | Averages and last 4 game logs next to what the opponent allows. No prop lines; not a pick. |
| Blitz | FTN charting: 1+ blitzer on a dropback. Blitz rate = blitzes / charted dropbacks; ranks need 30+ charted dropbacks. |
| Heavy box | FTN charting: 8+ defenders in the box at the snap on a designed run. |
| Man / zone | nflverse participation (FTN), last season only: it is published after the postseason, so the current season has none. Shown labeled with its season. |

## Grading the attack calls (added Nov 24, 2026)

Implemented in `sql/models/23_defense_splits.sql` (adjusted columns) and `sql/models/31_report_card.sql`; the notes' early-down soft spot (`30_draft_notes.sql`) uses the same pick.

| Item | Definition |
|------|-----------|
| Opponent-adjusted defense | Season to date, per situation and play type: EPA per play allowed above what the offenses faced usually gain, after crediting those offenses for the defenses they faced (three rounds of offense/defense adjustment). `epa_vs_expected`, `rank_allowed_adj` (1 = softest). |
| Early-down soft / stout | Called only with strong evidence: top 5 / bottom 5 of 32 in `rank_allowed_adj`. Backtest, weeks 3-11 of 2026: top/bottom 10 on raw EPA hit 53%, top/bottom 5 adjusted 60%. Not called in weeks 2-4 (1-3 games of data): weeks 3-4 were a coin flip in 2025 (48%) and 2026 (52%); from week 5 on, 58% in 2025 and 66% in 2026 at the 1.5 line. |
| Net points | For a call graded on EPA (early-down soft/stout, the position they cover worst, red-zone throws): our EPA in that part of the game minus what our offense usually gets on the same number of plays. "Usually" = our season to date before the game in that situation, blended with 30 plays of league average. |
| No real impact | Net points within 1.5 either way. Shown, but counted neither right nor wrong. One big play can still decide a call. Chosen over 2 because calls landing between 1.5 and 2 were right as often as the rest (2025: 13 of 23, 57%), so a wider line only discards graded calls. Reassess after the 2026 season. |
| Fumbles after the catch (added Nov 27, 2026) | Every graded call uses `epa_before_fumble` (nflverse `qb_epa`): a completed pass that ends in a lost fumble counts at its value up to the moment the ball came out. An open receiver is still a coverage loss for the defense; the fumble is a separate event the call never claimed to predict. Interceptions, sacks and fumbles on runs or by the passer count in full. Differs from EPA on 177 plays in 2024-2026 (60 in 2026 through week 12). Regraded 78 of 10,115 calls; decisive hit rate rose 0.4-0.5 points a season (2026: 63.1% to 63.5%). Grading only: the pregame calls and the locked "usual" baseline keep plain EPA. |
| Third-down distance (dropped) | No longer a graded call. How often a team faces 3rd & 7+ follows from its early downs that game, not a habit: team share correlated about 0 between halves of 2025 and 2026, and the call was right 54% in 2026 (calls 10+ points off the league: 36-36). Tested as replacements and not adopted: 3rd & 7+ conversion rate (split-half correlation about 0, calls about 50% once a game was a conversion off the league), and the 3rd & 7+ top target (when he differed from the overall top target, the overall top target got the most 3rd & 7+ looks more often, 38-40% vs 24-25%). |
| 3rd & 7+ in the staff notes | Context only, shown when far from average: their share of third downs at 7+ to go when 8+ points off the league (about the top and bottom 7 teams), their 3rd & 7+ EPA per play and the defense's 3rd & 7+ EPA per dropback allowed when top or bottom 5. Split-half correlation was 0.05-0.19 for these, against 0.34-0.38 for the 3rd & 1-3 pass rate and 0.37-0.50 for early-down EPA. |

## Trades during the season

nflverse's trade feed can lag by months (on Oct 30, 2026 its newest trade was from April), so the check has two other sources:

1. **`config/trades_manual.csv`**: add a row per player when a trade happens (date, from, to, name, position; PFR id optional). Picks go in `notes`. Once nflverse publishes the trade, the manual row is ignored automatically.
2. **Weekly rosters**: a player who shows up on a new team's roster is caught even if nobody typed the trade in. Every run (Tuesday report and the Thu/Sat/Sun/Mon updates) lists these for all 32 teams, first seen in the last 14 days, in the "Trades to confirm" GitHub issue and on the run's summary page. That is your cue to add it to the CSV (or ignore it if it was a waiver claim). Rosters catch a move only once the new team's weekly roster has him, and skip a player marked cut by the old team, so a deadline trade is best typed in from the NFL.com tracker the day it happens.

**No trades after the deadline** (`config/trade_deadlines.csv`). A team switch in the weekly rosters after the deadline is a waiver claim, cut or free-agent signing: it is labeled "waivers/FA", never a trade, and never goes on the "Trades to confirm" list. A row in `trades_manual.csv` dated after the deadline stops the run (`test_no_trades_after_deadline`).

Every run prints each move involving the Bears or the opponent, and a GitHub Actions warning when one of the opponent's regulars moved. The report shows the same moves in a "Roster changes" box above "3 things to know" and says how many of the opponent's games came before the move.
