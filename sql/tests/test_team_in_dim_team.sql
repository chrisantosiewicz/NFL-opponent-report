-- Every team and opponent in the play and schedule tables exists in dim_team.
-- Catches relocations/abbreviation changes (e.g. LA vs LAR) before they
-- silently drop a team from the ranks.
SELECT DISTINCT 'stg_plays.team' AS source, team
FROM stg_plays
WHERE team NOT IN (SELECT team FROM dim_team)
UNION ALL
SELECT DISTINCT 'stg_plays.opponent', opponent
FROM stg_plays
WHERE opponent NOT IN (SELECT team FROM dim_team)
UNION ALL
SELECT DISTINCT 'stg_team_games.team', team
FROM stg_team_games
WHERE team NOT IN (SELECT team FROM dim_team);
