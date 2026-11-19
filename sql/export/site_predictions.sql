-- site_predictions: the locked win-% calls for one season, with results and
-- grades, as one JSON object -> site/data/predictions-<season>.json.
--
-- export_predictions() in R/pipeline.R loads the existing file into
-- raw_prediction_locks, then fills {{season}}, {{week}}, {{run_date}},
-- {{updated}}, {{lock_before}} and {{path}}. A game is locked the first time a run sees
-- it in a published week before kickoff; a locked row is kept exactly as it was.
-- W2 (38_w2_predictions.sql) is locked the same way, on its own clock, in the
-- w2_* fields. Grades (right / wrong, log loss for each model and the market) are worked out
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
          -- Never lock a game that has kicked off ({{lock_before}} is now, US Eastern).
          AND game_id NOT IN (
              SELECT game_id FROM raw_schedules
              WHERE gametime IS NOT NULL
                AND strptime(CAST(gameday AS VARCHAR) || ' ' || left(CAST(gametime AS VARCHAR), 5), '%Y-%m-%d %H:%M')
                    <= strptime('{{lock_before}}', '%Y-%m-%d %H:%M'))
    ),
    -- W2's calls, locked the same way on their own clock (raw_w2_locks holds
    -- the ones already in the file).
    w2_locks AS (
        SELECT * FROM raw_w2_locks
        UNION ALL
        SELECT game_id, w2_home_win, w2_home_margin, w2_total, w2_fit_run_id, '{{updated}}' AS w2_locked_at
        FROM w2_predictions
        WHERE season = {{season}} AND week = {{week}}
          AND gameday >= DATE '{{run_date}}'
          AND game_id NOT IN (SELECT game_id FROM raw_w2_locks)
          AND game_id NOT IN (
              SELECT game_id FROM raw_schedules
              WHERE gametime IS NOT NULL
                AND strptime(CAST(gameday AS VARCHAR) || ' ' || left(CAST(gametime AS VARCHAR), 5), '%Y-%m-%d %H:%M')
                    <= strptime('{{lock_before}}', '%Y-%m-%d %H:%M'))
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
                 ELSE round(-ln(CASE WHEN m.result > 0 THEN l.market_home_win ELSE 1 - l.market_home_win END), 4) END AS market_log_loss,
            round(w.w2_home_win, 4) AS w2_home_win,
            round(w.w2_home_margin, 2) AS w2_home_margin,
            round(w.w2_total, 2) AS w2_total,
            w.w2_fit_run_id, w.w2_locked_at,
            CASE WHEN m.result IS NULL OR m.result = 0 OR w.w2_home_win IS NULL THEN NULL
                 ELSE (w.w2_home_win > 0.5) = (m.result > 0) END AS w2_correct,
            CASE WHEN m.result IS NULL OR m.result = 0 OR w.w2_home_win IS NULL THEN NULL
                 ELSE round(-ln(CASE WHEN m.result > 0 THEN w.w2_home_win ELSE 1 - w.w2_home_win END), 4) END AS w2_log_loss
        FROM locks l
        JOIN stg_market_lines m USING (game_id)
        LEFT JOIN w2_locks w USING (game_id)
        WHERE m.season = {{season}}
    )
    SELECT
        {{season}}                               AS season,
        '{{updated}}'                            AS updated,
        (SELECT model_version FROM elo_params)   AS model_version,
        'K 20, home field 32, +25 off a bye, one-third regression each season, ratings from 2017 (includes 2025). Rest adjustment not yet included.' AS model_settings,
        (SELECT list(g ORDER BY g.week DESC, g.gameday, g.game_id) FROM graded g) AS games
) TO '{{path}}' (FORMAT JSON);
