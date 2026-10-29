-- Rates are between 0 and 1, and PROE between -1 and 1.
SELECT season, as_of_week, team, situation, span, metric, value
FROM tendency_ranks
WHERE (metric IN ('pass_rate', 'shotgun_rate') AND value NOT BETWEEN 0 AND 1)
   OR (metric = 'proe' AND value NOT BETWEEN -1 AND 1);
