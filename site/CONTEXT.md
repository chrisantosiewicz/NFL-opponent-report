# site - what GitHub Pages serves

One job: hold the published reports, the live scout page and the archive.

| Path | Kind | Written by |
|---|---|---|
| `scout.html`, `archive.html`, `index_template.html` | hand-edited pages | people |
| `index.html` | generated: latest report + archive | `build_site()` |
| `reports/` | generated one-pagers | `render_report()` |
| `data/` | generated JSON | `../sql/export/` |
| `notes/drafts/` | generated draft notes | `write_draft_notes()` |
| `notes/` | staff notes, final | Chris: [contract](notes/CONTEXT.md) |

Do not hand-edit generated files; change what writes them.

The weekly Action commits `reports/`, `data/`, `notes/drafts/` and `index.html` to `main`, then deploys this folder. Runs from other branches or for another team upload reports as a workflow artifact and publish nothing.
