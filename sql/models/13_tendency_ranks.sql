-- tendency_ranks: one row per team x as_of_week x situation x span x metric,
-- with its value, sample size (n), and league rank among the 32 teams that week.
--
-- Metrics
--   pass_rate      dropbacks / plays
--   shotgun_rate   shotgun snaps / plays
--   proe           pass rate over expected: (dropbacks - sum of xpass) / plays with xpass
--   epa_play       EPA per play
--   epa_pass       EPA per dropback
--   epa_run        EPA per designed run
--
-- league_rank 1 = highest value. pctile = PERCENT_RANK, 0 = lowest, 1 = highest.

CREATE OR REPLACE TABLE tendency_ranks AS
WITH metrics AS (
    SELECT season, as_of_week, team, situation, span, through_week, games,
           'pass_rate' AS metric, pass_plays * 1.0 / NULLIF(plays, 0) AS value, plays AS n
    FROM tendency_snapshot
    UNION ALL
    SELECT season, as_of_week, team, situation, span, through_week, games,
           'shotgun_rate', shotgun_plays * 1.0 / NULLIF(plays, 0), plays
    FROM tendency_snapshot
    UNION ALL
    SELECT season, as_of_week, team, situation, span, through_week, games,
           'proe', (xpass_pass_plays - sum_xpass) / NULLIF(xpass_plays, 0), xpass_plays
    FROM tendency_snapshot
    UNION ALL
    SELECT season, as_of_week, team, situation, span, through_week, games,
           'epa_play', sum_epa / NULLIF(plays, 0), plays
    FROM tendency_snapshot
    UNION ALL
    SELECT season, as_of_week, team, situation, span, through_week, games,
           'epa_pass', sum_pass_epa / NULLIF(pass_plays, 0), pass_plays
    FROM tendency_snapshot
    UNION ALL
    SELECT season, as_of_week, team, situation, span, through_week, games,
           'epa_run', sum_run_epa / NULLIF(plays - pass_plays, 0), plays - pass_plays
    FROM tendency_snapshot
)

SELECT
    *,
    RANK() OVER league_week_desc AS league_rank,
    COUNT(value) OVER league_week AS league_teams,
    PERCENT_RANK() OVER league_week_asc AS pctile,
    AVG(value) OVER league_week AS league_avg
FROM metrics
WHERE value IS NOT NULL  -- e.g. a team with no red-zone runs has no epa_run; it isn't ranked
WINDOW
    league_week      AS (PARTITION BY season, as_of_week, situation, span, metric),
    league_week_desc AS (PARTITION BY season, as_of_week, situation, span, metric ORDER BY value DESC),
    league_week_asc  AS (PARTITION BY season, as_of_week, situation, span, metric ORDER BY value ASC);
