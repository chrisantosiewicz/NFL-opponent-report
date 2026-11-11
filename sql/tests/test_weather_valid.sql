-- Game-day weather is well formed: indoor games are neutral and carry no
-- flags, forecast values are physically plausible, every game has a roof
-- class (a missing one means config/stadiums.csv lacks the stadium), and the
-- totals history has outdoor games to compare with.
SELECT game_id, 'indoor game flagged' AS problem
FROM game_weather
WHERE is_neutral AND (is_windy OR is_cold OR is_wet)

UNION ALL
SELECT game_id, 'forecast out of range'
FROM game_weather
WHERE temp_f NOT BETWEEN -40 AND 120
   OR wind_mph NOT BETWEEN 0 AND 100
   OR gust_mph < wind_mph
   OR precip_prob NOT BETWEEN 0 AND 100
   OR forecast_hours > 3

UNION ALL
SELECT game_id, 'no roof class (stadium missing from config/stadiums.csv)'
FROM game_weather
WHERE roof_class IS NULL
  AND season = (SELECT max(season) FROM game_weather)

UNION ALL
SELECT 'weather_history', 'no outdoor games in history'
WHERE NOT EXISTS (SELECT 1 FROM weather_history WHERE condition = 'all_outdoor' AND games > 0);
