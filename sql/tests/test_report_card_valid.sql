-- Report cards only grade completed games, every verdict is one of the
-- allowed values, each call appears once per team and week, and the
-- graded week's numbers come from games before it (the call text matches
-- the as-of draft notes: the hot spot's area is named in that week's notes),
-- and a locked call keeps the text it was locked with.
SELECT season, week, team, CAST(call_no AS VARCHAR) AS what, 'bad verdict' AS problem
FROM report_card
WHERE verdict NOT IN ('Hit', 'Miss', 'Mixed', 'Called it', 'Held', 'Didn''t come up', 'No real impact')
   OR (kind = 'tendency' AND verdict IN ('Held', 'Called it'))
   OR (side = 'offense' AND verdict IN ('Held', 'Called it'))
   OR (verdict = 'No real impact' AND call_no NOT IN (10, 11, 12, 14))   -- net-points calls only
UNION ALL
SELECT season, week, team, CAST(call_no AS VARCHAR), 'duplicate call'
FROM report_card GROUP BY ALL HAVING COUNT(*) > 1
UNION ALL
SELECT r.season, r.week, r.team, 'game', 'graded a game that is not complete'
FROM (SELECT DISTINCT season, week, team FROM report_card) r
JOIN stg_team_games g ON g.season = r.season AND g.week = r.week AND g.team = r.team
WHERE NOT g.is_complete
UNION ALL
-- (locked calls were checked against that week's notes when they were written)
SELECT r.season, r.week, r.team, '8', 'hot spot not in that week''s notes'
FROM report_card r
JOIN report_card_pregame c ON c.season = r.season AND c.week = r.week AND c.team = r.team AND c.call_no = 8
WHERE r.call_no = 8 AND NOT c.locked
  AND NOT EXISTS (SELECT 1 FROM draft_notes d WHERE d.season = r.season AND d.week = r.week AND d.team = r.team
                  AND d.text LIKE '%' || note_area(c.p_bucket, c.p_bucket2) || '%')
UNION ALL
-- Locks: one row per game, offense and call, and a locked call is graded with
-- the text it was locked with.
SELECT season, week, team, CAST(call_no AS VARCHAR), 'duplicate locked call'
FROM raw_report_card_locks GROUP BY season, week, team, game_id, call_no HAVING COUNT(*) > 1
UNION ALL
SELECT r.season, r.week, r.team, CAST(r.call_no AS VARCHAR), 'graded text differs from the lock'
FROM report_card r
JOIN raw_report_card_locks l ON l.season = r.season AND l.week = r.week AND l.team = r.team AND l.call_no = r.call_no
WHERE r.said <> l.said
UNION ALL
SELECT season, week, team, CAST(call_no AS VARCHAR), text
FROM (SELECT *, said || ' | ' || happened AS text FROM report_card)
WHERE regexp_matches(text, '\(\s*of|of\s*\)|  |\(\)| ,|NaN|^\s|\s$')
UNION ALL
-- Week 1 is graded too (scouted from last season) whenever last season is loaded.
SELECT g.season, g.week, g.team, 'week 1', 'week 1 not graded'
FROM stg_team_games g
WHERE g.week = 1 AND g.is_complete AND g.game_type = 'REG'
  AND EXISTS (SELECT 1 FROM tendency_ranks t WHERE t.season = g.season - 1)
  AND NOT EXISTS (SELECT 1 FROM report_card r WHERE r.season = g.season AND r.week = 1 AND r.team = g.team);
