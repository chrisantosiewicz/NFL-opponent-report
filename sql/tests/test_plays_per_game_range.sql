-- Scrimmage plays per game and per team-game fall in a sane range.
-- 2024-2025 observed: 99-158 per game, 30-91 per team-game. A game outside
-- 80-200 (or a team outside 25-110) usually means partial or duplicated data.
SELECT game_id, NULL AS team, COUNT(*) AS plays
FROM stg_plays
GROUP BY game_id
HAVING COUNT(*) NOT BETWEEN 80 AND 200
UNION ALL
SELECT game_id, team, COUNT(*)
FROM stg_plays
GROUP BY game_id, team
HAVING COUNT(*) NOT BETWEEN 25 AND 110;
