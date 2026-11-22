-- No trade after the season's trade deadline (config/trade_deadlines.csv).
-- A row here is a config/trades_manual.csv line dated after the deadline:
-- a typo, or a waiver claim/signing typed in as a trade. Fix or delete it;
-- weekly rosters already show post-deadline moves as 'waivers/FA'.
SELECT CAST(m.trade_date AS VARCHAR) AS trade_date, m.from_team, m.to_team, m.player_name, CAST(d.deadline AS VARCHAR) AS deadline
FROM raw_trades_manual m
JOIN raw_trade_deadlines d
  ON CAST(d.season AS INTEGER) = year(TRY_CAST(m.trade_date AS DATE))
WHERE TRY_CAST(m.trade_date AS DATE) > CAST(d.deadline AS DATE)
  AND month(TRY_CAST(m.trade_date AS DATE)) >= 9      -- in-season part of the year
UNION ALL
SELECT CAST(trade_date AS VARCHAR), from_team, to_team, player_name, CAST(NULL AS VARCHAR)
FROM stg_trades
WHERE move_type = 'trade'
  AND trade_date > (SELECT CAST(deadline AS DATE) FROM raw_trade_deadlines
                    WHERE CAST(season AS INTEGER) = stg_trades.season);
