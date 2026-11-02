-- formation_tells: early-down play calls by formation, season to date before
-- each week. One row per season x as_of_week x team. Same plays as the
-- early-down split (1st and 2nd down, 5-95% win probability), so the shares
-- line up with the report's shotgun rate.
--
-- The notes use it to say what a formation tells you: "under center 55% of
-- early downs, and they ran on 64% of those snaps".

CREATE OR REPLACE TABLE formation_tells AS
WITH plays AS (
    SELECT w.season, w.as_of_week, w.team, p.is_shotgun, p.is_pass, p.epa
    FROM game_windows w
    JOIN stg_plays p ON p.game_id = w.game_id AND p.team = w.team
    WHERE p.is_early_down AND p.is_neutral_wp
),

by_team AS (
    SELECT season, as_of_week, team,
           COUNT(*)                                          AS plays,
           COUNT(*) FILTER (WHERE is_shotgun = 0)            AS uc_plays,
           SUM(1 - is_pass) FILTER (WHERE is_shotgun = 0)    AS uc_runs,
           AVG(epa) FILTER (WHERE is_shotgun = 0)            AS uc_epa,
           COUNT(*) FILTER (WHERE is_shotgun = 1)            AS sg_plays,
           SUM(is_pass) FILTER (WHERE is_shotgun = 1)        AS sg_passes,
           AVG(epa) FILTER (WHERE is_shotgun = 1)            AS sg_epa
    FROM plays
    GROUP BY ALL
)

SELECT
    *,
    uc_plays  * 1.0 / NULLIF(plays, 0)    AS uc_share,
    uc_runs   * 1.0 / NULLIF(uc_plays, 0) AS uc_run_rate,
    sg_passes * 1.0 / NULLIF(sg_plays, 0) AS sg_pass_rate,
    -- league rates on the same plays, for "more than most teams"
    SUM(uc_runs)   OVER lg * 1.0 / NULLIF(SUM(uc_plays) OVER lg, 0) AS league_uc_run_rate,
    SUM(sg_passes) OVER lg * 1.0 / NULLIF(SUM(sg_plays) OVER lg, 0) AS league_sg_pass_rate
FROM by_team
WINDOW lg AS (PARTITION BY season, as_of_week);
