# sql/models - turn raw play-by-play into tendencies

One job: every table the report, live page and notes read, as plain SQL.

## Inputs
- Working (this run): `raw_pbp`, `raw_schedules`, `raw_teams` and side feeds in the local DuckDB file data/nfl.duckdb (never committed), loaded by `R/pipeline.R`
- Reference (every run): `../../_shared/definitions.md`
- Reference (every run): `../../config/trades_manual.csv`, `../../config/coaching_changes_manual.csv`

Do NOT load: `site/reports/`, `site/data/`, `learning/`.

## Process
1. Files run in file-name order (`build_models()`); a model may only read lower-numbered models.
2. Numbering bands: `01-09` staging and feeds, `10-17` tendencies, ranks and trades, `18-31` targets, formations, defense, direction, notes and grading.
3. Store counts and sums; compute rates last. Every number keeps its `n`.
4. A report for week N uses only games before week N.
5. A definition lives in one model; others read it from there.

## Outputs
- One table or view per file, named for the file without its number.

## Check
`sql/tests/` runs right after: every test returns zero rows or the run stops. A new model ships with at least one test.
