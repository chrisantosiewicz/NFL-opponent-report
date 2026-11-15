-- coverage_team / coverage_players: how each defense plays the pass and how
-- each offense and its top players do against it, for the attack plan.
--
-- This season (FTN charting, season to date before each week, like every
-- other model): blitz rate on dropbacks, average pass rushers, 8+ box rate
-- on designed runs, play-action rate, and EPA per play with and without a
-- blitz. side 'offense' = the team's own plays, 'defense' = plays against it.
-- blitz_rank 1 = blitzes the most (defense) / faces the most blitzes
-- (offense); blitz_epa_rank 1 = best EPA vs the blitz (offense) / allows the
-- most vs the blitz (defense). Ranks need 30+ charted dropbacks.
--
-- Last season (participation, full regular season and playoffs): man and
-- zone rates on dropbacks, the most-used coverage shell and its share, and
-- EPA per dropback vs man and vs zone. Last season's numbers belong to last
-- season's roster and coordinator: the page labels them.
--
-- coverage_players: the receivers and backs in player_trends, targets, yards
-- and EPA per target vs blitz / no blitz (this season, his current team) and
-- vs man / zone (last season, whatever team he was on).

CREATE OR REPLACE TABLE coverage_team AS
WITH plays AS (
    SELECT w.season, w.as_of_week, w.team,
           CASE WHEN p.team = w.team THEN 'offense' ELSE 'defense' END AS side,
           p.is_pass, p.is_run, p.epa, c.is_blitz, c.pass_rushers, c.is_heavy_box, c.is_play_action
    FROM game_windows w
    JOIN stg_plays p    ON p.game_id = w.game_id AND w.team IN (p.team, p.opponent)
    JOIN stg_charting c ON c.game_id = p.game_id AND c.play_id = p.play_id
    WHERE c.has_ftn
),

this_season AS (
    SELECT season, as_of_week, team, side,
           COUNT(*) FILTER (WHERE is_pass = 1)                                  AS dropbacks,
           SUM(is_blitz) FILTER (WHERE is_pass = 1)                             AS blitzes,
           AVG(pass_rushers) FILTER (WHERE is_pass = 1)                         AS avg_rushers,
           SUM(COALESCE(epa, 0)) FILTER (WHERE is_pass = 1 AND is_blitz = 1)    AS blitz_sum_epa,
           SUM(COALESCE(epa, 0)) FILTER (WHERE is_pass = 1 AND is_blitz = 0)    AS noblitz_sum_epa,
           COUNT(*) FILTER (WHERE is_run = 1 AND is_heavy_box IS NOT NULL)      AS runs,
           SUM(is_heavy_box) FILTER (WHERE is_run = 1)                          AS heavy_box_runs,
           SUM(COALESCE(epa, 0)) FILTER (WHERE is_run = 1 AND is_heavy_box = 1) AS heavy_box_sum_epa,
           SUM(is_play_action) FILTER (WHERE is_pass = 1)                       AS play_action,
           SUM(COALESCE(epa, 0)) FILTER (WHERE is_pass = 1 AND is_play_action = 1) AS pa_sum_epa
    FROM plays
    GROUP BY ALL
),

rated AS (
    SELECT *,
           blitzes * 1.0 / NULLIF(dropbacks, 0)                     AS blitz_rate,
           blitz_sum_epa / NULLIF(blitzes, 0)                       AS blitz_epa,
           noblitz_sum_epa / NULLIF(dropbacks - blitzes, 0)         AS noblitz_epa,
           heavy_box_runs * 1.0 / NULLIF(runs, 0)                   AS heavy_box_rate,
           heavy_box_sum_epa / NULLIF(heavy_box_runs, 0)            AS heavy_box_epa,
           play_action * 1.0 / NULLIF(dropbacks, 0)                 AS pa_rate,
           pa_sum_epa / NULLIF(play_action, 0)                      AS pa_epa,
           dropbacks >= 30                                          AS ranked
    FROM this_season
),

ranked AS (
    SELECT *,
           CASE WHEN ranked THEN RANK() OVER (PARTITION BY season, as_of_week, side, ranked ORDER BY blitz_rate DESC) END AS blitz_rank,
           CASE WHEN ranked AND blitzes >= 10 THEN RANK() OVER (PARTITION BY season, as_of_week, side, ranked AND blitzes >= 10
               ORDER BY blitz_epa DESC) END                                                                        AS blitz_epa_rank,
           CASE WHEN ranked THEN RANK() OVER (PARTITION BY season, as_of_week, side, ranked ORDER BY heavy_box_rate DESC) END AS heavy_box_rank,
           COUNT(*) FILTER (WHERE ranked) OVER (PARTITION BY season, as_of_week, side) AS teams,
           SUM(blitzes) OVER lg * 1.0 / SUM(dropbacks) OVER lg                         AS league_blitz_rate,
           SUM(blitz_sum_epa) OVER lg / SUM(blitzes) OVER lg                           AS league_blitz_epa,
           SUM(noblitz_sum_epa) OVER lg / SUM(dropbacks - blitzes) OVER lg             AS league_noblitz_epa
    FROM rated
    WINDOW lg AS (PARTITION BY season, as_of_week, side)
),

-- Last season, per team and side, from participation.
last_plays AS (
    SELECT p.season + 1 AS season, t.team,
           CASE WHEN p.team = t.team THEN 'offense' ELSE 'defense' END AS side,
           p.epa, c.man_zone, c.coverage
    FROM stg_charting c
    JOIN stg_plays p ON p.game_id = c.game_id AND p.play_id = c.play_id
    JOIN (SELECT team FROM dim_team) t ON t.team IN (p.team, p.opponent)
    WHERE p.is_pass = 1 AND c.man_zone IS NOT NULL
),

last_rates AS (
    SELECT season, team, side,
           COUNT(*)                                                   AS ly_dropbacks,
           AVG(CASE WHEN man_zone = 'man' THEN 1.0 ELSE 0 END)        AS ly_man_rate,
           AVG(epa) FILTER (WHERE man_zone = 'man')                   AS ly_man_epa,
           AVG(epa) FILTER (WHERE man_zone = 'zone')                  AS ly_zone_epa
    FROM last_plays GROUP BY ALL
),

last_shell AS (
    SELECT season, team, side, coverage AS ly_top_coverage,
           COUNT(*) * 1.0 / SUM(COUNT(*)) OVER (PARTITION BY season, team, side) AS ly_top_coverage_share,
           ROW_NUMBER() OVER (PARTITION BY season, team, side ORDER BY COUNT(*) DESC, coverage) AS rn
    FROM last_plays WHERE coverage IS NOT NULL
    GROUP BY season, team, side, coverage
)

SELECT r.*, l.ly_dropbacks, l.ly_man_rate, 1 - l.ly_man_rate AS ly_zone_rate, l.ly_man_epa, l.ly_zone_epa,
       s.ly_top_coverage, s.ly_top_coverage_share
FROM ranked r
LEFT JOIN last_rates l USING (season, team, side)
LEFT JOIN (SELECT * FROM last_shell WHERE rn = 1) s USING (season, team, side);

CREATE OR REPLACE TABLE coverage_players AS
WITH picks AS (
    SELECT DISTINCT season, as_of_week, team, player_id, player_name, position
    FROM player_trends WHERE role IN ('receiver', 'rusher')
),

this_season AS (
    SELECT k.season, k.as_of_week, k.team, k.player_id,
           COUNT(*) FILTER (WHERE c.is_blitz = 1)                                   AS blitz_targets,
           SUM(CASE WHEN p.is_complete = 1 THEN COALESCE(p.yards_gained, 0) ELSE 0 END) FILTER (WHERE c.is_blitz = 1) AS blitz_yards,
           SUM(COALESCE(p.epa, 0)) FILTER (WHERE c.is_blitz = 1)                    AS blitz_sum_epa,
           COUNT(*) FILTER (WHERE c.is_blitz = 0)                                   AS noblitz_targets,
           SUM(CASE WHEN p.is_complete = 1 THEN COALESCE(p.yards_gained, 0) ELSE 0 END) FILTER (WHERE c.is_blitz = 0) AS noblitz_yards,
           SUM(COALESCE(p.epa, 0)) FILTER (WHERE c.is_blitz = 0)                    AS noblitz_sum_epa
    FROM picks k
    JOIN game_windows w ON w.season = k.season AND w.as_of_week = k.as_of_week AND w.team = k.team
    JOIN stg_plays p    ON p.game_id = w.game_id AND p.team = k.team AND p.receiver_id = k.player_id AND p.is_pass = 1
    JOIN stg_charting c ON c.game_id = p.game_id AND c.play_id = p.play_id AND c.has_ftn
    GROUP BY ALL
),

last_season AS (
    SELECT p.season + 1 AS season, p.receiver_id AS player_id,
           COUNT(*) FILTER (WHERE c.man_zone = 'man')                               AS ly_man_targets,
           SUM(CASE WHEN p.is_complete = 1 THEN COALESCE(p.yards_gained, 0) ELSE 0 END) FILTER (WHERE c.man_zone = 'man') AS ly_man_yards,
           SUM(COALESCE(p.epa, 0)) FILTER (WHERE c.man_zone = 'man')                AS ly_man_sum_epa,
           COUNT(*) FILTER (WHERE c.man_zone = 'zone')                              AS ly_zone_targets,
           SUM(CASE WHEN p.is_complete = 1 THEN COALESCE(p.yards_gained, 0) ELSE 0 END) FILTER (WHERE c.man_zone = 'zone') AS ly_zone_yards,
           SUM(COALESCE(p.epa, 0)) FILTER (WHERE c.man_zone = 'zone')               AS ly_zone_sum_epa
    FROM stg_plays p
    JOIN stg_charting c ON c.game_id = p.game_id AND c.play_id = p.play_id
    WHERE p.is_pass = 1 AND p.receiver_id IS NOT NULL AND c.man_zone IS NOT NULL
    GROUP BY ALL
)

SELECT k.*,
       COALESCE(t.blitz_targets, 0) AS blitz_targets, t.blitz_yards, t.blitz_sum_epa,
       COALESCE(t.noblitz_targets, 0) AS noblitz_targets, t.noblitz_yards, t.noblitz_sum_epa,
       COALESCE(l.ly_man_targets, 0) AS ly_man_targets, l.ly_man_yards, l.ly_man_sum_epa,
       COALESCE(l.ly_zone_targets, 0) AS ly_zone_targets, l.ly_zone_yards, l.ly_zone_sum_epa
FROM picks k
LEFT JOIN this_season t USING (season, as_of_week, team, player_id)
LEFT JOIN last_season l USING (season, player_id);
