# Skill Tracker: NFL Opponent Tendency Report

Ratings are 1 to 5. **1** = haven't done it, **2** = done it with heavy help, **3** = can do it alone with a reference, **4** = can do it alone and explain every choice, **5** = could teach it or do it live in an interview.

Ratings are evidence-based: a rating only moves when there is a commit, file, or interview answer to point at. Baselines marked **(pending)** are waiting on Chris's evidence.

Updated: 2026-10-25 (kickoff, before Week 1)

| # | Skill | Baseline | Current | Evidence | Next step |
|---|-------|----------|---------|----------|-----------|
| 1 | SQL for football data (CTEs, window frames, PERCENT_RANK, snapshot tables, as-of joins, tests as queries) | (pending) | — | Brief: joins and window functions in DuckDB over Parquet (MLB next-pitch project); CTEs starting early Nov in sponsorship project. *Need: a link to one MLB query with a window function.* | Week 1: write `stg_plays.sql` and the four data tests, explain each filter before review. |
| 2 | Small-sample judgment (minimum n, showing n, shrinkage, noise vs tendency) | (pending) | — | Brief: thesis bootstrap CIs for EPA, ANOVA with Bonferroni. *Need: the thesis section or code file for the bootstrap.* | Week 2: pick and defend the minimum-n rule for the "3 things to know" box; explain why 30 plays. |
| 3 | Football scouting translation (splits → what a coordinator does with them) | (pending) | — | Brief: Big Ten findings presented to SU football staff; halftime reports for SU Women's Soccer. *Need: one example finding you gave a coach and what they did with it.* | Week 3: write the five panel titles as findings, in coach language. |
| 4 | Report design (one page, findings as titles, nothing to decode) | (pending) | — | Brief: Tableau scouting reports (St. Louis CITY SC), offseason reports for 5 college programs. *Need: one of those reports or a screenshot.* | Week 3: friend test; log what confused them and what you cut. |
| 5 | Pipeline ownership (renv, failure handling, reading Actions logs, last good output stays live) | (pending) | — | Brief: daily Git, Quarto on GitHub Pages; first Actions workflow due Nov 15 (sponsorship tracker). *Need: link to that workflow once it runs.* | Week 4: cron workflow; deliberately break one run and read the log. |
| 6 | Evaluation: predict, then grade (stretch) | (pending) | — | Brief: thesis random forests trained 2016–2023, tested out of sample on 2024–2025; McNemar's test. *Need: the out-of-sample results table.* | Late Dec: first prediction logged before a game, graded after. |
| 7 | Interview defense (explain and defend the work live) | (pending) | — | None yet in this project. | End of Week 1: 2–3 hiring-manager questions on the staging models. |

## Weekly log

| Week | Dates | Skills practiced | Rating changes | Evidence |
|------|-------|------------------|----------------|----------|
| 0 (kickoff) | Oct 25 | — | Baselines pending | This file |
