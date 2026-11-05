-- Freshness: every game the schedule marks complete has play-by-play.
-- This is the test that fails on a Tuesday when nflverse hasn't published
-- Monday night's game yet. The pipeline then stops before rendering, so the
-- last good report stays up.
SELECT g.game_id, g.season, g.week, g.team, g.opponent
FROM stg_team_games g
WHERE g.is_complete
  AND g.is_home
  AND g.game_id NOT IN (SELECT DISTINCT game_id FROM stg_plays);
