-- Every win chance is a probability, and every game has the model's number.
SELECT game_id, model_home_win, market_home_win
FROM game_predictions
WHERE model_home_win IS NULL
   OR model_home_win NOT BETWEEN 0 AND 1
   OR (market_home_win IS NOT NULL AND market_home_win NOT BETWEEN 0 AND 1);
