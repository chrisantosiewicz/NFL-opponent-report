-- Every team with a game and a snapshot that week gets a draft with the
-- approach paragraphs, and no line has an unfilled number (NULL renders as
-- an empty string inside concat, which leaves "( of )" or "at  EPA").
SELECT g.season, g.week, g.team, 'missing draft' AS problem
FROM stg_team_games g
JOIN (SELECT DISTINCT season, as_of_week FROM tendency_ranks) s
  ON s.season = g.season AND s.as_of_week = g.week
LEFT JOIN (SELECT DISTINCT season, week, team FROM draft_notes WHERE kind = 'p') d
  ON d.season = g.season AND d.week = g.week AND d.team = g.team
WHERE d.team IS NULL
UNION ALL
SELECT season, week, team, text
FROM draft_notes
WHERE regexp_matches(text, '\(\s*of|of\s*\)|at\s+EPA|  |\(\)| ,|\s\.$|NaN|\s$|^\s|%\s*\(league\s*%');
