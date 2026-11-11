-- A team's pre-game Elo is exactly its rating after its previous game that
-- season (nothing from this game or later leaks in), and an unplayed game
-- has no post-game rating. One row per team per game.
WITH r AS (
    SELECT e.*, s.result,
           lag(e.elo_post) OVER (PARTITION BY e.team, e.season ORDER BY e.gameday, e.week) AS prev_post
    FROM elo_ratings e
    JOIN raw_schedules_history s USING (game_id)
)
SELECT 'pre <> previous post' AS problem, game_id, team FROM r
WHERE prev_post IS NOT NULL AND abs(elo_pre - prev_post) > 1e-9
UNION ALL
SELECT 'post before the game is played', game_id, team FROM r
WHERE result IS NULL AND elo_post IS NOT NULL
UNION ALL
SELECT 'duplicate team-game', game_id, team FROM elo_ratings
GROUP BY game_id, team HAVING count(*) > 1;
