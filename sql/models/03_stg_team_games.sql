-- stg_team_games: the schedule with one row per team per game (two rows per
-- game), so "who does CHI play next?" is a simple filter.

CREATE OR REPLACE TABLE stg_team_games AS
WITH games AS (
    SELECT
        game_id,
        season,
        week,
        game_type,
        CAST(gameday AS DATE) AS gameday,
        home_team,
        away_team,
        home_score,
        away_score,
        result IS NOT NULL    AS is_complete
    FROM raw_schedules
)

SELECT game_id, season, week, game_type, gameday,
       home_team AS team, away_team AS opponent, TRUE AS is_home,
       home_score AS team_score, away_score AS opponent_score, is_complete
FROM games

UNION ALL

SELECT game_id, season, week, game_type, gameday,
       away_team AS team, home_team AS opponent, FALSE AS is_home,
       away_score AS team_score, home_score AS opponent_score, is_complete
FROM games;
