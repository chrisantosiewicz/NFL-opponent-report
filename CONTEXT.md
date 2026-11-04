# The weekly pipeline

Load, model, test, render, write notes, publish. One command runs the code steps: `Rscript run_pipeline.R` (flags in [README.md](README.md)).

| Step | Where | Output | Check |
|---|---|---|---|
| 1 Load | `R/pipeline.R` `load_raw_data()`, `config/*.csv` | `raw_*` tables in `data/nfl.duckdb` | freshness test in step 3 |
| 2 Model | `sql/models/` (file-name order) | DuckDB tables | step 3 |
| 3 Test | `sql/tests/` | nothing, or the run stops | every query returns zero rows |
| 4 Export | `sql/export/` | `site/data/*.json` | the live page loads the week |
| 5 Render | `report/opponent_report.qmd` | `site/reports/<season>-week<NN>-<OPP>.html` / `.pdf` | one page; small samples marked |
| 6 Draft notes | `sql/models/30_draft_notes.sql`, `write_draft_notes()` | `site/notes/drafts/<slug>.md` | **a person**: Chris edits and saves to `site/notes/<slug>.md` |
| 7 Publish | `.github/workflows/weekly-report.yml`, `build_site()` | `site/index.html`, GitHub Pages | Action is green on `main` |
| 8 Grade | `sql/models/31_report_card.sql`, `sql/export/site_report_cards.sql` | `site/data/report-cards-<season>.json` | `test_report_card_valid` |

Factory (stable, every run): [_shared/definitions.md](_shared/definitions.md), `config/`, `report/helpers.R` (`MIN_N`), `report/report.css`.
Product (new each run): `site/reports/`, `site/data/`, `site/notes/drafts/`, `site/index.html`.

Status is what exists: a week is published when its report is in `site/reports/` on `main`; its notes are final when `site/notes/<slug>.md` exists (otherwise the live page shows the draft).
