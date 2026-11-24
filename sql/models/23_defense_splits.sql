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
--
-- Opponent-adjusted (span 'season' only; NULL for 'last4'): epa_vs_expected is
-- EPA per play allowed above what the offenses it faced usually gain in that
-- situation, after crediting those offenses for the defenses they faced (three
-- rounds of offense <-> defense adjustment, like a simple rating system).
-- rank_allowed_adj 1 = softest after the adjustment. The soft/stout early-down
-- picks in the notes and report card use these (changed Nov 24, 2026: raw EPA
-- allowed hit 53% at predicting a single game, adjusted 55-56%).

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

-- Opponent adjustment: league average, then offense and defense ratings in
-- turns (residual EPA per play), three rounds each.
adj_plays AS (
    SELECT season, as_of_week, situation, CASE WHEN is_pass = 1 THEN 'pass' ELSE 'run' END AS play_type,
           defense, team AS offense, COALESCE(epa, 0) AS epa
    FROM by_situation
),
adj_lg AS (
    SELECT season, as_of_week, situation, play_type, AVG(epa) AS lg FROM adj_plays GROUP BY ALL
),
adj_r AS (
    SELECT a.*, a.epa - l.lg AS r FROM adj_plays a JOIN adj_lg l USING (season, as_of_week, situation, play_type)
),
o1 AS (SELECT season, as_of_week, situation, play_type, offense, AVG(r) AS o FROM adj_r GROUP BY ALL),
d1 AS (SELECT season, as_of_week, situation, play_type, defense, AVG(r - o) AS d
       FROM adj_r JOIN o1 USING (season, as_of_week, situation, play_type, offense) GROUP BY ALL),
o2 AS (SELECT season, as_of_week, situation, play_type, offense, AVG(r - d) AS o
       FROM adj_r JOIN d1 USING (season, as_of_week, situation, play_type, defense) GROUP BY ALL),
d2 AS (SELECT season, as_of_week, situation, play_type, defense, AVG(r - o) AS d
       FROM adj_r JOIN o2 USING (season, as_of_week, situation, play_type, offense) GROUP BY ALL),
o3 AS (SELECT season, as_of_week, situation, play_type, offense, AVG(r - d) AS o
       FROM adj_r JOIN d2 USING (season, as_of_week, situation, play_type, defense) GROUP BY ALL),
d3 AS (SELECT season, as_of_week, situation, play_type, defense, AVG(r - o) AS d
       FROM adj_r JOIN o3 USING (season, as_of_week, situation, play_type, offense) GROUP BY ALL),

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
    t.*,
    t.sum_epa / t.plays                                          AS epa_allowed,
    t.successes * 1.0 / t.plays                                  AS success_allowed,
    t.yards * 1.0 / t.plays                                      AS yards_per_play,
    RANK() OVER (PARTITION BY t.season, t.as_of_week, t.span, t.situation, t.play_type
                 ORDER BY t.sum_epa / t.plays DESC)              AS rank_allowed,
    PERCENT_RANK() OVER (PARTITION BY t.season, t.as_of_week, t.span, t.situation, t.play_type
                         ORDER BY t.sum_epa / t.plays)           AS pctile_allowed,
    COUNT(*) OVER (PARTITION BY t.season, t.as_of_week, t.span, t.situation, t.play_type) AS teams,
    SUM(t.sum_epa) OVER (PARTITION BY t.season, t.as_of_week, t.span, t.situation, t.play_type)
      / SUM(t.plays) OVER (PARTITION BY t.season, t.as_of_week, t.span, t.situation, t.play_type) AS league_epa,
    a.d                                                          AS epa_vs_expected,
    CASE WHEN a.d IS NOT NULL THEN
        RANK() OVER (PARTITION BY t.season, t.as_of_week, t.span, t.situation, t.play_type, a.d IS NULL
                     ORDER BY a.d DESC) END                      AS rank_allowed_adj
FROM totals t
LEFT JOIN d3 a ON t.span = 'season' AND a.season = t.season AND a.as_of_week = t.as_of_week
              AND a.situation = t.situation AND a.play_type = t.play_type AND a.defense = t.defense;
