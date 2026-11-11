-- Game-day weather is well formed: indoor games are neutral and carry no
-- flags, forecast values are physically plausible, every game has a roof
-- class (a missing one means config/stadiums.csv lacks the stadium), and the
-- totals history has outdoor games to compare with.
SELECT game_id, 'indoor game flagged' AS problem
FROM game_weather
WHERE is_neutral AND (is_windy OR is_cold OR is_wet)

UNION ALL
SELECT game_id, 'forecast out of range: ' || concat_ws(', ',
       CASE WHEN temp_f NOT BETWEEN -40 AND 120 THEN 'temp ' || temp_f END,
       CASE WHEN wind_mph NOT BETWEEN 0 AND 100 THEN 'wind ' || wind_mph END,
       CASE WHEN gust_mph NOT BETWEEN 0 AND 150 THEN 'gust ' || gust_mph END,
       CASE WHEN precip_prob NOT BETWEEN 0 AND 100 THEN 'precip ' || precip_prob END,
       CASE WHEN forecast_hours > 3 THEN 'hours ' || forecast_hours END)
FROM game_weather
WHERE temp_f NOT BETWEEN -40 AND 120
   OR wind_mph NOT BETWEEN 0 AND 100
   OR gust_mph NOT BETWEEN 0 AND 150
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
