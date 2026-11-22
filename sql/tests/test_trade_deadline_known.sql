-- Every season the run loads has a trade deadline in config/trade_deadlines.csv,
-- or post-deadline moves can't be told from trades. Add the missing season.
SELECT DISTINCT g.season
FROM stg_team_games g
WHERE g.game_type = 'REG'
  AND g.season NOT IN (SELECT CAST(season AS INTEGER) FROM raw_trade_deadlines);
