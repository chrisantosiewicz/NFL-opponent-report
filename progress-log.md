# Progress log

## 2026-10-25: Kickoff
- Plan and timeline confirmed: Week 1 Nov 16–22 (staging + tests), Week 2 Nov 23–29 light (tendencies, rolling, snapshot), Week 3 Nov 30–Dec 6 (Quarto one-pager), Week 4 Dec 7–13 (automation, archive, README). First report Tue Dec 15.
- Definitions locked in README. Win-probability filter: option A (filter neutral splits only; 2-minute and trailing 8+ unfiltered), window widened from 10–90% to 5–95% by Chris.
- Optional check for Chris: compare 2025 early-down pass-rate ranks filtered vs unfiltered to confirm the filter's effect.
- Added: 2025 full-season ranks next to 2026 ranks.
- Repo created (empty). Skill Tracker drafted; baselines pending Chris's evidence.
- Waiting on: thesis nflfastR loading/cleaning code (Chris, later).

## 2026-10-26: v1 pipeline built (Claude, at Chris's request)
- Chris asked Claude to build everything now and walk him through it after.
- Built: SQL models (staging, tendencies, rolling, snapshot, ranks, last-season ranks, "3 things"), 10 data tests, R pipeline (`run_pipeline.R`), Quarto one-pager, landing page + archive, GitHub Actions weekly workflow and renv lockfile workflow.
- Verified on real nflverse data (2024–2026 through Week 7): all models build, all 10 tests pass; the leakage test fails when the `<` guard is changed to `<=`.
- League 3rd-down shotgun rate: ~98% on 3rd & 7+, ~97% on 3rd & 4–6, 62–70% on 3rd & 1–3 (to compare with the thesis).
- Next for Chris: setup steps at the end of `docs/walkthrough.md` (Pages, renv lock, first manual run), then the ✍️ exercises.

## 2026-10-28: Live page (Claude, at Chris's request)
- Added `export_site_data()`: one DuckDB `COPY` per week writes every team's ranks to `site/data/<season>-week<NN>.json`, after the data tests.
- Added `site/scout.html`: pick any team, season or last 4 games, each metric on a 32-team strip; under-30-play numbers greyed; "What stands out" and shifts use the same rules as the one-pager. Staff notes go in `site/notes/<slug>.md`.
- Rebuilt the data through Week 7: all 10 tests pass. The Week 8 SEA one-pager committed Oct 26 predates SEA's Week 7 game (Oct 25 vs KC), so the first workflow run will refresh it.
- Not verified: `export_site_data()` in R (no R here; the same SQL was run through DuckDB directly).
