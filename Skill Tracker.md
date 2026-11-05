# Skill Tracker: NFL Opponent Tendency Report

Ratings are 1 to 5. **1** = haven't done it, **2** = done it with heavy help, **3** = can do it alone with a reference, **4** = can do it alone and explain every choice, **5** = could teach it or do it live in an interview.

Ratings are evidence-based: a rating only moves when there is a commit, file, or interview answer to point at. Baselines marked **(pending)** are waiting on Chris's evidence.

Updated: 2026-10-26 (v1 pipeline built by Claude at Chris's request; ratings move only when Chris's own work is committed)

| # | Skill | Baseline | Current | Evidence | Next step |
|---|-------|----------|---------|----------|-----------|
| 1 | SQL for football data (CTEs, window frames, PERCENT_RANK, snapshot tables, as-of joins, tests as queries) | (pending) | — | Brief: joins and window functions in DuckDB over Parquet (MLB next-pitch project); CTEs starting early Nov in sponsorship project. *Need: a link to one MLB query with a window function.* | Walkthrough §1–3: rebuild the third-down CASE and the rolling 3rd-down query from memory; check against the answer table. |
| 2 | Small-sample judgment (minimum n, showing n, shrinkage, noise vs tendency) | (pending) | — | Brief: thesis bootstrap CIs for EPA, ANOVA with Bonferroni. *Need: the thesis section or code file for the bootstrap.* | Walkthrough §7: add shrinkage (`shrunk_value`) with a data-chosen k; bootstrap one PROE interval. |
| 3 | Football scouting translation (splits → what a coordinator does with them) | (pending) | — | Brief: Big Ten findings presented to SU football staff; halftime reports for SU Women's Soccer. *Need: one example finding you gave a coach and what they did with it.* | Walkthrough §8: write the "so what" line a coordinator would act on for each of the 3 things. |
| 4 | Report design (one page, findings as titles, nothing to decode) | (pending) | — | Brief: Tableau scouting reports (St. Louis CITY SC), offseason reports for 5 college programs. *Need: one of those reports or a screenshot.* | Week 3: friend test; log what confused them and what you cut. |
| 5 | Pipeline ownership (renv, failure handling, reading Actions logs, last good output stays live) | (pending) | — | Brief: daily Git, Quarto on GitHub Pages; first Actions workflow due Nov 15 (sponsorship tracker). *Need: link to that workflow once it runs.* | Walkthrough §9: break a test on a branch, run the workflow, find the failing line in the log. |
| 6 | Evaluation: predict, then grade (stretch) | (pending) | — | Brief: thesis random forests trained 2016–2023, tested out of sample on 2024–2025; McNemar's test. *Need: the out-of-sample results table.* | Late Dec: first prediction logged before a game, graded after. |
| 7 | Interview defense (explain and defend the work live) | (pending) | — | None yet in this project. | Walkthrough §10: answer the 5 questions out loud; send answers for feedback. |

## Weekly log

| Week | Dates | Skills practiced | Rating changes | Evidence |
|------|-------|------------------|----------------|----------|
| 0 (kickoff) | Oct 25 | — | Baselines pending | This file |
| 0 (v1 build) | Oct 26 | All (reading) | None: Claude wrote v1 at Chris's request | `docs/walkthrough.md`: exercises ✍️ per skill. Rewrites committed by Chris count as evidence. |
