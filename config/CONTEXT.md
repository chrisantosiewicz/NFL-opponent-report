# config - facts typed in by hand

One job: hold what nflverse doesn't publish (yet). Each CSV explains its columns in its header comments.

| File | When to edit | Read by |
|---|---|---|
| `trades_manual.csv` | a trade happens in season (one row per player) | `load_manual_trades()` -> `sql/models/06_stg_trades.sql` |
| `trade_deadlines.csv` | before Week 1 each season (one row: season, deadline) | `load_manual_trades()` -> `sql/models/06_stg_trades.sql` |
| `stadiums.csv` | the schedule names a stadium not in it (a "No stadium location" warning) | `load_stadiums()`, `fetch_weather()` -> `sql/models/36_game_weather.sql` |
| `w2_predictions.csv` | written and pushed by the laptop's scheduled `_tools/w2_refresh.ps1` (by hand: `python3 -I _tools/w2_to_csv.py <w2 json>`, then commit); never typed by hand; a push starts an update run | `load_w2_predictions()` -> `sql/models/38_w2_predictions.sql` |
| `coaching_changes_manual.csv` | offseason HC/OC/DC changes, before Week 1 | `sql/models/27_week1_carryover.sql` |

How and why trades are tracked: [definitions](../_shared/definitions.md), "Trades during the season".

## Check
`sql/tests/test_manual_trades_parse.sql`, `test_trades_teams_valid.sql`, `test_no_trades_after_deadline.sql` and `test_trade_deadline_known.sql` pass on the next run. Every run also checks all 32 teams' weekly rosters for team switches that no trade list has, and keeps the open "Trades to confirm" GitHub issue up to date with them (`check_league_moves()`). Each one there is either a trade to add here or a waiver claim to leave alone; it drops off once its row is here.
