-- Offense and defense yards mirror each other across the league, and each
-- team appears once per side and week.
SELECT season, as_of_week, NULL AS team, 'offense and defense totals differ' AS problem
FROM team_yards
GROUP BY season, as_of_week
HAVING SUM(rush_yards) FILTER (WHERE side = 'offense') <> SUM(rush_yards) FILTER (WHERE side = 'defense')
    OR SUM(pass_yards) FILTER (WHERE side = 'offense') <> SUM(pass_yards) FILTER (WHERE side = 'defense')
UNION ALL
SELECT season, as_of_week, team, 'duplicate row'
FROM team_yards
GROUP BY season, as_of_week, team, side
HAVING COUNT(*) > 1;
