-- No leakage: a snapshot for as_of_week N only uses games before week N.
SELECT season, as_of_week, team, situation, span, through_week
FROM tendency_snapshot
WHERE through_week >= as_of_week;
