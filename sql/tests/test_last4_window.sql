-- The last-4 span never covers more than 4 games, and never more than the
-- season span.
SELECT l.season, l.week, l.team, l.situation, l.games AS last4_games, s.games AS season_games
FROM team_rolling l
JOIN team_rolling s
  ON s.game_id = l.game_id AND s.team = l.team AND s.situation = l.situation
 AND s.span = 'season'
WHERE l.span = 'last4'
  AND (l.games > 4 OR l.games > s.games);
