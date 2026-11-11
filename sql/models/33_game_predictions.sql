-- game_predictions: one row per game with the model's win chance next to the
-- market's. Only win % is shown on the site: Chris's backtest (2019-2024)
-- found no signal in Elo's cover or over chances (49.1% ATS, 49.9% totals),
-- so neither is computed here, and no "edge" is claimed.
--
-- Win % follows his engine: predicted home margin = 0.0422 x adjusted Elo gap,
-- the final margin is a normal curve around it (sd 13.22) rounded to whole
-- points, and a tie counts half: P(margin > 0) + 1/2 P(margin = 0).

CREATE OR REPLACE TABLE game_predictions AS
WITH p AS (FROM elo_params),
h AS (
    SELECT e.*, (SELECT points_per_elo FROM p) * e.elo_gap AS pred_margin
    FROM elo_ratings e
    WHERE e.is_home
)

SELECT
    m.season, m.week, m.game_type, m.gameday, m.game_id,
    m.home_team, m.away_team,
    h.elo_pre                                   AS home_elo,
    h.pred_margin                               AS model_home_margin,
    1 - norm_cdf((0.5 - h.pred_margin) / (SELECT margin_sd FROM p))
      + 0.5 * (norm_cdf((0.5 - h.pred_margin) / (SELECT margin_sd FROM p))
               - norm_cdf((-0.5 - h.pred_margin) / (SELECT margin_sd FROM p))) AS model_home_win,
    m.market_home_win,
    m.home_line,
    m.total_line,
    m.home_moneyline,
    m.away_moneyline,
    m.result,
    m.is_complete,
    (SELECT model_version FROM p)               AS model_version
FROM stg_market_lines m
JOIN h USING (game_id);
