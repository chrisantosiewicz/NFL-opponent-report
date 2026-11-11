# sql/export - JSON for the live and archive pages

One job: write what `site/scout.html` and `site/archive.html` fetch.

## Inputs
- Working (this run): tables from `../models/`
- Reference (every run): `R/pipeline.R` `run_sql_template()` fills the `{{placeholders}}`

## Process
1. `site_week.sql`: all 32 teams for one week -> `site/data/<season>-week<NN>.json`, including injury reports and the game-day forecast. Update runs rewrite this file only.
2. `site_index.sql`: the weeks on disk, newest first -> `site/data/index.json`.
3. `site_report_cards.sql`: every graded matchup -> `site/data/report-cards-<season>.json`.
4. `site_predictions.sql`: locked win-% calls with results and grades -> `site/data/predictions-<season>.json`. `export_predictions()` reads the existing file first, so a locked call is never rewritten.

## Outputs
- `site/data/*.json`

## Check
Open `site/scout.html` locally and switch to the new week: every team loads with no console errors.
