-- Pick stars (39_pick_stars.sql): every W2 game with lines has exactly one
-- spread and one total row. Spreads are unrated (no stars or points parts);
-- totals have each part in range and stars = 1 + points, at most 5. The pick
-- is one of the game's teams (spread) or over/under (total).
WITH expected AS (
    SELECT w.game_id FROM w2_predictions w
    JOIN game_predictions p USING (game_id)
    WHERE p.home_line IS NOT NULL AND p.total_line IS NOT NULL
)
SELECT e.game_id, m.market, 'missing or duplicated' AS problem
FROM expected e
CROSS JOIN (VALUES ('spread'), ('total')) m(market)
LEFT JOIN (SELECT game_id, market, count(*) AS n FROM pick_stars GROUP BY ALL) s
  ON s.game_id = e.game_id AND s.market = m.market
WHERE COALESCE(s.n, 0) <> 1
UNION ALL
SELECT game_id, market, 'spread should be unrated'
FROM pick_stars
WHERE market = 'spread' AND (stars IS NOT NULL OR gap_pts IS NOT NULL)
UNION ALL
SELECT game_id, market, 'total part out of range or stars wrong'
FROM pick_stars
WHERE market = 'total'
  AND (gap_pts NOT IN (0, 2, 3) OR support_pts NOT BETWEEN 0 AND 1 OR risk_pts NOT BETWEEN -1 AND 0
       OR points <> greatest(gap_pts + support_pts + risk_pts, 0)
       OR stars IS NULL OR stars <> least(1 + points, 5))
UNION ALL
SELECT game_id, market, 'pick not in game'
FROM pick_stars
WHERE (market = 'spread' AND (pick_team IS NULL OR pick_team NOT IN (home_team, away_team) OR pick_total IS NOT NULL))
   OR (market = 'total' AND (pick_total NOT IN ('over', 'under') OR pick_team IS NOT NULL))
   OR pick_line IS NULL OR pick_label IS NULL;
