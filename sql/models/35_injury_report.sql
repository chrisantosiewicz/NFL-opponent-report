-- injury_report: for every team's game, the players on its most recent injury
-- report, how much each one has played, and whether he is new to the report.
-- Feeds the injury flag on the scouting page (sql/export/site_week.sql).
--
-- Which report: the game week's own report once the team has filed one
-- (Wednesday, or Monday/Tuesday before a Thursday game). Before that, e.g. on
-- the Tuesday run, it falls back to the team's latest earlier report, and
-- is_current_report is false so the page can say "last week's final report".
--
-- Who counts: a player with a game status (Out, Doubtful, Questionable) or who
-- did not practice fully. A full participant with no status is healthy.
--
-- Starter: averaged at least 50% of offensive or defensive snaps in the games
-- he played among the team's last 4 games before this one (definitions.md).
-- New: not on the team's report for the week before the report used.

CREATE OR REPLACE TABLE injury_report AS
WITH team_weeks AS (
    SELECT season, week, team, gameday
    FROM stg_team_games
),

report_weeks AS (
    SELECT t.season, t.week, t.team, t.gameday, max(i.week) AS report_week
    FROM team_weeks t
    JOIN (SELECT DISTINCT season, week, team FROM stg_injuries) i
      ON i.season = t.season AND i.team = t.team AND i.week <= t.week
    GROUP BY ALL
),

prior_weeks AS (
    SELECT r.season, r.week, r.team, max(i.week) AS prior_week
    FROM report_weeks r
    JOIN (SELECT DISTINCT season, week, team FROM stg_injuries) i
      ON i.season = r.season AND i.team = r.team AND i.week < r.report_week
    GROUP BY ALL
),

listed AS (
    SELECT r.season, r.week, r.team, r.gameday, r.report_week, p.prior_week,
           i.gsis_id, i.player_name, i.position, i.report_status, i.injury, i.practice
    FROM report_weeks r
    JOIN stg_injuries i
      ON i.season = r.season AND i.team = r.team AND i.week = r.report_week
    LEFT JOIN prior_weeks p
      ON p.season = r.season AND p.week = r.week AND p.team = r.team
    WHERE i.report_status IS NOT NULL OR i.practice IN ('DNP', 'Limited')
),

-- The team's last 4 completed games before this one (any season).
recent_games AS (
    SELECT t.season, t.week, t.team, g.game_id
    FROM team_weeks t
    JOIN stg_team_games g
      ON g.team = t.team AND g.is_complete AND g.gameday < t.gameday
    QUALIFY row_number() OVER (PARTITION BY t.season, t.week, t.team
                               ORDER BY g.gameday DESC) <= 4
),

player_ids AS (
    SELECT gsis_id, any_value(pfr_id) AS pfr_id
    FROM raw_players
    WHERE NULLIF(gsis_id, '') IS NOT NULL AND NULLIF(pfr_id, '') IS NOT NULL
    GROUP BY gsis_id
),

usage AS (
    SELECT l.season, l.week, l.team, l.gsis_id,
           count(s.game_id)                                        AS games_played,
           avg(greatest(s.offense_pct, s.defense_pct))             AS snap_share
    FROM listed l
    JOIN player_ids p ON p.gsis_id = l.gsis_id
    JOIN recent_games r ON r.season = l.season AND r.week = l.week AND r.team = l.team
    JOIN stg_snap_counts s ON s.game_id = r.game_id AND s.team = l.team AND s.pfr_id = p.pfr_id
    GROUP BY ALL
)

SELECT
    l.season, l.week, l.team, l.gameday,
    l.report_week,
    l.report_week = l.week                                         AS is_current_report,
    l.gsis_id, l.player_name, l.position,
    l.report_status, l.injury, l.practice,
    COALESCE(u.games_played, 0)                                    AS games_played,
    u.snap_share,
    COALESCE(u.snap_share >= 0.5, FALSE)                           AS is_starter,
    -- New to the report (no earlier report this season counts as new).
    NOT EXISTS (
        SELECT 1 FROM stg_injuries prev
        WHERE prev.season = l.season AND prev.team = l.team
          AND prev.week = l.prior_week AND prev.gsis_id = l.gsis_id
          AND (prev.report_status IS NOT NULL OR prev.practice IN ('DNP', 'Limited'))
    )                                                              AS is_new,
    CASE
        WHEN l.report_status IN ('Out', 'Doubtful')  THEN 'out'
        WHEN l.report_status = 'Questionable'        THEN 'questionable'
        ELSE 'practice'
    END                                                            AS flag
FROM listed l
LEFT JOIN usage u
  ON u.season = l.season AND u.week = l.week AND u.team = l.team AND u.gsis_id = l.gsis_id;
