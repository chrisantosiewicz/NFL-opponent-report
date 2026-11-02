-- defense_vs_position: production each defense allows to wide receivers,
-- tight ends and running backs as pass targets, season to date before each
-- week. One row per season x as_of_week x defense x position.
--
-- Position comes from nflverse's player table (raw_players) for the targeted
-- player; FB counts as RB. Targets with no known position are left out.
-- rank_allowed 1 = allows the MOST EPA per target to that position.

CREATE OR REPLACE TABLE defense_vs_position AS
WITH positions AS (
    SELECT DISTINCT gsis_id,
           CASE WHEN position IN ('RB', 'FB', 'HB') THEN 'RB' ELSE position END AS position
    FROM raw_players
    WHERE position IN ('WR', 'TE', 'RB', 'FB', 'HB')
),

targets AS (
    SELECT w.season, w.as_of_week, w.team AS defense, pos.position,
           p.epa, p.yards_gained, p.is_success
    FROM game_windows w
    JOIN stg_plays p ON p.game_id = w.game_id AND p.opponent = w.team
    JOIN positions pos ON pos.gsis_id = p.receiver_id
    WHERE p.is_pass = 1
),

games AS (
    SELECT season, as_of_week, team AS defense, COUNT(*) AS games
    FROM game_windows GROUP BY ALL
),

totals AS (
    SELECT t.season, t.as_of_week, t.defense, t.position, g.games,
           COUNT(*)                          AS targets,
           SUM(COALESCE(t.yards_gained, 0))  AS yards,
           SUM(COALESCE(t.epa, 0))           AS sum_epa,
           SUM(COALESCE(t.is_success, 0))    AS successes
    FROM targets t
    JOIN games g USING (season, as_of_week, defense)
    GROUP BY ALL
)

SELECT
    *,
    sum_epa / targets                AS epa_per_target,
    yards * 1.0 / games              AS yards_per_game,
    targets * 1.0 / games            AS targets_per_game,
    RANK() OVER lg_epa               AS rank_allowed,
    RANK() OVER lg_yards             AS yards_rank_allowed,
    COUNT(*) OVER lg                 AS teams,
    SUM(sum_epa) OVER lg / SUM(targets) OVER lg AS league_epa_per_target
FROM totals
WINDOW lg       AS (PARTITION BY season, as_of_week, position),
       lg_epa   AS (PARTITION BY season, as_of_week, position ORDER BY sum_epa / targets DESC),
       lg_yards AS (PARTITION BY season, as_of_week, position ORDER BY yards * 1.0 / games DESC);
