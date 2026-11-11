-- The spread and the moneylines name the same favorite (catches a flipped
-- spread_line sign: home_line is negative when the home team is favored).
SELECT game_id, home_line, home_moneyline, away_moneyline
FROM stg_market_lines
WHERE home_line IS NOT NULL AND home_moneyline IS NOT NULL
  AND abs(home_line) >= 3
  AND ((home_line < 0) <> (market_home_win > 0.5));
