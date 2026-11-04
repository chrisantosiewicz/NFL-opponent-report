# NFL opponent report - entry file

Every Tuesday in season this repo pulls nflverse play-by-play, builds SQL models in DuckDB, tests them, and publishes a one-page tendency report on the Chicago Bears' next opponent, plus a live scout page for all 32 teams.

Start here, then read at most one `CONTEXT.md`. The pipeline in one screen: [CONTEXT.md](CONTEXT.md).

## Where things live

| Folder | What it holds |
|---|---|
| `_shared/` | factory: the locked [definitions](_shared/definitions.md) every model and report follows |
| `config/` | hand-kept CSVs (trades, coaching changes): [contract](config/CONTEXT.md) |
| `R/`, `run_pipeline.R` | load data, run SQL, render, build the site (R moves data, SQL holds logic) |
| `sql/models/` | numbered models, built in file-name order: [contract](sql/models/CONTEXT.md) |
| `sql/tests/` | queries that must return zero rows: [contract](sql/tests/CONTEXT.md) |
| `sql/export/` | JSON for the live page: [contract](sql/export/CONTEXT.md) |
| `report/` | the Quarto one-pager: [contract](report/CONTEXT.md) |
| `site/` | what GitHub Pages serves: [contract](site/CONTEXT.md); staff notes: [contract](site/notes/CONTEXT.md) |
| `learning/` | Chris's skill tracker, progress log and walkthrough: [contract](learning/CONTEXT.md) |
| `_tools/` | `links.py` checks every link and input path in the docs |
| `.github/workflows/` | Tuesday run, Wednesday retry, publish to Pages |

## Route by task

| If you are | Go to |
|---|---|
| changing a definition or threshold | [_shared/definitions.md](_shared/definitions.md), then [sql/models](sql/models/CONTEXT.md) |
| adding or changing a model | [sql/models/CONTEXT.md](sql/models/CONTEXT.md) |
| adding a data test | [sql/tests/CONTEXT.md](sql/tests/CONTEXT.md) |
| logging a trade or coaching change | [config/CONTEXT.md](config/CONTEXT.md) |
| changing the one-pager | [report/CONTEXT.md](report/CONTEXT.md) |
| changing the live or archive page | [site/CONTEXT.md](site/CONTEXT.md) |
| publishing this week's staff notes | [site/notes/CONTEXT.md](site/notes/CONTEXT.md) |
| logging work or updating a skill rating | [learning/CONTEXT.md](learning/CONTEXT.md) |
| asked for status | newest `site/reports/*.html`, `site/notes/` vs `site/notes/drafts/`, the last Actions run |

## The one rule

A failed data test stops the run, and nothing is published: the last good report stays live.

After editing any `.md` here, run `python3 -I _tools/links.py`.
