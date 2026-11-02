-- receiver_targets: who the ball goes to, as known before each week.
-- One row per season x as_of_week x team x span x situation x receiver, with
-- COUNTS (targets, team_targets, sum_epa) so shares are computed once.
--
-- A target is a pass play with a receiver listed (nflverse receiver_id):
-- completions, incompletions and interceptions, not sacks or throwaways with
-- no receiver. No win-probability filter: this is about who they throw to,
-- and late-game targets still say who they trust.
--
-- Situations (a target can be in several):
--   all, early_down, third_down, third_1_6 (3rd & 1-6), third_long (3rd & 7+),
--   red_zone, two_minute, trailing_8plus, deep (20+ air yards)

CREATE OR REPLACE TABLE receiver_targets AS
WITH targets AS (
    SELECT game_id, team, receiver_id, epa, air_yards, down, ydstogo,
           is_early_down, is_red_zone, is_two_minute, is_trailing_8plus
    FROM stg_plays
    WHERE is_pass = 1 AND receiver_id IS NOT NULL
),

by_situation AS (
    SELECT 'all'            AS situation, * FROM targets
    UNION ALL SELECT 'early_down',     * FROM targets WHERE is_early_down
    UNION ALL SELECT 'third_down',     * FROM targets WHERE down = 3
    UNION ALL SELECT 'third_1_6',      * FROM targets WHERE down = 3 AND ydstogo <= 6
    UNION ALL SELECT 'third_long',     * FROM targets WHERE down = 3 AND ydstogo >= 7
    UNION ALL SELECT 'red_zone',       * FROM targets WHERE is_red_zone
    UNION ALL SELECT 'two_minute',     * FROM targets WHERE is_two_minute
    UNION ALL SELECT 'trailing_8plus', * FROM targets WHERE is_trailing_8plus
    UNION ALL SELECT 'deep',           * FROM targets WHERE air_yards >= 20
),

per_game AS (
    SELECT game_id, team, situation, receiver_id,
           COUNT(*) AS targets, SUM(COALESCE(epa, 0)) AS sum_epa
    FROM by_situation
    GROUP BY ALL
),

spans AS (
    SELECT season, as_of_week, team, game_id, week, 'season' AS span FROM game_windows
    UNION ALL
    SELECT season, as_of_week, team, game_id, week, 'last4' FROM game_windows WHERE in_last4
),

totals AS (
    SELECT s.season, s.as_of_week, s.team, s.span, p.situation, p.receiver_id,
           SUM(p.targets) AS targets, SUM(p.sum_epa) AS sum_epa,
           MAX(s.week) AS through_week
    FROM spans s
    JOIN per_game p ON p.game_id = s.game_id AND p.team = s.team
    GROUP BY ALL
)

SELECT
    t.season, t.as_of_week, t.team, t.span, t.situation, t.receiver_id,
    COALESCE(pl.display_name, t.receiver_id)                                AS receiver_name,
    pl.position,
    t.targets,
    SUM(t.targets) OVER grp                                                 AS team_targets,
    SUM(t.sum_epa) OVER grp                                                 AS team_sum_epa,
    t.targets * 1.0 / SUM(t.targets) OVER grp                               AS share,
    t.sum_epa,
    MAX(t.through_week) OVER grp                                            AS through_week
FROM totals t
LEFT JOIN (SELECT DISTINCT gsis_id, display_name, position FROM raw_players) pl
  ON pl.gsis_id = t.receiver_id
WINDOW grp AS (PARTITION BY t.season, t.as_of_week, t.team, t.span, t.situation);
