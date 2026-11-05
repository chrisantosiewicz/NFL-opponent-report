-- Every row in config/trades_manual.csv has a readable date, two different
-- teams and a player. A typo here would drop the trade without a word.
SELECT trade_date, from_team, to_team, player_name
FROM raw_trades_manual
WHERE TRY_CAST(trade_date AS DATE) IS NULL
   OR NULLIF(from_team, '') IS NULL
   OR NULLIF(to_team, '') IS NULL
   OR from_team = to_team
   OR NULLIF(player_name, '') IS NULL;
