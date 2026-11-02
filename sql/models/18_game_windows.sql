-- game_windows: for each report week, which of each team's completed games
-- count as "season to date" and which as "last 4". One row per season x
-- as_of_week x team x game. Same leakage rule as tendency_snapshot: only
-- games from weeks before the report's week (test_game_windows_no_leakage.sql).
--
-- The as-of weeks come from the schedule, so a team on a bye still gets a
-- window, and last 4 counts games, not weeks (a bye is skipped).

CREATE OR REPLACE TABLE game_windows AS
WITH as_of AS (
    SELECT DISTINCT season, week AS as_of_week FROM stg_team_games
)

SELECT
    a.season,
    a.as_of_week,
    g.team,
    g.game_id,
    g.week,
    ROW_NUMBER() OVER (PARTITION BY a.season, a.as_of_week, g.team ORDER BY g.week DESC) <= 4 AS in_last4
FROM as_of a
JOIN stg_team_games g
  ON g.season = a.season
 AND g.week   < a.as_of_week
WHERE g.is_complete;
