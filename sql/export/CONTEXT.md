# sql/export - JSON for the live and archive pages

One job: write what `site/scout.html` and `site/archive.html` fetch.

## Inputs
- Working (this run): tables from `../models/`
- Reference (every run): `R/pipeline.R` `run_sql_template()` fills the `{{placeholders}}`

## Process
1. `site_week.sql`: all 32 teams for one week -> `site/data/<season>-week<NN>.json`, including injury reports, the game-day forecast and the attack plan's data (play direction, defense vs position, team yards, player trends, coverage). Written for the focal team's report week and, when that team is on bye, for the league's current week too, so the page always has this weekend's games. Update runs rewrite these files only.
2. `site_index.sql`: the weeks on disk, newest first, with each week's last game day -> `site/data/index.json`. The page opens on the earliest week not yet over.
3. `site_report_cards.sql`: every graded matchup -> `site/data/report-cards-<season>.json`.
4. `site_predictions.sql`: locked win-% calls with results and grades -> `site/data/predictions-<season>.json`. `export_predictions()` reads the existing file first, so a locked call is never rewritten, and a game that has kicked off is never locked.
5. Report-card locks: `export_report_card_locks()` in `R/pipeline.R` writes `report_card_pregame_fresh` (`../models/31_report_card.sql`) for every game not yet kicked off to `site/data/report-card-locks-<season>.json`, keeping kicked-off games' rows as they are. Every run writes it, update runs included.

## Outputs
- `site/data/*.json`

## Check
Open `site/scout.html` locally and switch to the new week: every team loads with no console errors.
