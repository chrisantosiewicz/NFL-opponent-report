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

## 2026-10-30: Trade check (Claude, at Chris's request)
- Chris asked for a check on trades made any time this season up to the deadline (Nov 10, 2026), and a display for it.
- Added: trade feed + `config/trades_manual.csv` + weekly-roster detection → `stg_trades`; `trade_impact` (usage before the move, games since, "regular" flag); 3 data tests; `check_trades()` in the run log with Actions warnings; "Roster changes" box on the report.
- Found: nflverse's trade feed stops at Apr 17, 2026, so all seven in-season trades are in the manual CSV (seeded from NFL.com's tracker). Rosters also flagged G Christian Haynes SEA → MIA (Week 8), not in any trade list.
- Verified on real nflverse data through Week 8: all models build, all 13 tests pass, SEA Week 8 and TB Week 9 render on one page. The R side was run with a SQLite stand-in for duckdb (CRAN was blocked in the build container), so the first real run in Actions is the end-to-end check.
