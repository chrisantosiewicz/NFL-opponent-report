-- Every team in the trade and snap-count tables maps to a dim_team code.
-- An unmapped code would silently hide a trade from both teams' reports:
-- add it to models/04_team_alias.sql.
SELECT 'stg_trades.from_team' AS source, from_team AS team, player_name
FROM stg_trades
WHERE from_team NOT IN (SELECT team FROM dim_team)
UNION ALL
SELECT 'stg_trades.to_team', to_team, player_name
FROM stg_trades
WHERE to_team NOT IN (SELECT team FROM dim_team)
UNION ALL
SELECT DISTINCT 'stg_snap_counts.team', team, NULL
FROM stg_snap_counts
WHERE team NOT IN (SELECT team FROM dim_team);
