-- Within each bucket_type the shares add to 1, every bucket is a known value,
-- and over the season span offense rows mirror defense rows across the league
-- (every located play counts once on each side; last-4 windows differ by team).
SELECT season, as_of_week, team, side, span, situation, play_type, bucket_type,
       'shares do not add to 1' AS problem
FROM play_direction
GROUP BY ALL
HAVING ABS(SUM(share) - 1) > 1e-9
UNION ALL
SELECT season, as_of_week, team, side, span, situation, play_type, bucket_type, 'unknown bucket'
FROM play_direction
WHERE NOT (
    (bucket_type = 'width' AND bucket IN ('inside', 'off_tackle', 'outside')) OR
    (bucket_type = 'side'  AND bucket IN ('left', 'middle', 'right')) OR
    (bucket_type = 'depth' AND bucket IN ('short', 'deep')) OR
    (bucket_type = 'lane'  AND bucket IN ('short_outside', 'short_middle', 'deep_outside', 'deep_middle')) OR
    (bucket_type = 'zone'  AND bucket IN ('short_left', 'short_middle', 'short_right',
                                          'deep_left', 'deep_middle', 'deep_right')))
UNION ALL
SELECT season, as_of_week, NULL, NULL, span, situation, play_type, bucket_type,
       'offense and defense totals differ'
FROM play_direction
WHERE span = 'season'
GROUP BY season, as_of_week, span, situation, play_type, bucket_type
HAVING SUM(plays) FILTER (WHERE side = 'offense') <> SUM(plays) FILTER (WHERE side = 'defense');
