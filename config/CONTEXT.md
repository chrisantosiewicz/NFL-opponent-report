# config - facts typed in by hand

One job: hold what nflverse doesn't publish (yet). Each CSV explains its columns in its header comments.

| File | When to edit | Read by |
|---|---|---|
| `trades_manual.csv` | a trade happens in season (one row per player) | `load_manual_trades()` -> `sql/models/06_stg_trades.sql` |
| `coaching_changes_manual.csv` | offseason HC/OC/DC changes, before Week 1 | `sql/models/27_week1_carryover.sql` |

How and why trades are tracked: [definitions](../_shared/definitions.md), "Trades during the season".

## Check
`sql/tests/test_manual_trades_parse.sql` and `test_trades_teams_valid.sql` pass on the next run. A "Seen in weekly rosters but not in any trade list" warning means a row is missing here.
