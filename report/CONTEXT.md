# report - the one-page opponent report

One job: render one matchup to HTML and PDF.

## Inputs
- Working (this run): the local DuckDB file data/nfl.duckdb (built by step 1, never committed), params `opponent` and `week` from `render_report()`
- Reference (every run): `helpers.R` (wording, `MIN_N = 30`, shift thresholds), `report.css`
- Reference (every run): `../_shared/definitions.md`

## Process
1. `opponent_report.qmd` reads models only; no new logic here (logic goes in `sql/models/`).
2. Rendered from inside `report/`; HTML is printed to PDF by headless Chrome (`print_pdf()`).
3. Findings are titles; any number under `MIN_N` plays is shown with a red asterisk.

## Outputs
- `site/reports/<season>-week<NN>-<OPP>.html` and `.pdf`

## Check
A person opens the PDF: it fits on one page and every number has its n.
