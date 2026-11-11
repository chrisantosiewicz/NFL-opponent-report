-- elo_ratings: Chris's Elo v1 rebuilt in SQL, so the site can run it in the
-- Tuesday Action without his local betting repo. One row per team per game
-- with the team's rating BEFORE the game (and after it, once it's played).
--
-- Settings, from his live fit 20261007T173644Z-38ed5333 (Nov 10, 2026):
--   every team starts at 1500 in 2017; each new season pulls a rating
--   one-third of the way back to 1500; K = 20; home field +32 Elo (0 at a
--   neutral site); +25 Elo for a team coming off a bye (13+ days of rest).
-- Not rebuilt yet: his rest adjustment (formula not sent). Unlike his live
-- ratings, these include 2025 (his repo skips it to protect a final test).
-- So this is "Elo v1 (cloud)", to be checked against his numbers.
--
-- A rating only moves after a game is played, so a pre-game rating uses
-- only games before it (test_elo_no_leakage.sql).

CREATE OR REPLACE TABLE elo_params AS
SELECT
    'Elo v1 (cloud)'  AS model_version,
    2017              AS first_season,
    1500.0            AS mean_rating,
    1.0 / 3           AS season_regression,
    20.0              AS k,
    32.0              AS home_field,
    25.0              AS bye_bonus,
    13                AS bye_rest_days,
    0.0422            AS points_per_elo,   -- predicted margin = 0.0422 x Elo gap
    13.22             AS margin_sd;        -- spread of the margin around it

-- Standard normal CDF (Abramowitz & Stegun 7.1.26 erf, error under 1e-6);
-- DuckDB has no built-in.
CREATE OR REPLACE MACRO erf_t(z) AS 1.0 / (1.0 + 0.3275911 * z);
CREATE OR REPLACE MACRO erf_pos(z) AS
    1 - ((((1.061405429 * erf_t(z) - 1.453152027) * erf_t(z) + 1.421413741) * erf_t(z)
          - 0.284496736) * erf_t(z) + 0.254829592) * erf_t(z) * exp(-z * z);
CREATE OR REPLACE MACRO norm_cdf(x) AS 0.5 * (1 + sign(x) * erf_pos(abs(x) / sqrt(2)));

CREATE OR REPLACE TABLE elo_ratings AS
WITH RECURSIVE
p AS (FROM elo_params),
games AS (
    SELECT
        s.game_id,
        CAST(s.season AS INTEGER)               AS season,
        CAST(s.week AS INTEGER)                 AS week,
        CAST(s.gameday AS DATE)                 AS gameday,
        h.team                                  AS home_team,
        a.team                                  AS away_team,
        s.location = 'Neutral'                  AS neutral,
        COALESCE(CAST(s.home_rest AS INTEGER), 7) AS home_rest,
        COALESCE(CAST(s.away_rest AS INTEGER), 7) AS away_rest,
        CAST(s.result AS INTEGER)               AS result
    FROM raw_schedules_history s
    JOIN team_alias h ON h.alias = s.home_team
    JOIN team_alias a ON a.alias = s.away_team
    WHERE s.season >= (SELECT first_season FROM p)
),
-- Each team plays at most once a week, so a (season, week) is one step of the
-- recursion and every game in it uses the ratings from the step before.
steps AS (
    SELECT season, week, ROW_NUMBER() OVER (ORDER BY season, week) AS step
    FROM (SELECT DISTINCT season, week FROM games)
),
team_games AS (
    SELECT st.step, g.game_id, g.home_team AS team, TRUE AS is_home, g.neutral,
           g.home_rest >= (SELECT bye_rest_days FROM p) AS off_bye, g.result
    FROM games g JOIN steps st USING (season, week)
    UNION ALL
    SELECT st.step, g.game_id, g.away_team, FALSE, g.neutral,
           g.away_rest >= (SELECT bye_rest_days FROM p), -g.result
    FROM games g JOIN steps st USING (season, week)
),
elo(step, season, team, rating, game_id, pre, adj_pre, opp_adj_pre) AS (
    SELECT 0, (SELECT first_season FROM p), team, (SELECT mean_rating FROM p),
           NULL::VARCHAR, NULL::DOUBLE, NULL::DOUBLE, NULL::DOUBLE
    FROM dim_team

    UNION ALL

    SELECT step, season, team,
           -- post-game rating: K x (result - expected), expected from the
           -- adjusted gap (home field and bye included); unplayed games don't move it
           pre + CASE WHEN game_id IS NULL OR result IS NULL THEN 0
                      ELSE (SELECT k FROM p) * ((CASE WHEN result > 0 THEN 1.0 WHEN result < 0 THEN 0.0 ELSE 0.5 END)
                           - 1.0 / (1.0 + pow(10.0, -(adj_pre - opp_adj_pre) / 400.0))) END,
           game_id, pre, adj_pre, opp_adj_pre
    FROM (
        SELECT x.*,
               CASE WHEN game_id IS NULL THEN NULL
                    ELSE sum(adj_pre) OVER (PARTITION BY game_id) - adj_pre END AS opp_adj_pre
        FROM (
            SELECT st.step, st.season, e.team, tg.game_id, tg.result,
                   -- the rating going into this week, regressed at a new season
                   CASE WHEN st.season > e.season
                        THEN (SELECT mean_rating FROM p) + (e.rating - (SELECT mean_rating FROM p)) * (1 - (SELECT season_regression FROM p))
                        ELSE e.rating END AS pre,
                   CASE WHEN st.season > e.season
                        THEN (SELECT mean_rating FROM p) + (e.rating - (SELECT mean_rating FROM p)) * (1 - (SELECT season_regression FROM p))
                        ELSE e.rating END
                     + CASE WHEN tg.is_home AND NOT tg.neutral THEN (SELECT home_field FROM p) ELSE 0 END
                     + CASE WHEN tg.off_bye THEN (SELECT bye_bonus FROM p) ELSE 0 END AS adj_pre
            FROM elo e
            JOIN steps st ON st.step = e.step + 1
            LEFT JOIN team_games tg ON tg.step = st.step AND tg.team = e.team
        ) x
    ) y
)

SELECT
    g.season, g.week, g.gameday, e.game_id, e.team,
    e.team = g.home_team                AS is_home,
    CASE WHEN e.team = g.home_team THEN g.away_team ELSE g.home_team END AS opponent,
    e.pre                               AS elo_pre,
    e.adj_pre - e.opp_adj_pre           AS elo_gap,       -- adjusted, from this team's side
    CASE WHEN g.result IS NULL THEN NULL ELSE e.rating END AS elo_post
FROM elo e
JOIN games g ON g.game_id = e.game_id
WHERE e.game_id IS NOT NULL;
