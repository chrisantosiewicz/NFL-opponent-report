-- Freshness: every game with a final score has play-by-play by the day after
-- it was played. A game from yesterday or today may still be waiting (nflverse
-- posts play-by-play overnight): it is left out of the numbers and the live
-- page notes it, so a Tuesday run still publishes without Monday night's
-- game, and the Wednesday run picks it up. Anything older stops the run, so
-- the last good report stays up.
SELECT g.game_id, g.season, g.week, g.team, g.opponent, g.gameday
FROM stg_team_games g
WHERE g.awaiting_pbp
  AND g.is_home
  AND CAST(g.gameday AS DATE) < current_date - INTERVAL 1 DAY;
