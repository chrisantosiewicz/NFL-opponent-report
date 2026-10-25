# nfl-opponent-report

Every Tuesday during the NFL season, an automated pipeline pulls the latest NFL play-by-play, runs a set of SQL models in DuckDB, and publishes a one-page tendency report on the Chicago Bears' next opponent.

**Status:** kickoff (Oct 25, 2026). Build starts Nov 16; first automated report Tue Dec 15, 2026.

**Stack:** R (nflreadr) → DuckDB → hand-written `.sql` models run through DBI → data tests (queries that must return zero rows) → parameterized Quarto one-pager → GitHub Actions Tuesday cron → GitHub Pages with an archive.

## Definitions (locked Oct 25, 2026)

| Item | Definition |
|------|-----------|
| Scrimmage plays | Pass or run plays only. Exclude kneels, spikes, and no-play penalties. |
| Win-probability filter | Neutral splits (early downs, 3rd down, red zone) use plays with 5% ≤ `wp` ≤ 95% (`wp` = possession team's pre-snap win probability). |
| Situational splits | 2-minute and trailing by 8+ never use the WP filter. |
| Early downs | 1st and 2nd down |
| 3rd down | Short 1–3, medium 4–6, long 7+ yards to go |
| Red zone | Ball at the opponent's 20 or closer (`yardline_100 <= 20`) |
| 2-minute | Last 2:00 of either half (`half_seconds_remaining <= 120`) |
| Trailing by 8+ | `score_differential <= -8` |
| Window | Splits and ranks use the current season up to the report's week. Earlier seasons supply league baselines only. |
| Last-season ranks | Full-season 2025 league rank shown next to each 2026 rank where applicable, with a caveat when the opponent changed play callers. |
| Leakage | A report for week N uses only games before week N. |
| "3 things to know" | A metric in the league's top or bottom 10% with at least 30 plays. |

## Data credit

Play-by-play and schedule data from [nflverse](https://github.com/nflverse) (nflreadr / nflfastR), used under its open license.
