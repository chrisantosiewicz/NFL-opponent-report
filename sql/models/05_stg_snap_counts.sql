-- stg_snap_counts: one row per player per game they played, with the share of
-- their team's offensive and defensive snaps. Keyed by PFR id, the same id the
-- trade feed uses. Source: raw_snap_counts (nflreadr::load_snap_counts).

CREATE OR REPLACE TABLE stg_snap_counts AS
SELECT
    s.game_id,
    CAST(s.season AS INTEGER)               AS season,
    CAST(s.week AS INTEGER)                 AS week,
    g.gameday,
    COALESCE(a.team, s.team)                AS team,
    s.pfr_player_id                         AS pfr_id,
    s.player                                AS player_name,
    s.position,
    COALESCE(TRY_CAST(s.offense_snaps AS INTEGER), 0) AS offense_snaps,
    COALESCE(TRY_CAST(s.offense_pct AS DOUBLE), 0)    AS offense_pct,
    COALESCE(TRY_CAST(s.defense_snaps AS INTEGER), 0) AS defense_snaps,
    COALESCE(TRY_CAST(s.defense_pct AS DOUBLE), 0)    AS defense_pct
FROM raw_snap_counts s
LEFT JOIN team_alias a ON a.alias = s.team
LEFT JOIN stg_team_games g ON g.game_id = s.game_id AND g.team = COALESCE(a.team, s.team)
WHERE COALESCE(TRY_CAST(s.offense_snaps AS INTEGER), 0)
    + COALESCE(TRY_CAST(s.defense_snaps AS INTEGER), 0) > 0;
