-- site_predictions: the locked win-% calls for one season, with results and
-- grades, as one JSON object -> site/data/predictions-<season>.json.
--
-- export_predictions() in R/pipeline.R loads the existing file into
-- raw_prediction_locks, then fills {{season}}, {{week}}, {{run_date}},
-- {{updated}} and {{path}}. A game is locked the first time a run sees it in
-- the report week before its game day; a locked row is kept exactly as it was.
-- Grades (right / wrong, log loss for the model and the market) are worked out
-- fresh each run from the final score; ties are not graded.

COPY (
    WITH locks AS (
        SELECT * FROM raw_prediction_locks
        UNION ALL
        SELECT game_id, model_home_win, market_home_win, home_line, total_line,
               model_version, '{{updated}}' AS locked_at
        FROM game_predictions
        WHERE season = {{season}} AND week = {{week}}
          AND gameday >= DATE '{{run_date}}'
          AND game_id NOT IN (SELECT game_id FROM raw_prediction_locks)
    ),
    graded AS (
        SELECT
            m.week, l.game_id, CAST(m.gameday AS VARCHAR) AS gameday,
            m.home_team, m.away_team,
            round(l.model_home_win, 4) AS model_home_win,
            round(l.market_home_win, 4) AS market_home_win,
            l.home_line, l.total_line, l.model_version, l.locked_at,
            m.result,
            CASE WHEN m.result IS NULL OR m.result = 0 THEN NULL
                 ELSE (l.model_home_win > 0.5) = (m.result > 0) END AS model_correct,
            CASE WHEN m.result IS NULL OR m.result = 0 THEN NULL
                 ELSE round(-ln(CASE WHEN m.result > 0 THEN l.model_home_win ELSE 1 - l.model_home_win END), 4) END AS model_log_loss,
            CASE WHEN m.result IS NULL OR m.result = 0 OR l.market_home_win IS NULL THEN NULL
                 ELSE round(-ln(CASE WHEN m.result > 0 THEN l.market_home_win ELSE 1 - l.market_home_win END), 4) END AS market_log_loss
        FROM locks l
        JOIN stg_market_lines m USING (game_id)
        WHERE m.season = {{season}}
    )
    SELECT
        {{season}}                               AS season,
        '{{updated}}'                            AS updated,
        (SELECT model_version FROM elo_params)   AS model_version,
        'K 20, home field 32, +25 off a bye, one-third regression each season, ratings from 2017 (includes 2025). Rest adjustment not yet included.' AS model_settings,
        (SELECT list(g ORDER BY g.week DESC, g.gameday, g.game_id) FROM graded g) AS games
) TO '{{path}}' (FORMAT JSON);
