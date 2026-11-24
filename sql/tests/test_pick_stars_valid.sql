-- Pick stars (39_pick_stars.sql): every W2 game with lines has exactly one
-- spread and one total row; each part is in its range, the points add up,
-- the stars follow the cutoffs, and the pick is one of the game's teams (or
-- over/under for a total).
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
SELECT game_id, market, 'part out of range'
FROM pick_stars
WHERE gap_pts NOT BETWEEN 0 AND (CASE market WHEN 'spread' THEN 4 ELSE 2 END)
   OR elo_pts NOT BETWEEN -1 AND 1 OR (market = 'total' AND elo_pts <> 0)
   OR support_pts NOT BETWEEN 0 AND 2
   OR risk_pts NOT BETWEEN -2 AND 0
UNION ALL
SELECT game_id, market, 'points or stars wrong'
FROM pick_stars
WHERE points <> gap_pts + elo_pts + support_pts + risk_pts
   OR stars <> CASE WHEN points <= 1 THEN 1 WHEN points = 2 THEN 2 WHEN points <= 4 THEN 3
                    WHEN points <= 6 THEN 4 ELSE 5 END
UNION ALL
SELECT game_id, market, 'pick not in game'
FROM pick_stars
WHERE (market = 'spread' AND (pick_team IS NULL OR pick_team NOT IN (home_team, away_team) OR pick_total IS NOT NULL))
   OR (market = 'total' AND (pick_total NOT IN ('over', 'under') OR pick_team IS NOT NULL))
   OR pick_line IS NULL OR pick_label IS NULL;
