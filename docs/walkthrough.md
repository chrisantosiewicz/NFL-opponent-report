# Walkthrough: how the pipeline works, and how to own it

Written Oct 26, 2026, after the first full build. Read it with the code open.

**Read this first: who wrote what.** You asked me to build v1 of everything, including the SQL models. That's fine, but it changes what you can claim. The resume line says *you* built it, and in an interview you have to walk through every line. So each section ends with **exercises**. The ones marked ✍️ are "close the file and rebuild it from memory". Commit your rewrites under your name. When the git history shows your versions of the key queries, the resume line is honest. Until then it isn't, and I'll keep flagging that.

Each section names the skill it builds (numbers match `Skill Tracker.md`).

---

## 0. The big picture (5 min)

```
nflreadr (R)  ──►  raw_* tables in data/nfl.duckdb
                      │
          sql/models/*.sql, run in file-name order by build_models()
                      │
   stg_plays ─► team_game_tendencies ─► team_rolling ─► tendency_snapshot ─► tendency_ranks
   dim_team                                                                ├► last_season_ranks
   stg_team_games ─────────────────────────────────────────────────────────┘└► three_things
                      │
          sql/tests/*.sql: every query must return 0 rows, or the run stops
                      │
          report/opponent_report.qmd (Quarto, params = opponent + week)
                      │
          site/reports/2026-week08-SEA.html (+ .pdf)  ─►  site/index.html (latest + archive)
                      │
          GitHub Actions: Tue 14:00 UTC, Wed retry  ─►  GitHub Pages
```

One command does it all: `Rscript run_pipeline.R`. Every design rule (play filter, buckets, the 5–95% window) is in the README's Definitions table, and in exactly one place in the code (`01_stg_plays.sql` and `10_team_game_tendencies.sql`).

Design rules that run through the whole build:
1. **R moves data, SQL holds the logic.** `load_raw_data()` doesn't transform anything. If you want to change a definition, it's a SQL change.
2. **Store counts, compute rates last.** Models keep `plays`, `pass_plays` and `sum_xpass`, not `pass_rate`. Section 2 explains why.
3. **Every number travels with its n.** `tendency_ranks` has an `n` column on every row, and the report prints it.
4. **Leakage is a test, not a promise.** `test_snapshot_no_leakage.sql` fails if any snapshot uses a game from its own week or later.

---

## 1. `stg_plays`: what counts as a play (Skill 1)

File: `sql/models/01_stg_plays.sql`

- `play_type IN ('pass', 'run')` keeps real scrimmage plays. It drops `no_play` (penalties that wipe out the play), kicks, `qb_kneel` and `qb_spike`. In 2025 there were 4,723 `no_play` rows, about 9% of all rows.
- `down IS NOT NULL` drops two-point tries (325 rows across 2024–26).
- **`is_pass` comes from the `pass` column, not from `play_type`.** In nflverse, a QB scramble has `play_type = 'run'` but `pass = 1`. That's a dropback, and the `xpass` model predicts dropbacks. If you counted scrambles as runs, a mobile QB's team would look run-heavy and its PROE would be wrong. There were 2,669 scrambles in 2024–26.
- The situation flags are all built here, once, so every downstream model buckets plays the same way.

**Why questions**
1. Why do we drop `no_play` rows if a holding penalty on a pass still tells you they called a pass?
2. Should a sack count as a pass? Defend your answer to a run-game coordinator.

**Exercises**
- Count how many 2025 rows each filter removes, one filter at a time. Which filter matters most for the Bears?
- ✍️ Rewrite the `CASE` for `third_down_distance` from memory.

---

## 2. `team_game_tendencies`: counts, not rates, and the spine (Skill 1, Skill 2)

File: `sql/models/10_team_game_tendencies.sql`

**Where the CTEs come in.** There are four CTEs, each one step:
1. `plays_by_situation` stacks one `SELECT` per situation with `UNION ALL`. A play can be in several situations (3rd-and-2 at the 15 counts as both `third_short` and `red_zone`), so you can't use one `CASE`.
2. `situation_totals` holds counts and sums per team, game and situation.
3. `team_games` is the spine: every game each team played.
4. `situations` lists every situation.

**Why counts, not rates.** Say a team throws 2 of 2 red-zone plays one week (100%) and 3 of 10 the next (30%). The average of the two game rates is 65%. The real rate is 5 of 12, 42%. Averaging rates gives a 2-play game the same weight as a 10-play game. Storing counts lets every later model add plays first and divide once.

**Why the spine.** 63 of 1,350 team-games had zero red-zone plays. Without the spine those games have no row. Then `ROWS BETWEEN 3 PRECEDING` in the next model would reach back 5 or 6 games for red zone while still covering 4 for early downs. The `CROSS JOIN` spine plus `LEFT JOIN ... COALESCE(..., 0)` gives every team-game a row for every situation, even at 0 plays.

**Exercises**
- Delete the spine (use `situation_totals` directly) and rebuild. Find a team whose red-zone `last4` span now covers more than 4 calendar games. Then write a data test that would have caught it.
- Explain in two sentences why `proe` uses `xpass_plays` as the denominator, not `plays`. (Hint: 325 plays have no `xpass`.)

---

## 3. `team_rolling`: window frames (Skill 1, most likely live SQL test)

File: `sql/models/11_team_rolling.sql`

- `ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW` gives season to date. `ROWS BETWEEN 3 PRECEDING AND CURRENT ROW` gives the last 4 *rows*, which means the last 4 *games*: a bye week has no row, so it's skipped.
- `RANGE BETWEEN 3 PRECEDING` on `week` would mean "weeks within 3 of this one", so a bye would leave only 3 games. Know this difference cold. Interviewers love it.
- The named `WINDOW` clause keeps the 20 `SUM() OVER` lines readable.
- The final `UNION ALL` turns the two spans into rows (`span = 'season' | 'last4'`), so the next models handle both the same way.

**✍️ Exercise (do this one twice, a few days apart):** with only `stg_plays` open, write the Bears' 2025 regular-season **rolling last-4-games 3rd-down pass rate**, one row per game, with the play count. Check yourself against these values:

| week | 3rd-down plays | last-4 pass rate | last-4 plays |
|-----:|----:|-----:|----:|
| 1 | 12 | 0.917 | 12 |
| 4 | 17 | 0.786 | 56 |
| 6 | 10 | 0.759 | 54 |
| 14 | 16 | 0.625 | 64 |
| 18 | 11 | 0.766 | 47 |

(Week 5 was a bye, and week 6's window is weeks 2, 3, 4 and 6.) If your week-6 number is different, check the frame: you probably used `RANGE`, or averaged game rates.

---

## 4. `tendency_snapshot`: as-of join and leakage (Skill 1)

File: `sql/models/12_tendency_snapshot.sql`

The question it answers: *on the Tuesday before week N, what did we know?* For each `(season, as_of_week)` from the schedule, it joins to `team_rolling` rows with `r.week < w.as_of_week`. Then `ROW_NUMBER() ... ORDER BY r.week DESC` keeps only the most recent one, `recency = 1`. That's an as-of join written in portable SQL.

- The strict `<` is the entire leakage guard. I checked the test by changing it to `<=`: `test_snapshot_no_leakage.sql` failed with 21,600 rows. Do the same yourself so you've seen it fail.
- The as-of weeks come from the **schedule**, not from `team_rolling`. That way a team on a bye still has a snapshot that week, and league ranks always cover 32 teams. `test_snapshot_has_all_teams.sql` guards that.
- Week 1 has no rows on purpose: nothing is known yet that season. The report falls back to last season.

**Exercises**
- ✍️ Rewrite it with DuckDB's `ASOF JOIN`. Prove the two give identical rows with `(SELECT ... FROM a EXCEPT SELECT ... FROM b)` in both directions. Then say which one you'd show in an interview, and why.
- Why does a report for a Thursday game in week 12 still use only weeks 1–11, even though it publishes on Tuesday?

---

## 5. Ranks, last season, "3 things" (Skill 1, Skill 2)

Files: `13_tendency_ranks.sql`, `14_last_season_ranks.sql`, `15_three_things.sql`

- `RANK() ... ORDER BY value DESC` puts 1 at the highest value. `PERCENT_RANK()` ascending runs from 0 (lowest) to 1 (highest), computed as `(rank − 1) / (teams − 1)`.
- **Top 10% means `pctile >= 0.9`**. With 32 teams, the 4th-highest team has rank 29 ascending, so 28/31 = 0.903. That makes "top 10%" the top 4 and "bottom 10%" the bottom 4.
- **Last season** doesn't need new math. The snapshot taken before the first playoff week *is* the full regular season, so `14_last_season_ranks.sql` just filters `tendency_ranks` to that week.
- **"3 things"**: a season metric in the top or bottom 10% on 30 or more plays, at most one per situation, ranked by how extreme it is.

**Why questions**
1. `league_avg` is the average of the 32 team rates, not the league's total pass plays ÷ total plays. When do those differ, and which should the report use?
2. A team is 2nd in 3rd-and-short pass rate on 31 plays. Should that headline the box? (This sets up section 7.)

---

## 6. Data tests (Skill 1, Skill 5)

Folder: `sql/tests/`. All 10 pass on 2024–2026 data as of Oct 26.

| Test | Guards against |
|------|----------------|
| `test_stg_plays_unique` | duplicated plays (double-loading a season) |
| `test_stg_plays_down_not_null` | someone loosening the staging filter |
| `test_team_in_dim_team` | abbreviation mismatches (LA vs LAR) silently dropping a team |
| `test_dim_team_has_32` | a bad teams pull |
| `test_plays_per_game_range` | partial games. Observed 99–158 plays per game and 30–91 per team-game; the test allows 80–200 and 25–110 |
| `test_completed_games_have_plays` | **freshness**: Monday night's game is final in the schedule but not yet in the play-by-play |
| `test_snapshot_no_leakage` | future data in a snapshot |
| `test_snapshot_has_all_teams` | ranks computed over fewer than 32 teams |
| `test_last4_window` | the last-4 span covering more than 4 games |
| `test_rates_in_range` | math bugs (a rate above 1) |

**Exercise:** write one more test of your own: *every situation's plays in a team-game are ≤ that team-game's `all_neutral` plays, except two_minute and trailing_8plus*. Explain why those two are the exceptions.

---

## 7. Small samples (Skill 2)

What's built: `MIN_N = 30` in `report/helpers.R`. Any number under 30 plays gets a red asterisk, and faded dots on the EPA chart. "3 things" requires 30 or more plays. Shifts require 30 or more plays in the last 4 games.

What isn't built, and is **yours to build**: shrinkage. A 3rd-and-short pass rate on 25 plays shouldn't be read at face value.
- ✍️ Add a `shrunk_value` column to `tendency_ranks`: `(pass_plays + k * league_rate) / (plays + k)`. Pick `k` by looking at how stable the 2025 first-half rates were in the second half. That's a defensible, data-driven `k`, and it makes a great interview story.
- Link to your thesis: bootstrap SEA's early-down PROE over plays (1,000 resamples) and put the 90% interval in a tooltip or footnote. Compare the interval width at 30 plays with the width at 300.

**Thesis sanity check (from the Week 2 plan, done now):** shotgun rate on 3rd down in the league was 98% on 3rd & 7+, about 97% on 3rd & 4–6, and 62–70% on 3rd & 1–3 (2024–2026). Check this against your thesis's "3rd down makes shotgun ~15× more likely". Are these numbers consistent with that odds ratio? Write the comparison in one paragraph, because it's a nice cross-validation for the README.

---

## 8. The report (Skill 3, Skill 4)

File: `report/opponent_report.qmd`, styles in `report.css`, wording in `helpers.R`.

- The params are `opponent`, `focal_team`, `season` and `week`. The report reads only `tendency_ranks`, `last_season_ranks` and `three_things` at that week, so it can't see the future either.
- Panel titles are **rule-based findings**, such as "Early downs: run-first, runs more than the situation calls for". They're facts. They are not yet coaching language.

**Exercises (this is where your coaching experience matters most)**
- Look at the rendered report (`site/reports/2026-week08-SEA.html`). For each "3 things" item, write the line a defensive coordinator would act on: *"So what: expect…, plan…"*. That translation is the most valuable thing a club analyst does, and it's the part I deliberately left to you.
- Friend test: show it to one football person for 2 minutes. Write down every place they paused, then cut or rename those parts.
- Decide whether `epa_play` belongs in the early-down table or only in the EPA panel. One page means every row has to earn its place.

---

## 9. Automation (Skill 5)

Files: `.github/workflows/weekly-report.yml`, `.github/workflows/renv-lock.yml`

- **Schedule:** Tuesday 14:00 UTC, September to February, with a Wednesday retry. If Monday night's play-by-play isn't out yet, the freshness test fails, the run stops before publishing, and Wednesday tries again.
- **Keeping the last good report:** the archive commit and the Pages deploy only run if `Run pipeline` succeeds. Any failure means nothing changes on the site, and GitHub emails you.
- **The archive** is the `site/reports/` folder, committed back to `main` by the bot. `build_site()` rebuilds `index.html` from whatever reports are on disk.
- **renv:** I couldn't create `renv.lock` here, because CRAN is blocked in my sandbox and the versions would have been wrong. `renv-lock.yml` creates it on a GitHub runner with real CRAN versions. Run it once (setup step 2 below).
- **Bears eliminated:** `find_next_game()` finds nothing, so the pipeline scouts both teams in every game of the next scheduled week.

**Exercises**
- Make a branch, break a test on purpose (for example, change the play-count range to 100–110), push, run the workflow on that branch, and read the failed log. Find the exact line that tells you which test failed. That's the `pipeline-failure-triage` skill, done by hand once.
- Explain why the Wednesday retry can't publish a report with leakage, even if it runs after the week's Thursday game.

---

## 10. Interview defense (Skill 7)

Practise answering these out loud in 60–90 seconds each. Send me your answers and I'll give feedback.

1. **"How do you know a tendency is real and not noise?"** A good answer covers: n shown everywhere, a 30-play minimum, top/bottom 10% only, and shrinkage or bootstrap intervals (once you've built them). Give a concrete example of a flag that disappeared once you applied the rule.
2. **"What happens when the pipeline breaks on a Tuesday?"** A good answer covers: tests gate publishing, the last good report stays up, the email, the Wednesday retry, how you read the log, and the most likely cause (nflverse release timing).
3. **"Write me the rolling 3rd-down query."** The section 3 exercise, from memory, with the `ROWS` vs `RANGE` explanation.
4. **"How do you prevent leakage?"** The strict `<` in the as-of join, the test, and why the schedule drives the as-of weeks.
5. **"Why 5–95% win probability?"** The answer you owe me from Oct 25.

---

## Setup you need to do (about 10 minutes, once)

1. **Turn on GitHub Pages:** repo Settings → Pages → Build and deployment → Source: **GitHub Actions**.
2. **Pin packages:** Actions tab → "Create or update renv.lock" → Run workflow. It commits `renv.lock`. Run it before step 3.
3. **First manual run:** Actions → "Weekly opponent report" → Run workflow (team `CHI`, date blank). Check that the site shows the SEA report.
4. **Local:** install R and Quarto, then `renv::restore()` and `Rscript run_pipeline.R`.

## What I verified here, and what I couldn't

Verified in my sandbox, on real nflverse data (2024, 2025, and 2026 through Week 7):
- `Rscript run_pipeline.R --skip-load` runs end to end with R 4.3, DuckDB, nflreadr and Quarto 1.6.
- All 10 tests pass, and the leakage test fails (21,600 rows) when `<` is changed to `<=`.
- The SEA Week 8 report renders to HTML, and to a one-page letter PDF via headless Chrome.
- Three cases work: `--date=2026-12-15` picks Week 15 at BUF; `--opponent=CAR --week=1` falls back to last season's numbers; a date after the Bears' last game falls back to "next week's matchups" and stops cleanly when the schedule has none yet.

Not verified:
- The GitHub Actions workflows. They only run on GitHub, so expect one or two fixes on the first run, and read those logs as Skill 5 practice.
- `load_raw_data()` loading schedules through `nflreadr::load_schedules()`. My sandbox blocks that download URL, so I loaded the same nflverse schedule file another way. On GitHub it uses the normal path.

Known rough edges, yours to decide:
- In the Week 1 fallback, the "Last season" column repeats the main numbers.
- The "3 things" box can show fewer than 3 items when fewer qualify. That's on purpose (SEA has 2), but a coach might expect 3.
- `league_avg` is an unweighted mean of team rates (see section 5).
