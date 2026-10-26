-- Each (game_id, play_id) appears once in stg_plays.
SELECT game_id, play_id, COUNT(*) AS copies
FROM stg_plays
GROUP BY game_id, play_id
HAVING COUNT(*) > 1;
