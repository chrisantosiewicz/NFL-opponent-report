-- Prop stars (40_prop_stars.sql): one row per game x player x market; each
-- part in its range, the points add up, the stars follow the cutoffs, and the
-- player is on one of the game's teams. Prop lines (config/prop_lines.csv)
-- name a scheduled game, a known market and a positive line, once each.
SELECT game_id, player, market, 'more than one row' AS problem
FROM prop_stars GROUP BY ALL HAVING count(*) > 1
UNION ALL
SELECT game_id, player, market, 'part out of range'
FROM prop_stars
WHERE gap_pts NOT BETWEEN 0 AND 4 OR agree_pts NOT BETWEEN -1 AND 1
   OR support_pts NOT BETWEEN 0 AND 2 OR risk_pts NOT BETWEEN -2 AND 0
   OR pick NOT IN ('over', 'under')
UNION ALL
SELECT game_id, player, market, 'points or stars wrong'
FROM prop_stars
WHERE points <> gap_pts + agree_pts + support_pts + risk_pts
   OR stars <> CASE WHEN points <= 1 THEN 1 WHEN points = 2 THEN 2 WHEN points <= 4 THEN 3
                    WHEN points <= 6 THEN 4 ELSE 5 END
   OR team NOT IN (home_team, away_team)
UNION ALL
SELECT l.game_id, l.player, l.market, 'bad prop line'
FROM raw_prop_lines l
LEFT JOIN raw_schedules s ON s.game_id = l.game_id
WHERE s.game_id IS NULL OR l.market NOT IN ('pass_yds', 'rush_yds', 'rec_yds', 'receptions')
   OR l.line IS NULL OR l.line <= 0
UNION ALL
SELECT game_id, player, market, 'prop line listed twice'
FROM raw_prop_lines GROUP BY ALL HAVING count(*) > 1;
