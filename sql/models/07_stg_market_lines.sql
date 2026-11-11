-- stg_market_lines: the betting market's numbers for every game, one row per
-- game, straight from nflverse schedules (no sportsbook API, nothing scraped).
--
-- nflverse's spread_line is positive when the HOME team is favored. Here it is
-- turned once into betting notation from the home side (home_line: favorite
-- negative, so CHI favored by 6.5 at home is -6.5). Every later model reads
-- home_line / team_line, never spread_line.
--
-- market_home_win: the moneylines' implied win chances with the bookmaker's
-- margin removed (each side's implied chance divided by their sum).
-- Lines for a game appear in the feed a week or so before it; until then they
-- are NULL. For finished games they are the feed's last (closing) numbers.

CREATE OR REPLACE TABLE stg_market_lines AS
WITH s AS (
    SELECT
        game_id,
        CAST(season AS INTEGER)          AS season,
        CAST(week AS INTEGER)            AS week,
        game_type,
        CAST(gameday AS DATE)            AS gameday,
        home_team,
        away_team,
        CAST(spread_line AS DOUBLE)      AS spread_line,
        CAST(total_line AS DOUBLE)       AS total_line,
        CAST(home_moneyline AS INTEGER)  AS home_moneyline,
        CAST(away_moneyline AS INTEGER)  AS away_moneyline,
        CAST(result AS INTEGER)          AS result,       -- home score minus away score
        CAST(total AS INTEGER)           AS total_points,
        result IS NOT NULL               AS is_complete
    FROM raw_schedules
),
implied AS (
    SELECT *,
        CASE WHEN home_moneyline < 0 THEN -home_moneyline / (100.0 - home_moneyline)
             WHEN home_moneyline > 0 THEN 100.0 / (home_moneyline + 100.0) END AS home_implied,
        CASE WHEN away_moneyline < 0 THEN -away_moneyline / (100.0 - away_moneyline)
             WHEN away_moneyline > 0 THEN 100.0 / (away_moneyline + 100.0) END AS away_implied
    FROM s
)

SELECT
    game_id, season, week, game_type, gameday, home_team, away_team,
    -spread_line                                   AS home_line,
    total_line,
    home_moneyline,
    away_moneyline,
    home_implied / (home_implied + away_implied)   AS market_home_win,
    result,
    total_points,
    is_complete
FROM implied;
