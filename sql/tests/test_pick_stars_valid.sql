-- Pick stars (39_pick_stars.sql): every W2 game with a total line and
-- moneylines has exactly one moneyline and one total row. Moneyline stars
-- follow the hit-chance bands; totals have each part in range and stars =
-- 1 + points, 1 to 5. The pick is one of the game's teams (moneyline) or
-- over/under (total), and the hit chance is at least 50%.
WITH expected AS (
    SELECT w.game_id FROM w2_predictions w
    JOIN game_predictions p USING (game_id)
    WHERE p.total_line IS NOT NULL AND p.market_home_win IS NOT NULL
)
SELECT e.game_id, m.market, 'missing or duplicated' AS problem
FROM expected e
CROSS JOIN (VALUES ('moneyline'), ('total')) m(market)
LEFT JOIN (SELECT game_id, market, count(*) AS n FROM pick_stars GROUP BY ALL) s
  ON s.game_id = e.game_id AND s.market = m.market
WHERE COALESCE(s.n, 0) <> 1
UNION ALL
SELECT game_id, market, 'moneyline stars off the hit-chance bands'
FROM pick_stars
WHERE market = 'moneyline'
  AND (stars IS NULL OR stars <> CASE WHEN hit_chance < 0.60 THEN 1 WHEN hit_chance < 0.67 THEN 2
                                      WHEN hit_chance < 0.75 THEN 3 WHEN hit_chance < 0.83 THEN 4 ELSE 5 END)
UNION ALL
SELECT game_id, market, 'total part out of range or stars wrong'
FROM pick_stars
WHERE market = 'total'
  AND (gap_pts NOT IN (0, 2, 3) OR support_pts NOT BETWEEN 0 AND 1 OR risk_pts NOT BETWEEN -1 AND 0
       OR points <> gap_pts + support_pts + risk_pts
       OR stars IS NULL OR stars <> least(greatest(1 + points, 1), 5))
UNION ALL
SELECT game_id, market, 'pick not in game'
FROM pick_stars
WHERE (market = 'moneyline' AND (pick_team IS NULL OR pick_team NOT IN (home_team, away_team) OR pick_total IS NOT NULL))
   OR (market = 'total' AND (pick_total NOT IN ('over', 'under') OR pick_team IS NOT NULL OR pick_line IS NULL))
   OR pick_label IS NULL OR hit_chance IS NULL OR hit_chance < 0.5 OR hit_chance > 1;
