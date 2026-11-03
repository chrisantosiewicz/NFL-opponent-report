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

## 2026-10-30: Trade check (Claude, at Chris's request)
- Chris asked for a check on trades made any time this season up to the deadline (Nov 10, 2026), and a display for it.
- Added: trade feed + `config/trades_manual.csv` + weekly-roster detection → `stg_trades`; `trade_impact` (usage before the move, games since, "regular" flag); 3 data tests; `check_trades()` in the run log with Actions warnings; "Roster changes" box on the report.
- Found: nflverse's trade feed stops at Apr 17, 2026, so all seven in-season trades are in the manual CSV (seeded from NFL.com's tracker). Rosters also flagged G Christian Haynes SEA → MIA (Week 8), not in any trade list.
- Verified on real nflverse data through Week 8: all models build, all 13 tests pass, SEA Week 8 and TB Week 9 render on one page. The R side was run with a SQLite stand-in for duckdb (CRAN was blocked in the build container), so the first real run in Actions is the end-to-end check.

## 2026-11-02: Top target, formation tells, generated draft notes (Claude, at Chris's request)
- Chris asked for the SEA notes to cover the top-target receiver and the Simmons trade, as a narrative approach rather than isolated stat bullets, and for the method to be part of the weekly pipeline.
- Merged PR #3's trade check into this branch. Simmons (TEN to CHI, Oct 29) is in `config/trades_manual.csv` from NFL.com's tracker; nflverse weekly rosters list him with CHI in Week 8.
- Added `game_windows`, `receiver_targets`, `top_target`, `formation_tells` and `draft_notes`, plus 4 tests (17 in all, all passing on data through Week 8).
- `draft_notes` writes "The approach" (identity and whether it works, roster moves on their offense and our defense, the passing game through the top target, 3rd & long and late-half results) and "What to look for" (moves to watch, formation tells, where the top target lines up, watched shifts). The live page shows it for any team without staff notes.
- Not verified: `write_draft_notes()` in R (no R here; the same query and Markdown were produced from Python).

- Added the offensive side: `defense_splits` (runs vs dropbacks allowed by down and distance, red zone, season and last 4) and `defense_vs_position` (WR/TE/RB targets allowed), plus 2 tests (19 in all, all passing). `defense_splits` season totals are checked against the offense-side snapshot so the two views can't drift.
- `draft_notes` (now `25_`) has four sections every week: Stopping their offense, Attacking their defense, What to look for on defense, What to look for on offense. Their defensive roster moves and ours on offense feed the attack half. Seattle's staff notes got the same sections.
- Added `play_direction` from nflverse's charted run lane (`run_location`, `run_gap`) and pass area (`pass_location`, `pass_length`): share, EPA and league rank by bucket for each offense and defense, by early down, 3rd & 1-3 / 4-6 / 7+, red zone and all neutral downs. New test `test_play_direction_shares` (shares add to 1, buckets valid, offense and defense totals match). 20 tests, all passing.
- `draft_notes` (now `27_`) adds a "where it goes" paragraph to Stopping their offense, a run-lane and throw-area paragraph to Attacking their defense, and look-for bullets on both sides. Seattle's staff notes got the same.
- Notes box on the live page is now "Scouting Notes" with a Defense / Offense toggle under the title. Sections are sorted by their `## ` headings ("Attacking..." or "...on offense" go to Offense, the rest to Defense); the toggle is hidden when a team's notes only have one side, and the choice carries over when switching teams.
