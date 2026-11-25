-- w2_predictions: Chris's W2 model (his betting repo: M6 ridge plus rain and
-- wind, trained 2017-2024), one row per game, from config/w2_predictions.csv.
-- W2 is not rebuilt here: the laptop runs it after each weather sweep and
-- commits the CSV (_tools/w2_to_csv.py). Only games in the schedule are kept.
--
-- w2_home_line is the margin in betting notation from the home side (favorite
-- negative), like stg_market_lines.home_line. Shown next to Elo and the market
-- on the Predictions tab; W2's cover and over chances are not copied.

CREATE OR REPLACE TABLE w2_predictions AS
SELECT
    w.season, w.week, w.game_id, CAST(s.gameday AS DATE) AS gameday,
    s.home_team, s.away_team,
    w.w2_home_win,
    w.w2_home_margin,
    -w.w2_home_margin             AS w2_home_line,
    w.w2_total,
    w.fit_run_id                  AS w2_fit_run_id,
    w.run_at                      AS w2_run_at,
    'W2'                          AS w2_version,
    w.is_backfill
FROM (
    SELECT *, FALSE AS is_backfill FROM raw_w2_predictions
    UNION ALL
    -- config/w2_backfill.csv: weeks W2 never ran live (only for the backfilled
    -- star-pick record; a live row for the same game wins).
    SELECT *, TRUE FROM raw_w2_backfill
    WHERE game_id NOT IN (SELECT game_id FROM raw_w2_predictions)
) w
JOIN raw_schedules s ON s.game_id = w.game_id;
