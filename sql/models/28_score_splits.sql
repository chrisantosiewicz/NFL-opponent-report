-- score_splits: how each offense (and each defense, from the other side)
-- plays by score, in the situations where the score changes what a team is
-- trying to do, season to date before each week. One row per season x
-- as_of_week x team x side x situation x score_state.
--
-- Situations: two_minute (last 2 minutes of a half), third_down, red_zone, all.
-- Score states from the offense's side: trailing_9plus, trailing_1_8, tied,
-- leading_1_8, leading_9plus, plus two roll-ups: not_leading (tied or behind,
-- when a team has to move the ball) and leading (when it may be running the
-- clock). No win-probability filter: the score state is the filter.
--
-- So one play can't tell the story, each row has the median EPA and EPA with
-- the single best play taken out next to the mean.
-- epa_rank: offense 1 = best; defense 1 = allows the MOST. Teams with 10+
-- plays are ranked.

CREATE OR REPLACE TABLE score_splits AS
WITH plays AS (
    SELECT w.season, w.as_of_week, w.team,
           CASE WHEN p.team = w.team THEN 'offense' ELSE 'defense' END AS side,
           p.*,
           CASE WHEN p.score_differential <= -9 THEN 'trailing_9plus'
                WHEN p.score_differential < 0  THEN 'trailing_1_8'
                WHEN p.score_differential = 0  THEN 'tied'
                WHEN p.score_differential <= 8 THEN 'leading_1_8'
                ELSE 'leading_9plus' END AS state
    FROM game_windows w
    JOIN stg_plays p ON p.game_id = w.game_id AND w.team IN (p.team, p.opponent)
),

by_situation AS (
    SELECT 'two_minute' AS situation, * FROM plays WHERE is_two_minute
    UNION ALL SELECT 'third_down', * FROM plays WHERE down = 3
    UNION ALL SELECT 'red_zone',   * FROM plays WHERE is_red_zone
    UNION ALL SELECT 'all',        * FROM plays
),

by_state AS (
    SELECT state AS score_state, * FROM by_situation
    UNION ALL
    SELECT CASE WHEN state LIKE 'leading%' THEN 'leading' ELSE 'not_leading' END, * FROM by_situation
),

totals AS (
    SELECT season, as_of_week, team, side, situation, score_state,
           COUNT(*)                          AS plays,
           SUM(COALESCE(epa, 0))             AS sum_epa,
           MAX(COALESCE(epa, 0))             AS best_epa,
           MEDIAN(COALESCE(epa, 0))          AS median_epa,
           SUM(COALESCE(is_success, 0))      AS successes,
           SUM(is_pass)                      AS dropbacks,
           SUM(COALESCE(yards_gained, 0))    AS yards
    FROM by_state
    GROUP BY ALL
)

SELECT *,
    sum_epa / plays                                          AS epa_per_play,
    CASE WHEN plays > 1 THEN (sum_epa - best_epa) / (plays - 1) END AS epa_wo_best,
    successes * 1.0 / plays                                  AS success_rate,
    dropbacks * 1.0 / plays                                  AS pass_rate,
    yards * 1.0 / plays                                      AS yards_per_play,
    CASE WHEN plays >= 10 THEN
        RANK() OVER (PARTITION BY season, as_of_week, side, situation, score_state, plays >= 10
                     ORDER BY sum_epa / plays DESC) END      AS epa_rank,
    COUNT(*) FILTER (WHERE plays >= 10) OVER (PARTITION BY season, as_of_week, side, situation, score_state) AS ranked_teams,
    SUM(sum_epa) OVER (PARTITION BY season, as_of_week, side, situation, score_state)
      / SUM(plays) OVER (PARTITION BY season, as_of_week, side, situation, score_state) AS league_epa,
    SUM(successes) OVER (PARTITION BY season, as_of_week, side, situation, score_state) * 1.0
      / SUM(plays) OVER (PARTITION BY season, as_of_week, side, situation, score_state) AS league_success,
    SUM(dropbacks) OVER (PARTITION BY season, as_of_week, side, situation, score_state) * 1.0
      / SUM(plays) OVER (PARTITION BY season, as_of_week, side, situation, score_state) AS league_pass_rate
FROM totals;
