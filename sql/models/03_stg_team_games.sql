-- stg_team_games: the schedule with one row per team per game (two rows per
-- game), so "who does CHI play next?" is a simple filter.
--
-- is_complete = the game has a final score AND its play-by-play is loaded.
-- A game with a score but no play-by-play yet (nflverse posts it overnight)
-- is awaiting_pbp: it is left out of every "games so far" window until the
-- play-by-play arrives, and the live page says so on both teams. The
-- freshness test only fails when a game has waited more than a day.

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
        result IS NOT NULL AND game_id IN (SELECT DISTINCT game_id FROM stg_plays)     AS is_complete,
        result IS NOT NULL AND game_id NOT IN (SELECT DISTINCT game_id FROM stg_plays) AS awaiting_pbp
    FROM raw_schedules
)

SELECT game_id, season, week, game_type, gameday,
       home_team AS team, away_team AS opponent, TRUE AS is_home,
       home_score AS team_score, away_score AS opponent_score, is_complete, awaiting_pbp
FROM games

UNION ALL

SELECT game_id, season, week, game_type, gameday,
       away_team AS team, home_team AS opponent, FALSE AS is_home,
       away_score AS team_score, home_score AS opponent_score, is_complete, awaiting_pbp
FROM games;
