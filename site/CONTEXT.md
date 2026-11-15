# site - what GitHub Pages serves

One job: hold the published reports, the live scout page and the archive.

| Path | Kind | Written by |
|---|---|---|
| `scout.html`, `archive.html`, `index_template.html` | hand-edited pages | people |
| `index.html` | generated from `index_template.html`: "Who's your favorite team?" logo grid, Bears one-pager + archive | `build_site()` |
| `reports/` | generated Bears one-pagers (the archive) | `render_report()` |
| `reports/teams/` | generated one-pagers for every other team, this week only | `render_league_reports()` |
| `data/` | generated JSON, including the locked `predictions-<season>.json` | `../sql/export/` |
| `notes/drafts/` | generated draft notes | `write_draft_notes()` |
| `notes/` | staff notes, final | Chris: [contract](notes/CONTEXT.md) |

Do not hand-edit generated files; change what writes them.

A home-page logo opens `scout.html?for=<TEAM>#<OPP>`: that team's opponent, scouted for them. `?for=` makes the scout page the fan's (brand, "Your team", "Back to ... opponent"); without it the page is the Bears', as before. The "Want a one-pager?" box shows only when the team's report exists (checked with HEAD).

The weekly Action commits `reports/`, `data/`, `notes/drafts/` and `index.html` to `main`, then deploys this folder. Runs from other branches or for another team upload reports as a workflow artifact and publish nothing.
