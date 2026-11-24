-- pick_stars: W2's pick on the side and the total of every game it has run,
-- for the Predictions tab. Two rows per game: market = 'spread' (the side W2
-- likes against the line) and 'total' (over or under). Rules and the backtest
-- behind them: _shared/definitions.md, "Pick stars".
--
-- Only totals 6+ points off the line get stars (2-5). W2's out-of-fold predictions for 2019-2024
-- (1,557 games vs closing lines) covered 48.6-51.3% at every spread gap, so a
-- spread pick is shown as an unrated lean (stars NULL) and still graded; it
-- can earn stars once live results show an edge. Totals 6+ points off the
-- line went 94-68 (58.0%); under 6 points was a coin flip, so a total under
-- 6 points off is a "no play" lean (stars NULL), still graded.
--
-- Total points (6+ points off only), then stars = 1 + points, 2 to 5:
--   gap      2..3  |W2 total - line|: 6-9 = 2, 9+ = 3.
--   support  0..1  wind or rain in the forecast backs an under (15+ mph
--                  wind: unders 54.3% in 2019-2024, 117 games).
--   risk    -1..0  an upcoming outdoor game with no forecast yet (games
--                  already played have no saved forecast, so no penalty), or
--                  an over in wind or rain.
-- Spread reasons still name the gap and a starting QB out on the picked side
-- (picked sides with their QB out covered 40.4%, 2024-2026). is_backfill: W2
-- was run after the fact (config/w2_backfill.csv); such rows feed only the
-- backfilled record in predictions-<season>.json.

CREATE OR REPLACE TABLE pick_stars AS
WITH g AS (
    SELECT p.season, p.week, p.gameday, p.game_id, p.home_team, p.away_team,
           p.home_line, p.total_line,
           w.w2_home_margin + p.home_line AS home_gap,   -- W2 margin minus the market's (home side)
           w.w2_total - p.total_line      AS total_gap,
           w.w2_home_margin, w.w2_total, w.is_backfill, COALESCE(p.is_complete, FALSE) AS is_complete
    FROM game_predictions p
    JOIN w2_predictions w USING (game_id)
    WHERE p.home_line IS NOT NULL AND p.total_line IS NOT NULL
),

picks AS (
    SELECT season, week, gameday, game_id, home_team, away_team, 'spread' AS market,
           CASE WHEN home_gap >= 0 THEN home_team ELSE away_team END AS pick_team,
           NULL::VARCHAR AS pick_total,
           CASE WHEN home_gap >= 0 THEN home_line ELSE -home_line END AS pick_line,
           abs(home_gap) AS gap, w2_home_margin, w2_total, is_backfill, is_complete
    FROM g
    UNION ALL
    SELECT season, week, gameday, game_id, home_team, away_team, 'total',
           NULL, CASE WHEN total_gap >= 0 THEN 'over' ELSE 'under' END,
           total_line, abs(total_gap), w2_home_margin, w2_total, is_backfill, is_complete
    FROM g
),

inj AS (
    SELECT season, week, team, bool_or(position = 'QB') AS qb_out
    FROM injury_report
    WHERE is_starter AND flag = 'out'
    GROUP BY ALL
),

parts AS (
    SELECT p.*,
        CASE WHEN market = 'total' AND gap >= 6 THEN CASE WHEN gap < 9 THEN 2 ELSE 3 END END AS gap_pts,
        (market = 'total' AND gap >= 6 AND pick_total = 'under' AND COALESCE(wx.is_windy OR wx.is_wet, FALSE)) AS s_weather,
        (market = 'total' AND gap >= 6 AND NOT p.is_complete AND wx.game_id IS NOT NULL AND NOT wx.is_neutral AND wx.temp_f IS NULL)  AS r_no_forecast,
        (market = 'total' AND gap >= 6 AND pick_total = 'over' AND COALESCE(wx.is_windy OR wx.is_wet, FALSE))   AS r_weather,
        (market = 'spread' AND COALESCE(i.qb_out, FALSE))                                         AS r_qb
    FROM picks p
    LEFT JOIN game_weather wx ON wx.game_id = p.game_id
    LEFT JOIN inj i ON i.season = p.season AND i.week = p.week AND i.team = p.pick_team
),

scored AS (
    SELECT *,
        CASE WHEN gap_pts IS NOT NULL THEN CAST(COALESCE(s_weather, FALSE) AS INTEGER) END    AS support_pts,
        CASE WHEN gap_pts IS NOT NULL THEN -least(CAST(COALESCE(r_no_forecast, FALSE) AS INTEGER)
                                               + CAST(COALESCE(r_weather, FALSE) AS INTEGER), 1) END AS risk_pts
    FROM parts
)

SELECT
    season, week, gameday, game_id, home_team, away_team, market, is_backfill,
    pick_team, pick_total, pick_line,
    CASE WHEN market = 'spread'
         THEN pick_team || ' ' || CASE WHEN pick_line > 0 THEN '+' ELSE '' END
              || CASE WHEN pick_line = 0 THEN 'PK' ELSE CAST(pick_line AS VARCHAR) END
         ELSE CASE pick_total WHEN 'over' THEN 'Over ' ELSE 'Under ' END || CAST(pick_line AS VARCHAR) END AS pick_label,
    round(gap, 1) AS gap, w2_home_margin, w2_total,
    gap_pts, support_pts, risk_pts,
    gap_pts + support_pts + risk_pts                                      AS points,
    CASE WHEN gap_pts IS NOT NULL THEN least(1 + gap_pts + support_pts + risk_pts, 5) END AS stars,  -- NULL: unrated spread or no-play total
    list_filter([
        CASE WHEN market = 'spread' THEN 'W2 ' || CAST(round(gap, 1) AS VARCHAR) || ' pts off the line'
             ELSE 'W2 total ' || CAST(round(w2_total, 1) AS VARCHAR) || ' (' || CAST(round(gap, 1) AS VARCHAR) || ' off)' END,
        CASE WHEN r_qb THEN pick_team || ' starting QB out' END,
        CASE WHEN s_weather THEN 'Wind or rain' END,
        CASE WHEN r_no_forecast THEN 'No forecast yet' END,
        CASE WHEN r_weather THEN 'Over in wind or rain' END
    ], lambda x: x IS NOT NULL) AS reasons
FROM scored;
