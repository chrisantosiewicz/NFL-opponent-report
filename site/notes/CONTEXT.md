# site/notes - staff notes, the person check

One job: hold the final, human-edited notes the live page shows for each matchup.


Write the "so what" for a report here and it shows at the top of the live page
for that team and week. One file per report, named like the report:
`2026-week08-SEA.md`.

Plain lines become paragraphs and lines starting with `- ` become bullets.
Lines starting with `#` are skipped. Commit the file to `main`; it shows on the
site after the next run of the weekly workflow (or a manual run).

## Inputs
- Working (this run): `drafts/<season>-week<NN>-<TEAM>.md`, written by `write_draft_notes()`
- Reference (every run): the report in `../reports/` for the same slug

## Check
Chris reads the draft against the report, edits it, and saves it here under the same name. Until a file exists here, the live page shows the draft.
