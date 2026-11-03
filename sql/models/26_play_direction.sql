-- play_direction: where each team runs and throws, and where its defense gets
-- run and thrown on, by down and distance, before each week. One row per
-- season x as_of_week x team x side x span x situation x play_type x
-- bucket_type x bucket.
--
-- side 'offense' = the team's own plays; 'defense' = plays against it.
-- Runs are designed runs only (scrambles are dropbacks), bucketed two ways:
--   width: inside (middle, guards), off_tackle, outside (around end)
--   side:  left, middle, right
-- Passes are aimed throws with a charted area (sacks, scrambles and most
-- throwaways have none), bucketed three ways:
--   depth: short, deep (nflverse: deep = 15+ air yards)
--   side:  left, middle, right
--   zone:  short_left ... deep_right
--   lane:  short_outside, short_middle, deep_outside, deep_middle (outside =
--          left or right of the hashes, so a concept run to either side counts)
-- Shares are within a bucket_type, so they add to 1 (test_play_direction_shares).
-- Situations and the 5-95% win-probability filter match defense_splits.
--
-- epa_rank: offense 1 = best EPA per play to that bucket; defense 1 = allows
-- the MOST. Ranks only count teams with 5+ plays in the bucket.
--
-- So one big play can't make a hot spot: epa_wo_best is EPA per play with the
-- bucket's single best play taken out (rank_wo_best ranks on it), next to
-- median yards, success rate and explosive rate (runs 10+, passes 20+ yards).

CREATE OR REPLACE TABLE play_direction AS
WITH plays AS (
    SELECT w.season, w.as_of_week, w.team, w.in_last4,
           CASE WHEN p.team = w.team THEN 'offense' ELSE 'defense' END AS side,
           p.*
    FROM game_windows w
    JOIN stg_plays p ON p.game_id = w.game_id AND w.team IN (p.team, p.opponent)
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

buckets AS (
    -- designed runs with a charted lane
    SELECT season, as_of_week, team, side, span, situation, 'run' AS play_type,
           'width' AS bucket_type,
           CASE WHEN run_location = 'middle' OR run_gap = 'guard' THEN 'inside'
                WHEN run_gap = 'tackle' THEN 'off_tackle'
                ELSE 'outside' END AS bucket,
           epa, is_success, yards_gained
    FROM spans
    WHERE is_run = 1 AND run_location IS NOT NULL
      AND (run_location = 'middle' OR run_gap IS NOT NULL)
    UNION ALL
    SELECT season, as_of_week, team, side, span, situation, 'run', 'side', run_location,
           epa, is_success, yards_gained
    FROM spans
    WHERE is_run = 1 AND run_location IS NOT NULL
      AND (run_location = 'middle' OR run_gap IS NOT NULL)
    -- aimed passes with a charted area
    UNION ALL
    SELECT season, as_of_week, team, side, span, situation, 'pass', 'depth', pass_length,
           epa, is_success, yards_gained
    FROM spans
    WHERE is_pass = 1 AND pass_location IS NOT NULL AND pass_length IS NOT NULL
    UNION ALL
    SELECT season, as_of_week, team, side, span, situation, 'pass', 'side', pass_location,
           epa, is_success, yards_gained
    FROM spans
    WHERE is_pass = 1 AND pass_location IS NOT NULL AND pass_length IS NOT NULL
    UNION ALL
    SELECT season, as_of_week, team, side, span, situation, 'pass', 'lane',
           pass_length || CASE WHEN pass_location = 'middle' THEN '_middle' ELSE '_outside' END,
           epa, is_success, yards_gained
    FROM spans
    WHERE is_pass = 1 AND pass_location IS NOT NULL AND pass_length IS NOT NULL
    UNION ALL
    SELECT season, as_of_week, team, side, span, situation, 'pass', 'zone',
           pass_length || '_' || pass_location,
           epa, is_success, yards_gained
    FROM spans
    WHERE is_pass = 1 AND pass_location IS NOT NULL AND pass_length IS NOT NULL
),

totals AS (
    SELECT season, as_of_week, team, side, span, situation, play_type, bucket_type, bucket,
           COUNT(*)                        AS plays,
           SUM(COALESCE(epa, 0))           AS sum_epa,
           SUM(COALESCE(is_success, 0))    AS successes,
           SUM(COALESCE(yards_gained, 0))  AS yards,
           MAX(COALESCE(epa, 0))           AS best_epa,
           MEDIAN(COALESCE(yards_gained, 0)) AS median_yards,
           SUM(CASE WHEN yards_gained >= CASE WHEN play_type = 'run' THEN 10 ELSE 20 END THEN 1 ELSE 0 END) AS explosives
    FROM buckets
    GROUP BY ALL
),

shared AS (
    SELECT *,
           SUM(plays) OVER (PARTITION BY season, as_of_week, team, side, span, situation,
                                         play_type, bucket_type) AS type_plays
    FROM totals
)

SELECT
    *,
    plays * 1.0 / type_plays                                       AS share,
    sum_epa / plays                                                AS epa_per_play,
    successes * 1.0 / plays                                        AS success_rate,
    yards * 1.0 / plays                                            AS yards_per_play,
    explosives * 1.0 / plays                                       AS explosive_rate,
    CASE WHEN plays > 1 THEN (sum_epa - best_epa) / (plays - 1) END AS epa_wo_best,
    SUM(successes) OVER lg * 1.0 / SUM(plays) OVER lg              AS league_success,
    SUM(yards) OVER lg * 1.0 / SUM(plays) OVER lg                  AS league_yards,
    SUM(plays) OVER lg * 1.0
      / SUM(type_plays) OVER lg                                    AS league_share,
    SUM(sum_epa) OVER lg / SUM(plays) OVER lg                      AS league_epa,
    CASE WHEN plays >= 5 THEN
        RANK() OVER (PARTITION BY season, as_of_week, side, span, situation, play_type,
                                  bucket_type, bucket, plays >= 5
                     ORDER BY sum_epa / plays DESC) END            AS epa_rank,
    CASE WHEN plays >= 5 THEN
        RANK() OVER (PARTITION BY season, as_of_week, side, span, situation, play_type,
                                  bucket_type, bucket, plays >= 5
                     ORDER BY (sum_epa - best_epa) / (plays - 1) DESC) END AS rank_wo_best,
    COUNT(*) FILTER (WHERE plays >= 5) OVER lg                     AS ranked_teams
FROM shared
WINDOW lg AS (PARTITION BY season, as_of_week, side, span, situation, play_type,
                           bucket_type, bucket);
