-- Opponent-adjusted defense numbers: every season-to-date row has them, and
-- last-4 rows don't; ranks run 1..teams; and the adjustment is centered, so
-- the play-weighted average of epa_vs_expected in each split is near zero
-- (a broken join would leave it far off).
SELECT season, as_of_week, defense, situation || '/' || play_type AS what, 'adjusted value missing or set on last4' AS problem
FROM defense_splits
WHERE (span = 'season' AND (epa_vs_expected IS NULL OR rank_allowed_adj IS NULL))
   OR (span = 'last4' AND (epa_vs_expected IS NOT NULL OR rank_allowed_adj IS NOT NULL))
UNION ALL
SELECT season, as_of_week, NULL, situation || '/' || play_type, 'adjusted rank out of range'
FROM defense_splits
WHERE span = 'season' AND (rank_allowed_adj < 1 OR rank_allowed_adj > teams)
UNION ALL
SELECT season, as_of_week, NULL, situation || '/' || play_type, 'adjustment not centered'
FROM defense_splits
WHERE span = 'season'
GROUP BY season, as_of_week, situation, play_type
HAVING abs(SUM(epa_vs_expected * plays) / SUM(plays)) > 0.05;
