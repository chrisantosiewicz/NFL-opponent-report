-- From week 2 on, every as-of week has all 32 teams in every situation/span.
-- A missing team would silently change everyone else's league rank.
SELECT season, as_of_week, situation, span, COUNT(DISTINCT team) AS teams
FROM tendency_snapshot
GROUP BY season, as_of_week, situation, span
HAVING COUNT(DISTINCT team) <> 32;
