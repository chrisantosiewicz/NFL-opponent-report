-- pick_stars: a 1-5 star confidence score for W2's side and total on every
-- game it has run, for the Predictions tab. Two rows per game: market =
-- 'spread' (the side W2 likes against the line) and 'total' (over or under).
-- Rules and cutoffs: _shared/definitions.md, "Pick stars".
--
-- Points, then stars (<= 1 one star, 2 two, 3-4 three, 5-6 four, 7+ five):
--   gap      0..4  how far W2 is from the market. Spreads compare W2's margin
--                  stretched to the market's spread for the week's slate
--                  (W2's margins are compressed toward zero, so the raw gap
--                  would always take the big underdog). Totals use the raw
--                  gap and top out at 2: W2's totals bunch at 41-49.
--   elo     -1..1  spreads only: Elo's margin is 1+ point past the line the
--                  same way (+1) or the other way (-1). Elo never picks:
--                  Chris's backtest found no ATS signal in it.
--   support  0..2  +1 each, at most 2. Spread: the picked team's season cover
--                  rate is 25+ points better than the opponent's (4+ decided
--                  games each); its net yards per game (gained minus allowed)
--                  are 50+ better. Total: both teams went over (under) in 60%+
--                  of their games (4+ each); wind or rain backs an under; both
--                  offenses rank in the top (bottom) half in yards per game and
--                  both defenses in the top (bottom) half in yards allowed.
--   risk    -2..0  spread: the picked team's starting QB is out or doubtful
--                  (-2), or 2+ of its other starters are (-1). Total: an
--                  outdoor game with no forecast yet, or an over in wind or
--                  rain or with either starting QB out (-1 each). Floor -2.
--
-- Untested: W2 arrived in week 11. The stars are locked with W2's call in
-- predictions-<season>.json and graded by star level, so the cutoffs can be
-- checked once there are enough graded picks.

CREATE OR REPLACE TABLE pick_stars AS
WITH g AS (
    SELECT p.season, p.week, p.gameday, p.game_id, p.home_team, p.away_team,
           p.home_line, p.total_line,
           -p.home_line              AS market_margin,     -- home side, + = home favored
           p.model_home_margin       AS elo_margin,
           w.w2_home_margin          AS w2_margin,
           w.w2_total
    FROM game_predictions p
    JOIN w2_predictions w USING (game_id)
    WHERE p.home_line IS NOT NULL AND p.total_line IS NOT NULL
),

-- Stretch W2's margins to the market's spread, per week's slate. A slate of
-- fewer than 8 games, or one where W2 is already as spread out, is left as is.
slate AS (
    SELECT season, week, count(*) AS n,
           avg(market_margin) AS mkt_mean, stddev_pop(market_margin) AS mkt_sd,
           avg(w2_margin) AS w2_mean, stddev_pop(w2_margin) AS w2_sd
    FROM g GROUP BY ALL
),

scaled AS (
    SELECT g.*,
           CASE WHEN s.n >= 8 AND s.w2_sd > 0 THEN least(greatest(s.mkt_sd / s.w2_sd, 1.0), 2.0) ELSE 1.0 END AS stretch,
           s.mkt_mean, s.w2_mean
    FROM g JOIN slate s USING (season, week)
),

-- One row per game and market, with the pick.
base AS (
    SELECT season, week, gameday, game_id, home_team, away_team, 'spread' AS market,
           CASE WHEN stretch = 1.0 THEN w2_margin
                ELSE mkt_mean + (w2_margin - w2_mean) * stretch END - market_margin AS home_gap,
           elo_margin - market_margin AS elo_home_gap,
           home_line, total_line, w2_margin, w2_total, stretch
    FROM scaled
    UNION ALL
    SELECT season, week, gameday, game_id, home_team, away_team, 'total',
           w2_total - total_line, NULL,
           home_line, total_line, w2_margin, w2_total, stretch
    FROM scaled
),

picks AS (
    SELECT b.*,
           abs(home_gap) AS gap,
           CASE WHEN market = 'spread' THEN CASE WHEN home_gap >= 0 THEN home_team ELSE away_team END END AS pick_team,
           CASE WHEN market = 'spread' THEN CASE WHEN home_gap >= 0 THEN away_team ELSE home_team END END AS other_team,
           CASE WHEN market = 'total' THEN CASE WHEN home_gap >= 0 THEN 'over' ELSE 'under' END END AS pick_total,
           -- The number bet: the picked team's spread (favorite negative), or the total.
           CASE WHEN market = 'spread' THEN CASE WHEN home_gap >= 0 THEN home_line ELSE -home_line END
                ELSE total_line END AS pick_line,
           -- Elo against the line, from the picked side (+ = agrees).
           CASE WHEN market = 'spread' THEN elo_home_gap * sign(home_gap) END AS elo_edge
    FROM base b
),

-- Inputs from the other models, as of this week (games before it).
ats AS (
    SELECT season, as_of_week AS week, team, cover_rate, over_rate,
           ats_wins + ats_losses AS ats_decided, overs + unders AS ou_decided
    FROM betting_trends WHERE span = 'season' AND split = 'all'
),
yds AS (
    SELECT season, as_of_week AS week, team,
           max(rush_ypg + pass_ypg) FILTER (WHERE side = 'offense') AS off_ypg,
           max(rush_ypg + pass_ypg) FILTER (WHERE side = 'defense') AS def_ypg
    FROM team_yards GROUP BY ALL
),
yds_rank AS (   -- 1 = most yards gained (offense) / most allowed (defense)
    SELECT *, rank() OVER (PARTITION BY season, week ORDER BY off_ypg DESC) AS off_rank,
              rank() OVER (PARTITION BY season, week ORDER BY def_ypg DESC) AS def_rank,
              count(*) OVER (PARTITION BY season, week) AS teams
    FROM yds
),
inj AS (
    SELECT season, week, team,
           bool_or(position = 'QB')                       AS qb_out,
           count(*) FILTER (WHERE position <> 'QB')       AS other_starters_out
    FROM injury_report
    WHERE is_starter AND flag = 'out'
    GROUP BY ALL
),

parts AS (
    SELECT p.*,
        -- gap points
        CASE WHEN market = 'spread' THEN
                 CASE WHEN gap < 1.5 THEN 0 WHEN gap < 2.5 THEN 1 WHEN gap < 3.5 THEN 2 WHEN gap < 5 THEN 3 ELSE 4 END
             ELSE CASE WHEN gap < 3 THEN 0 WHEN gap < 6 THEN 1 ELSE 2 END END AS gap_pts,
        CASE WHEN market = 'spread' THEN
                 CASE WHEN elo_edge >= 1 THEN 1 WHEN elo_edge <= -1 THEN -1 ELSE 0 END
             ELSE 0 END AS elo_pts,

        -- support flags
        (market = 'spread' AND ap.ats_decided >= 4 AND ao.ats_decided >= 4
            AND ap.cover_rate - ao.cover_rate >= 0.25)                               AS s_ats,
        (market = 'spread' AND (yp.off_ypg - yp.def_ypg) - (yo.off_ypg - yo.def_ypg) >= 50) AS s_yards_side,
        (market = 'total' AND ah.ou_decided >= 4 AND aa.ou_decided >= 4
            AND ((pick_total = 'over'  AND ah.over_rate >= 0.6 AND aa.over_rate >= 0.6)
              OR (pick_total = 'under' AND ah.over_rate <= 0.4 AND aa.over_rate <= 0.4)))  AS s_ou,
        (market = 'total' AND pick_total = 'under' AND COALESCE(wx.is_windy OR wx.is_wet, FALSE)) AS s_weather,
        (market = 'total' AND
            ((pick_total = 'over'  AND yh.off_rank <= yh.teams / 2 AND ya.off_rank <= ya.teams / 2
                                   AND yh.def_rank <= yh.teams / 2 AND ya.def_rank <= ya.teams / 2)
          OR (pick_total = 'under' AND yh.off_rank >  yh.teams / 2 AND ya.off_rank >  ya.teams / 2
                                   AND yh.def_rank >  yh.teams / 2 AND ya.def_rank >  ya.teams / 2))) AS s_yards_total,

        -- risk flags
        (market = 'spread' AND COALESCE(ip.qb_out, FALSE))                             AS r_qb,
        (market = 'spread' AND NOT COALESCE(ip.qb_out, FALSE) AND COALESCE(ip.other_starters_out, 0) >= 2) AS r_starters,
        (market = 'total' AND wx.game_id IS NOT NULL AND NOT wx.is_neutral AND wx.temp_f IS NULL) AS r_no_forecast,
        (market = 'total' AND pick_total = 'over' AND COALESCE(wx.is_windy OR wx.is_wet, FALSE)) AS r_weather,
        (market = 'total' AND pick_total = 'over' AND (COALESCE(ih.qb_out, FALSE) OR COALESCE(ia.qb_out, FALSE)))  AS r_qb_total,

        ap.cover_rate AS pick_cover_rate, ao.cover_rate AS other_cover_rate,
        ah.over_rate AS home_over_rate, aa.over_rate AS away_over_rate,
        wx.wind_mph, wx.precip_prob
    FROM picks p
    LEFT JOIN ats ap ON ap.season = p.season AND ap.week = p.week AND ap.team = p.pick_team
    LEFT JOIN ats ao ON ao.season = p.season AND ao.week = p.week AND ao.team = p.other_team
    LEFT JOIN ats ah ON ah.season = p.season AND ah.week = p.week AND ah.team = p.home_team
    LEFT JOIN ats aa ON aa.season = p.season AND aa.week = p.week AND aa.team = p.away_team
    LEFT JOIN yds_rank yp ON yp.season = p.season AND yp.week = p.week AND yp.team = p.pick_team
    LEFT JOIN yds_rank yo ON yo.season = p.season AND yo.week = p.week AND yo.team = p.other_team
    LEFT JOIN yds_rank yh ON yh.season = p.season AND yh.week = p.week AND yh.team = p.home_team
    LEFT JOIN yds_rank ya ON ya.season = p.season AND ya.week = p.week AND ya.team = p.away_team
    LEFT JOIN inj ip ON ip.season = p.season AND ip.week = p.week AND ip.team = p.pick_team
    LEFT JOIN inj ih ON ih.season = p.season AND ih.week = p.week AND ih.team = p.home_team
    LEFT JOIN inj ia ON ia.season = p.season AND ia.week = p.week AND ia.team = p.away_team
    LEFT JOIN game_weather wx ON wx.game_id = p.game_id
),

scored AS (
    SELECT *,
        least(CAST(COALESCE(s_ats, FALSE) AS INTEGER) + CAST(COALESCE(s_yards_side, FALSE) AS INTEGER)
            + CAST(COALESCE(s_ou, FALSE) AS INTEGER) + CAST(COALESCE(s_weather, FALSE) AS INTEGER)
            + CAST(COALESCE(s_yards_total, FALSE) AS INTEGER), 2)                        AS support_pts,
        greatest(-(2 * CAST(COALESCE(r_qb, FALSE) AS INTEGER) + CAST(COALESCE(r_starters, FALSE) AS INTEGER)
                   + CAST(COALESCE(r_no_forecast, FALSE) AS INTEGER) + CAST(COALESCE(r_weather, FALSE) AS INTEGER)
                   + CAST(COALESCE(r_qb_total, FALSE) AS INTEGER)), -2)                  AS risk_pts
    FROM parts
)

SELECT
    season, week, gameday, game_id, home_team, away_team, market,
    pick_team, pick_total, pick_line,
    CASE WHEN market = 'spread'
         THEN pick_team || ' ' || CASE WHEN pick_line > 0 THEN '+' ELSE '' END
              || CASE WHEN pick_line = 0 THEN 'PK' ELSE CAST(pick_line AS VARCHAR) END
         ELSE CASE pick_total WHEN 'over' THEN 'Over ' ELSE 'Under ' END || CAST(pick_line AS VARCHAR) END AS pick_label,
    round(gap, 1) AS gap, round(stretch, 2) AS stretch,
    w2_margin, w2_total, round(elo_edge, 1) AS elo_edge,
    gap_pts, elo_pts, support_pts, risk_pts,
    gap_pts + elo_pts + support_pts + risk_pts AS points,
    CASE WHEN gap_pts + elo_pts + support_pts + risk_pts <= 1 THEN 1
         WHEN gap_pts + elo_pts + support_pts + risk_pts = 2 THEN 2
         WHEN gap_pts + elo_pts + support_pts + risk_pts <= 4 THEN 3
         WHEN gap_pts + elo_pts + support_pts + risk_pts <= 6 THEN 4
         ELSE 5 END AS stars,
    -- Short reasons for the page, in the order the points are added.
    list_filter([
        CASE WHEN market = 'spread' THEN 'W2 ' || CAST(round(gap, 1) AS VARCHAR) || ' pts off the line'
             ELSE 'W2 total ' || CAST(round(w2_total, 1) AS VARCHAR) || ' (' || CAST(round(gap, 1) AS VARCHAR) || ' off)' END,
        CASE WHEN elo_pts = 1 THEN 'Elo agrees' WHEN elo_pts = -1 THEN 'Elo disagrees' END,
        CASE WHEN s_ats THEN pick_team || ' covers more (' || CAST(round(100 * pick_cover_rate) AS INTEGER) || '% vs '
                             || CAST(round(100 * other_cover_rate) AS INTEGER) || '%)' END,
        CASE WHEN s_yards_side THEN pick_team || ' +50 net yards a game' END,
        CASE WHEN s_ou THEN 'Both teams ' || pick_total || ' 60%+' END,
        CASE WHEN s_weather THEN 'Wind or rain' END,
        CASE WHEN s_yards_total THEN 'Yards matchup' END,
        CASE WHEN r_qb THEN pick_team || ' QB out' END,
        CASE WHEN r_starters THEN pick_team || ' 2+ starters out' END,
        CASE WHEN r_no_forecast THEN 'No forecast yet' END,
        CASE WHEN r_weather THEN 'Over in wind or rain' END,
        CASE WHEN r_qb_total THEN 'Over with a starting QB out' END
    ], lambda x: x IS NOT NULL) AS reasons
FROM scored;
