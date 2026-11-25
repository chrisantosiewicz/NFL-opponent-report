-- pick_stars: W2's moneyline pick and its total pick for every game it has
-- run, for the Predictions tab. Two rows per game: market = 'moneyline' (the
-- team we think wins) and 'total' (over or under). Stars (1-5) say how likely
-- the pick is to hit. Rules and the tests behind them: _shared/definitions.md,
-- "Pick stars".
--
-- Moneyline: hit chance = the average of W2's win chance and the market's
-- (moneylines with the bookmaker's margin removed). W2 alone was less
-- accurate than the market in 2026 (Brier 0.230 vs 0.210); the average was in
-- between (0.216) and its bands held up: 60-67% won 71%, 67-75% won 76%.
-- Stars by hit chance: under 60% 1, 60-67% 2, 67-75% 3, 75-83% 4, 83%+ 5.
--
-- Total: points from W2's total vs the line, then stars = 1 + points (1 to 5):
--   gap      0..3  |W2 total - line|: under 6 = 0, 6-9 = 2, 9+ = 3. W2's
--                  2019-2024 out-of-fold totals hit 48-56% under 6 points
--                  off (no trend), 58.0% at 6+ (94-68), 12-5 at 9+.
--   support  0..1  wind or rain in the forecast backs an under (15+ mph
--                  wind: unders 54.3% in 2019-2024, 117 games).
--   risk    -1..0  an upcoming outdoor game with no forecast yet (games
--                  already played have no saved forecast, so no penalty), or
--                  an over in wind or rain.
-- hit_chance for a total is the backtest's rate for its gap band (shrunk
-- toward 50% for the small 9+ band): 51%, 57%, 62%.
--
-- Matchup reasons (shown, not scored): each team's offense and defense rank
-- in EPA per play this season before the game (defense 1 = allows the least).
-- In 2024-2026, points scored and allowed against the opponent did not beat
-- the total line (49% when furthest off), so they don't move the stars.
-- is_backfill: W2 was run after the fact (config/w2_backfill.csv); such rows
-- feed only the backfilled record in predictions-<season>.json.

CREATE OR REPLACE TABLE pick_stars AS
WITH g AS (
    SELECT p.season, p.week, p.gameday, p.game_id, p.home_team, p.away_team,
           p.total_line, p.home_moneyline, p.away_moneyline, p.market_home_win,
           w.w2_home_win, w.w2_total - p.total_line AS total_gap,
           w.w2_home_margin, w.w2_total, w.is_backfill, COALESCE(p.is_complete, FALSE) AS is_complete
    FROM game_predictions p
    JOIN w2_predictions w USING (game_id)
    WHERE p.total_line IS NOT NULL AND p.market_home_win IS NOT NULL
),

-- Season-to-date EPA per play before each week, offense and defense, ranked.
team_epa AS (
    SELECT w.season, w.week, t.team,
           sum(CASE WHEN t.side = 'off' THEN t.epa END) / nullif(sum(CASE WHEN t.side = 'off' THEN t.n END), 0) AS off_epa,
           sum(CASE WHEN t.side = 'def' THEN t.epa END) / nullif(sum(CASE WHEN t.side = 'def' THEN t.n END), 0) AS def_epa
    FROM (SELECT DISTINCT season, week FROM g) w
    JOIN (SELECT season, week, team, 'off' AS side, sum(epa) AS epa, count(*) AS n
          FROM stg_plays WHERE epa IS NOT NULL AND (is_pass OR is_run) AND season_type = 'REG' GROUP BY ALL
          UNION ALL
          SELECT season, week, opponent, 'def', sum(epa), count(*)
          FROM stg_plays WHERE epa IS NOT NULL AND (is_pass OR is_run) AND season_type = 'REG' GROUP BY ALL) t
      ON t.season = w.season AND t.week < w.week
    GROUP BY ALL
),
ranks AS (
    SELECT season, week, team,
           rank() OVER (PARTITION BY season, week ORDER BY off_epa DESC) AS off_rank,
           rank() OVER (PARTITION BY season, week ORDER BY def_epa ASC)  AS def_rank
    FROM team_epa
),

picks AS (
    SELECT season, week, gameday, game_id, home_team, away_team, 'moneyline' AS market,
           CASE WHEN ch >= 0.5 THEN home_team ELSE away_team END AS pick_team,
           NULL::VARCHAR AS pick_total,
           CAST(CASE WHEN ch >= 0.5 THEN home_moneyline ELSE away_moneyline END AS DOUBLE) AS pick_line,
           greatest(ch, 1 - ch) AS hit_chance,
           CASE WHEN ch >= 0.5 THEN w2_home_win ELSE 1 - w2_home_win END AS w2_chance,
           CASE WHEN ch >= 0.5 THEN market_home_win ELSE 1 - market_home_win END AS market_chance,
           NULL::DOUBLE AS gap, w2_home_margin, w2_total, is_backfill, is_complete
    FROM (SELECT *, (w2_home_win + market_home_win) / 2 AS ch FROM g)
    UNION ALL
    SELECT season, week, gameday, game_id, home_team, away_team, 'total',
           NULL, CASE WHEN total_gap >= 0 THEN 'over' ELSE 'under' END,
           total_line, NULL, NULL, NULL,
           abs(total_gap), w2_home_margin, w2_total, is_backfill, is_complete
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
        CASE WHEN market = 'total' THEN CASE WHEN gap < 6 THEN 0 WHEN gap < 9 THEN 2 ELSE 3 END END AS gap_pts,
        (market = 'total' AND pick_total = 'under' AND COALESCE(wx.is_windy OR wx.is_wet, FALSE)) AS s_weather,
        (market = 'total' AND NOT p.is_complete AND wx.game_id IS NOT NULL AND NOT wx.is_neutral AND wx.temp_f IS NULL) AS r_no_forecast,
        (market = 'total' AND pick_total = 'over' AND COALESCE(wx.is_windy OR wx.is_wet, FALSE))   AS r_weather,
        (market = 'moneyline' AND COALESCE(i.qb_out, FALSE))                                       AS r_qb,
        rh.off_rank AS home_off_rank, rh.def_rank AS home_def_rank,
        ra.off_rank AS away_off_rank, ra.def_rank AS away_def_rank
    FROM picks p
    LEFT JOIN game_weather wx ON wx.game_id = p.game_id
    LEFT JOIN inj i ON i.season = p.season AND i.week = p.week AND i.team = p.pick_team
    LEFT JOIN ranks rh ON rh.season = p.season AND rh.week = p.week AND rh.team = p.home_team
    LEFT JOIN ranks ra ON ra.season = p.season AND ra.week = p.week AND ra.team = p.away_team
),

scored AS (
    SELECT *,
        CASE WHEN market = 'total' THEN CAST(COALESCE(s_weather, FALSE) AS INTEGER) END AS support_pts,
        CASE WHEN market = 'total' THEN -least(CAST(COALESCE(r_no_forecast, FALSE) AS INTEGER)
                                               + CAST(COALESCE(r_weather, FALSE) AS INTEGER), 1) END AS risk_pts,
        CASE WHEN market = 'moneyline' THEN pick_team ELSE home_team END AS t1,
        CASE WHEN market = 'moneyline' THEN CASE WHEN pick_team = home_team THEN away_team ELSE home_team END ELSE away_team END AS t2
    FROM parts
),

final AS (
    SELECT *,
        CASE WHEN market = 'total' THEN gap_pts + support_pts + risk_pts END AS points,
        CASE WHEN market = 'moneyline' THEN
                 CASE WHEN round(hit_chance, 3) < 0.60 THEN 1 WHEN round(hit_chance, 3) < 0.67 THEN 2
                      WHEN round(hit_chance, 3) < 0.75 THEN 3 WHEN round(hit_chance, 3) < 0.83 THEN 4 ELSE 5 END
             ELSE least(greatest(1 + gap_pts + support_pts + risk_pts, 1), 5) END AS stars,
        CASE WHEN t1 = home_team THEN home_off_rank ELSE away_off_rank END AS t1_off, CASE WHEN t1 = home_team THEN home_def_rank ELSE away_def_rank END AS t1_def,
        CASE WHEN t2 = home_team THEN home_off_rank ELSE away_off_rank END AS t2_off, CASE WHEN t2 = home_team THEN home_def_rank ELSE away_def_rank END AS t2_def
    FROM scored
)

SELECT
    season, week, gameday, game_id, home_team, away_team, market, is_backfill,
    pick_team, pick_total, pick_line,
    CASE WHEN market = 'moneyline'
         THEN pick_team || ' to win' || COALESCE(' (' || CASE WHEN pick_line > 0 THEN '+' ELSE '' END || CAST(CAST(pick_line AS INTEGER) AS VARCHAR) || ')', '')
         ELSE CASE pick_total WHEN 'over' THEN 'Over ' ELSE 'Under ' END || CAST(pick_line AS VARCHAR) END AS pick_label,
    round(CASE WHEN market = 'moneyline' THEN hit_chance
               ELSE CASE WHEN gap < 6 THEN 0.51 WHEN gap < 9 THEN 0.57 ELSE 0.62 END END, 3) AS hit_chance,
    round(w2_chance, 3) AS w2_chance, round(market_chance, 3) AS market_chance,
    round(gap, 1) AS gap, w2_home_margin, w2_total,
    gap_pts, support_pts, risk_pts, points, stars,
    list_filter([
        CASE WHEN market = 'moneyline'
             THEN 'Wins about ' || CAST(round(100 * hit_chance) AS INTEGER) || '% (W2 ' || CAST(round(100 * w2_chance) AS INTEGER)
                  || '%, market ' || CAST(round(100 * market_chance) AS INTEGER) || '%)'
             ELSE 'W2 total ' || CAST(round(w2_total, 1) AS VARCHAR) || ' (' || CAST(round(gap, 1) AS VARCHAR) || ' off)' END,
        CASE WHEN market = 'moneyline' AND t1_off IS NOT NULL AND t2_def IS NOT NULL
             THEN t1 || ' offense ' || CAST(t1_off AS VARCHAR) || ' vs ' || t2 || ' defense ' || CAST(t2_def AS VARCHAR)
                  || '; ' || t1 || ' defense ' || CAST(t1_def AS VARCHAR) || ' vs ' || t2 || ' offense ' || CAST(t2_off AS VARCHAR)
             WHEN market = 'total' AND t1_off IS NOT NULL AND t2_off IS NOT NULL
             THEN 'Offenses ' || t1 || ' ' || CAST(t1_off AS VARCHAR) || ', ' || t2 || ' ' || CAST(t2_off AS VARCHAR)
                  || '; defenses ' || t1 || ' ' || CAST(t1_def AS VARCHAR) || ', ' || t2 || ' ' || CAST(t2_def AS VARCHAR) END,
        CASE WHEN r_qb THEN pick_team || ' starting QB out' END,
        CASE WHEN s_weather THEN 'Wind or rain' END,
        CASE WHEN r_no_forecast THEN 'No forecast yet' END,
        CASE WHEN r_weather THEN 'Over in wind or rain' END
    ], lambda x: x IS NOT NULL) AS reasons
FROM final;
