-- W2 rows (config/w2_predictions.csv and config/w2_backfill.csv) match the schedule's game and teams,
-- hold one row per game, and every number is in range: win chance 0-1,
-- margin within 40 points, total 20-80.
SELECT w.game_id, 'not in schedule or teams differ' AS problem
FROM raw_w2_predictions w
LEFT JOIN raw_schedules s ON s.game_id = w.game_id
WHERE s.game_id IS NULL OR s.home_team <> w.home_team OR s.away_team <> w.away_team
UNION ALL
SELECT game_id, 'more than one row' FROM raw_w2_predictions GROUP BY game_id HAVING count(*) > 1
UNION ALL
SELECT b.game_id, 'backfill row not in schedule, teams differ, or duplicated'
FROM raw_w2_backfill b
LEFT JOIN raw_schedules s ON s.game_id = b.game_id
WHERE s.game_id IS NULL OR s.home_team <> b.home_team OR s.away_team <> b.away_team
   OR b.game_id IN (SELECT game_id FROM raw_w2_backfill GROUP BY game_id HAVING count(*) > 1)
UNION ALL
SELECT game_id, 'number out of range'
FROM w2_predictions
WHERE w2_home_win IS NULL OR w2_home_win NOT BETWEEN 0 AND 1
   OR w2_home_margin IS NULL OR abs(w2_home_margin) > 40
   OR w2_total IS NULL OR w2_total NOT BETWEEN 20 AND 80;
