-- Every receiver's targets add up to the team's targets, and shares are 0-1.
SELECT season, as_of_week, team, span, situation,
       SUM(targets) AS summed, MAX(team_targets) AS team_targets
FROM receiver_targets
GROUP BY ALL
HAVING SUM(targets) <> MAX(team_targets)
    OR MIN(share) <= 0 OR MAX(share) > 1
    OR MAX(through_week) >= MAX(as_of_week);
