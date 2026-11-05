-- defense_splits: what each defense allows, against the run and the pass, by
-- down and distance, before each week. One row per season x as_of_week x
-- defense x span x situation x play_type ('run' or 'pass').
--
-- Same plays and situations as the offense side (stg_plays, 5-95% win
-- probability for the neutral splits), seen from the defense: a play counts
-- for its defteam. Dropbacks include sacks and scrambles, like pass_rate.
--
-- rank_allowed 1 = allows the MOST EPA per play (the softest defense there),
-- so "3rd-most" reads straight off it. pctile_allowed 1 = softest.

CREATE OR REPLACE TABLE defense_splits AS
WITH plays AS (
    SELECT w.season, w.as_of_week, w.team AS defense, w.in_last4, p.*
    FROM game_windows w
    JOIN stg_plays p ON p.game_id = w.game_id AND p.opponent = w.team
),

by_situation AS (
    SELECT 'early_down'   AS situation, * FROM plays WHERE is_early_down AND is_neutral_wp
    UNION ALL SELECT 'third_short',  * FROM plays WHERE third_down_distance = 'short'  AND is_neutral_wp
    UNION ALL SELECT 'third_medium', * FROM plays WHERE third_down_distance = 'medium' AND is_neutral_wp
    UNION ALL SELECT 'third_long',   * FROM plays WHERE third_down_distance = 'long'   AND is_neutral_wp
    UNION ALL SELECT 'red_zone',     * FROM plays WHERE is_red_zone AND is_neutral_wp
    UNION ALL SELECT 'all_neutral',  * FROM plays WHERE is_neutral_wp
),

spans AS (
    SELECT 'season' AS span, * FROM by_situation
    UNION ALL
    SELECT 'last4', * FROM by_situation WHERE in_last4
),

totals AS (
    SELECT season, as_of_week, defense, span, situation,
           CASE WHEN is_pass = 1 THEN 'pass' ELSE 'run' END AS play_type,
           COUNT(*)                        AS plays,
           SUM(COALESCE(epa, 0))           AS sum_epa,
           SUM(COALESCE(is_success, 0))    AS successes,
           SUM(COALESCE(yards_gained, 0))  AS yards
    FROM spans
    GROUP BY ALL
)

SELECT
    *,
    sum_epa / plays                                              AS epa_allowed,
    successes * 1.0 / plays                                      AS success_allowed,
    yards * 1.0 / plays                                          AS yards_per_play,
    RANK() OVER (PARTITION BY season, as_of_week, span, situation, play_type
                 ORDER BY sum_epa / plays DESC)                  AS rank_allowed,
    PERCENT_RANK() OVER (PARTITION BY season, as_of_week, span, situation, play_type
                         ORDER BY sum_epa / plays)               AS pctile_allowed,
    COUNT(*) OVER (PARTITION BY season, as_of_week, span, situation, play_type) AS teams,
    SUM(sum_epa) OVER (PARTITION BY season, as_of_week, span, situation, play_type)
      / SUM(plays) OVER (PARTITION BY season, as_of_week, span, situation, play_type) AS league_epa
FROM totals;
