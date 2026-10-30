-- trade_impact: for each week's report, every in-season trade known before
-- that week, with how much the player was used by the team he left and how
-- many games each team has played since. The report uses it to say which
-- tendency numbers were built with a roster that no longer exists.
--
-- One row per season x as_of_week x traded player.
--   Known by week N      = trade_date before the week's last game. The
--                          report keeps only trades before its own game
--                          (a Monday game sees a Thursday trade).
--   Usage and game counts use only completed games before week N, the same
--   leakage rule as tendency_snapshot (tests/test_trade_impact_no_leakage.sql).
--
-- is_key: the player was a regular for the team he left. Any one of
--   dropback_share >= 50%   (the starting QB)
--   target_share   >= 15%
--   carry_share    >= 30%
--   snap_pct       >= 60%   (offense or defense, average over his games there)
-- Players with no snaps or plays before the trade are never key.

CREATE OR REPLACE TABLE trade_impact AS
WITH week_bounds AS (
    SELECT season, week AS as_of_week, MAX(gameday) AS week_end
    FROM stg_team_games
    GROUP BY season, week
),

known AS (
    SELECT w.as_of_week, w.week_end, t.*,
           ROW_NUMBER() OVER (PARTITION BY w.season, w.as_of_week ORDER BY t.trade_id, t.player_name) AS move_no
    FROM stg_trades t
    JOIN week_bounds w ON w.season = t.season AND t.trade_date < w.week_end
),

played AS (
    -- Completed games before each as_of_week, per team.
    SELECT w.as_of_week, g.season, g.team, g.game_id, g.gameday
    FROM stg_team_games g
    JOIN week_bounds w ON w.season = g.season AND g.week < w.as_of_week
    WHERE g.is_complete
),

team_games AS (
    SELECT
        k.season, k.as_of_week, k.move_no,
        COUNT(DISTINCT CASE WHEN p.team = k.from_team THEN p.game_id END) AS from_games,
        COUNT(DISTINCT CASE WHEN p.team = k.from_team AND p.gameday > k.trade_date THEN p.game_id END) AS from_games_since,
        COUNT(DISTINCT CASE WHEN p.team = k.to_team THEN p.game_id END) AS to_games,
        COUNT(DISTINCT CASE WHEN p.team = k.to_team AND p.gameday > k.trade_date THEN p.game_id END) AS to_games_since
    FROM known k
    LEFT JOIN played p
      ON p.season = k.season AND p.as_of_week = k.as_of_week AND p.team IN (k.from_team, k.to_team)
    GROUP BY ALL
),

snaps AS (
    SELECT
        k.season, k.as_of_week, k.move_no,
        COUNT(CASE WHEN s.team = k.from_team AND s.gameday < k.trade_date THEN 1 END) AS games_before,
        AVG(CASE WHEN s.team = k.from_team AND s.gameday < k.trade_date THEN s.offense_pct END) AS off_snap_pct_before,
        AVG(CASE WHEN s.team = k.from_team AND s.gameday < k.trade_date THEN s.defense_pct END) AS def_snap_pct_before,
        COUNT(CASE WHEN s.team = k.to_team AND s.gameday > k.trade_date THEN 1 END) AS games_after,
        AVG(CASE WHEN s.team = k.to_team AND s.gameday > k.trade_date THEN GREATEST(s.offense_pct, s.defense_pct) END) AS snap_pct_after
    FROM known k
    LEFT JOIN stg_snap_counts s
      ON s.pfr_id = k.pfr_id
     AND s.season = k.season
     AND s.week < k.as_of_week
    GROUP BY ALL
),

usage AS (
    -- Share of the old team's plays in its games before the trade.
    SELECT
        k.season, k.as_of_week, k.move_no,
        SUM(p.is_pass)                                               AS team_dropbacks,
        SUM(CASE WHEN p.is_pass = 1 AND p.receiver_id IS NOT NULL THEN 1 ELSE 0 END) AS team_targets,
        SUM(p.is_run)                                                AS team_carries,
        SUM(CASE WHEN p.is_pass = 1 AND p.passer_id = k.gsis_id THEN 1 ELSE 0 END)   AS dropbacks,
        SUM(CASE WHEN p.is_pass = 1 AND p.receiver_id = k.gsis_id THEN 1 ELSE 0 END) AS targets,
        SUM(CASE WHEN p.is_run = 1 AND p.rusher_id = k.gsis_id THEN 1 ELSE 0 END)    AS carries
    FROM known k
    JOIN stg_team_games g
      ON g.season = k.season AND g.team = k.from_team
     AND g.week < k.as_of_week AND g.gameday < k.trade_date
    JOIN stg_plays p ON p.game_id = g.game_id AND p.team = k.from_team
    GROUP BY ALL
)

SELECT
    k.season,
    k.as_of_week,
    k.week_end,
    k.trade_id,
    k.trade_date,
    k.from_team,
    k.to_team,
    k.player_name,
    k.position,
    k.pfr_id,
    k.gsis_id,
    k.move_type,
    k.source,
    tg.from_games,
    tg.from_games_since,
    tg.to_games,
    tg.to_games_since,
    s.games_before,
    s.off_snap_pct_before,
    s.def_snap_pct_before,
    CASE WHEN COALESCE(s.def_snap_pct_before, 0) > COALESCE(s.off_snap_pct_before, 0)
         THEN 'defense' ELSE 'offense' END                         AS side,
    s.games_after,
    s.snap_pct_after,
    u.dropbacks,
    u.targets,
    u.carries,
    u.dropbacks * 1.0 / NULLIF(u.team_dropbacks, 0)                AS dropback_share,
    u.targets   * 1.0 / NULLIF(u.team_targets, 0)                  AS target_share,
    u.carries   * 1.0 / NULLIF(u.team_carries, 0)                  AS carry_share,
    COALESCE(
        u.dropbacks * 1.0 / NULLIF(u.team_dropbacks, 0) >= 0.50
     OR u.targets   * 1.0 / NULLIF(u.team_targets, 0)   >= 0.15
     OR u.carries   * 1.0 / NULLIF(u.team_carries, 0)   >= 0.30
     OR GREATEST(COALESCE(s.off_snap_pct_before, 0), COALESCE(s.def_snap_pct_before, 0)) >= 0.60,
        FALSE)                                                     AS is_key
FROM known k
LEFT JOIN team_games tg USING (season, as_of_week, move_no)
LEFT JOIN snaps s       USING (season, as_of_week, move_no)
LEFT JOIN usage u       USING (season, as_of_week, move_no);
