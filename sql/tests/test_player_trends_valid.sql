-- Player trends add up: receptions never exceed targets, a player never has
-- more games than his team played before the week (no leakage), the last-4
-- count is at most 4, and each role keeps at most its picks (1 QB, 2 backs,
-- 4 receivers) per team and week.
SELECT season, as_of_week, team, player_id, 'receptions > targets' AS problem
FROM player_trends WHERE receptions > targets
UNION ALL
SELECT p.season, p.as_of_week, p.team, p.player_id, 'more games than the team played before the week'
FROM player_trends p
JOIN (SELECT season, as_of_week, team, COUNT(*) AS team_games FROM game_windows GROUP BY ALL) g
  USING (season, as_of_week, team)
WHERE p.games > g.team_games
UNION ALL
SELECT season, as_of_week, team, player_id, 'last4_games outside 0-4'
FROM player_trends WHERE last4_games NOT BETWEEN 0 AND 4 OR last4_games > games
UNION ALL
SELECT season, as_of_week, team, role, 'too many picks for a role'
FROM player_trends
GROUP BY season, as_of_week, team, role
HAVING COUNT(*) > CASE role WHEN 'passer' THEN 1 WHEN 'rusher' THEN 2 ELSE 4 END;
