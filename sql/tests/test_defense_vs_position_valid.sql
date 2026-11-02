-- Positions are WR / TE / RB only, one row each per defense and week, and
-- targets by position never exceed the defense's dropbacks faced.
SELECT season, as_of_week, defense, position, 'bad position or duplicate' AS problem
FROM defense_vs_position
GROUP BY ALL
HAVING position NOT IN ('WR', 'TE', 'RB') OR COUNT(*) > 1
UNION ALL
SELECT v.season, v.as_of_week, v.defense, 'all', 'more targets than dropbacks'
FROM (SELECT season, as_of_week, defense, SUM(targets) AS targets FROM defense_vs_position GROUP BY ALL) v
JOIN (SELECT w.season, w.as_of_week, w.team AS defense, SUM(p.is_pass) AS dropbacks
      FROM game_windows w JOIN stg_plays p ON p.game_id = w.game_id AND p.opponent = w.team
      GROUP BY ALL) d USING (season, as_of_week, defense)
WHERE v.targets > d.dropbacks;
