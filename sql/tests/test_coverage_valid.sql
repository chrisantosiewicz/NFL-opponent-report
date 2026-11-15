-- Coverage numbers stay in range: rates between 0 and 1, blitzes never exceed
-- charted dropbacks, one row per team and side per week, and a player's
-- targets split by blitz never exceed his targets in player_trends.
SELECT season, as_of_week, team, side, 'rate out of range or blitzes > dropbacks' AS problem
FROM coverage_team
WHERE blitz_rate NOT BETWEEN 0 AND 1 OR heavy_box_rate NOT BETWEEN 0 AND 1
   OR pa_rate NOT BETWEEN 0 AND 1 OR ly_man_rate NOT BETWEEN 0 AND 1 OR blitzes > dropbacks
UNION ALL
SELECT season, as_of_week, team, side, 'duplicate team and side'
FROM coverage_team GROUP BY season, as_of_week, team, side HAVING COUNT(*) > 1
UNION ALL
SELECT c.season, c.as_of_week, c.team, c.player_id, 'more blitz-split targets than targets'
FROM coverage_players c
JOIN (SELECT season, as_of_week, team, player_id, MAX(targets) AS targets FROM player_trends GROUP BY ALL) p
  USING (season, as_of_week, team, player_id)
WHERE c.blitz_targets + c.noblitz_targets > p.targets;
