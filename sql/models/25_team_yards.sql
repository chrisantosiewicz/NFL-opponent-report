-- team_yards: rushing and passing yards per game for every offense, and
-- allowed by every defense, season to date before each week. One row per
-- season x as_of_week x team x side ('offense' or 'defense').
--
-- Rushing = designed runs (scrambles are dropbacks, as everywhere else).
-- Passing = yards on dropbacks, so sacks count against it (net passing).
-- All plays count, not just 5-95% win probability: these are the totals
-- people quote. rush_rank / pass_rank 1 = the MOST yards (gained on offense,
-- allowed on defense), so "2nd in rushing yards" and "3rd-most allowed"
-- read straight off it.

CREATE OR REPLACE TABLE team_yards AS
WITH plays AS (
    SELECT w.season, w.as_of_week, w.team, w.game_id,
           CASE WHEN p.team = w.team THEN 'offense' ELSE 'defense' END AS side,
           p.is_run, p.is_pass, COALESCE(p.yards_gained, 0) AS yards
    FROM game_windows w
    JOIN stg_plays p ON p.game_id = w.game_id AND w.team IN (p.team, p.opponent)
),

totals AS (
    SELECT season, as_of_week, team, side,
           COUNT(DISTINCT game_id)                     AS games,
           SUM(is_run)                                 AS rushes,
           SUM(yards) FILTER (WHERE is_run = 1)        AS rush_yards,
           SUM(is_pass)                                AS dropbacks,
           SUM(yards) FILTER (WHERE is_pass = 1)       AS pass_yards
    FROM plays
    GROUP BY ALL
)

SELECT *,
    rush_yards * 1.0 / games                         AS rush_ypg,
    rush_yards * 1.0 / NULLIF(rushes, 0)             AS yards_per_carry,
    pass_yards * 1.0 / games                         AS pass_ypg,
    pass_yards * 1.0 / NULLIF(dropbacks, 0)          AS yards_per_dropback,
    RANK() OVER (PARTITION BY season, as_of_week, side ORDER BY rush_yards DESC) AS rush_rank,
    RANK() OVER (PARTITION BY season, as_of_week, side ORDER BY rush_yards * 1.0 / games DESC) AS rush_ypg_rank,
    RANK() OVER (PARTITION BY season, as_of_week, side ORDER BY pass_yards * 1.0 / games DESC) AS pass_ypg_rank,
    RANK() OVER (PARTITION BY season, as_of_week, side ORDER BY rush_yards * 1.0 / NULLIF(rushes, 0) DESC) AS ypc_rank,
    COUNT(*) OVER (PARTITION BY season, as_of_week, side) AS teams
FROM totals;
