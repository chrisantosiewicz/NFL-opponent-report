-- team_rolling: for each team-game, the running totals THROUGH that game, over
-- two spans:
--   season = season to date (all games so far this season, playoffs included)
--   last4  = the team's last 4 games played (ROWS counts games, so bye weeks
--            are skipped, not counted)
-- Output is long: one row per team x game x situation x span.

CREATE OR REPLACE TABLE team_rolling AS
WITH running AS (
    SELECT
        season,
        week,
        game_id,
        team,
        situation,

        COUNT(*)              OVER season_to_date AS season_games,
        SUM(plays)            OVER season_to_date AS season_plays,
        SUM(pass_plays)       OVER season_to_date AS season_pass_plays,
        SUM(shotgun_plays)    OVER season_to_date AS season_shotgun_plays,
        SUM(xpass_plays)      OVER season_to_date AS season_xpass_plays,
        SUM(xpass_pass_plays) OVER season_to_date AS season_xpass_pass_plays,
        SUM(sum_xpass)        OVER season_to_date AS season_sum_xpass,
        SUM(sum_epa)          OVER season_to_date AS season_sum_epa,
        SUM(sum_pass_epa)     OVER season_to_date AS season_sum_pass_epa,
        SUM(sum_run_epa)      OVER season_to_date AS season_sum_run_epa,

        COUNT(*)              OVER last_4_games   AS last4_games,
        SUM(plays)            OVER last_4_games   AS last4_plays,
        SUM(pass_plays)       OVER last_4_games   AS last4_pass_plays,
        SUM(shotgun_plays)    OVER last_4_games   AS last4_shotgun_plays,
        SUM(xpass_plays)      OVER last_4_games   AS last4_xpass_plays,
        SUM(xpass_pass_plays) OVER last_4_games   AS last4_xpass_pass_plays,
        SUM(sum_xpass)        OVER last_4_games   AS last4_sum_xpass,
        SUM(sum_epa)          OVER last_4_games   AS last4_sum_epa,
        SUM(sum_pass_epa)     OVER last_4_games   AS last4_sum_pass_epa,
        SUM(sum_run_epa)      OVER last_4_games   AS last4_sum_run_epa
    FROM team_game_tendencies
    WINDOW
        season_to_date AS (
            PARTITION BY team, season, situation
            ORDER BY week
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ),
        last_4_games AS (
            PARTITION BY team, season, situation
            ORDER BY week
            ROWS BETWEEN 3 PRECEDING AND CURRENT ROW
        )
)

-- Stack the two spans so every later model handles them the same way.
SELECT season, week, game_id, team, situation, 'season' AS span,
       season_games AS games, season_plays AS plays, season_pass_plays AS pass_plays,
       season_shotgun_plays AS shotgun_plays, season_xpass_plays AS xpass_plays,
       season_xpass_pass_plays AS xpass_pass_plays, season_sum_xpass AS sum_xpass,
       season_sum_epa AS sum_epa, season_sum_pass_epa AS sum_pass_epa,
       season_sum_run_epa AS sum_run_epa
FROM running

UNION ALL

SELECT season, week, game_id, team, situation, 'last4' AS span,
       last4_games, last4_plays, last4_pass_plays,
       last4_shotgun_plays, last4_xpass_plays,
       last4_xpass_pass_plays, last4_sum_xpass,
       last4_sum_epa, last4_sum_pass_epa,
       last4_sum_run_epa
FROM running;
