-- One top receiver per team and week, and his last-4 share is a real share.
SELECT season, as_of_week, team, COUNT(*) AS n
FROM top_target
GROUP BY ALL
HAVING COUNT(*) > 1
UNION ALL
SELECT season, as_of_week, team, 1
FROM top_target
WHERE share_last4 < 0 OR share_last4 > 1 OR share <= 0 OR share > 1
   OR targets_last4 > targets;
