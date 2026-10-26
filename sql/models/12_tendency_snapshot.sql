-- tendency_snapshot: what was KNOWN about each team before each week's games.
--
-- For every team, every scheduled week (as_of_week), and every situation/span,
-- take the team_rolling row from the team's most recent game with
-- week < as_of_week. That strict "<" is the leakage guard: a report for week N
-- never sees week N or later (tests/test_snapshot_no_leakage.sql checks it).
--
-- Week 1 of a season has no rows: nothing is known yet that season.

CREATE OR REPLACE TABLE tendency_snapshot AS
WITH as_of_weeks AS (
    SELECT DISTINCT season, week AS as_of_week
    FROM stg_team_games
),

candidates AS (
    SELECT
        w.season,
        w.as_of_week,
        r.team,
        r.situation,
        r.span,
        r.week AS through_week,
        r.games, r.plays, r.pass_plays, r.shotgun_plays, r.xpass_plays,
        r.xpass_pass_plays, r.sum_xpass, r.sum_epa, r.sum_pass_epa, r.sum_run_epa,
        ROW_NUMBER() OVER (
            PARTITION BY w.season, w.as_of_week, r.team, r.situation, r.span
            ORDER BY r.week DESC
        ) AS recency
    FROM as_of_weeks w
    JOIN team_rolling r
      ON r.season = w.season
     AND r.week   < w.as_of_week
)

SELECT
    season, as_of_week, team, situation, span, through_week,
    games, plays, pass_plays, shotgun_plays, xpass_plays,
    xpass_pass_plays, sum_xpass, sum_epa, sum_pass_epa, sum_run_epa
FROM candidates
WHERE recency = 1;
