-- Records add up: wins + losses + ties = games, ATS and over/under results
-- add up to the games that had a line, and a split never has more games than
-- the whole window.
SELECT b.season, b.as_of_week, b.team, b.span, b.split
FROM betting_trends b
JOIN betting_trends a
  ON a.season = b.season AND a.as_of_week = b.as_of_week AND a.team = b.team
 AND a.span = b.span AND a.split = 'all'
WHERE b.su_wins + b.su_losses + b.su_ties <> b.games
   OR b.ats_wins + b.ats_losses + b.ats_pushes <> b.lined_games
   OR b.overs + b.unders + b.total_pushes <> b.lined_games
   OR b.games > a.games
   OR (b.span = 'last4' AND b.games > 4);
