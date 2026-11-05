-- team_game_tendencies: one row per offense x game x situation, holding COUNTS
-- and SUMS, not rates. Rates are computed later from summed counts, so a
-- 4-game rate weights each play equally instead of averaging 4 game rates.
--
-- Win-probability filter: neutral situations use only plays at 5-95% wp.
-- Two-minute and trailing-8+ are unfiltered (the filter would remove most of
-- their plays, and "what they do when desperate" is the point of those splits).

CREATE OR REPLACE TABLE team_game_tendencies AS
WITH plays_by_situation AS (
    -- A play can land in several situations (3rd-and-short in the red zone),
    -- so each situation is its own SELECT, stacked with UNION ALL.
    SELECT 'early_down'      AS situation, * FROM stg_plays WHERE is_early_down AND is_neutral_wp
    UNION ALL
    SELECT 'third_short'     AS situation, * FROM stg_plays WHERE third_down_distance = 'short'  AND is_neutral_wp
    UNION ALL
    SELECT 'third_medium'    AS situation, * FROM stg_plays WHERE third_down_distance = 'medium' AND is_neutral_wp
    UNION ALL
    SELECT 'third_long'      AS situation, * FROM stg_plays WHERE third_down_distance = 'long'   AND is_neutral_wp
    UNION ALL
    SELECT 'red_zone'        AS situation, * FROM stg_plays WHERE is_red_zone AND is_neutral_wp
    UNION ALL
    SELECT 'two_minute'      AS situation, * FROM stg_plays WHERE is_two_minute
    UNION ALL
    SELECT 'trailing_8plus'  AS situation, * FROM stg_plays WHERE is_trailing_8plus
    UNION ALL
    SELECT 'all_neutral'     AS situation, * FROM stg_plays WHERE is_neutral_wp
),

situation_totals AS (
    SELECT
        game_id,
        team,
        situation,
        COUNT(*)                                     AS plays,
        SUM(is_pass)                                 AS pass_plays,
        SUM(is_shotgun)                              AS shotgun_plays,
        COUNT(xpass)                                 AS xpass_plays,      -- plays the xpass model covers
        SUM(CASE WHEN xpass IS NOT NULL THEN is_pass END) AS xpass_pass_plays,
        SUM(xpass)                                   AS sum_xpass,
        SUM(epa)                                     AS sum_epa,
        SUM(CASE WHEN is_pass = 1 THEN epa END)      AS sum_pass_epa,
        SUM(CASE WHEN is_run  = 1 THEN epa END)      AS sum_run_epa,
        SUM(is_success)                              AS success_plays
    FROM plays_by_situation
    GROUP BY game_id, team, situation
),

-- Spine: every game a team played x every situation, so a game with zero
-- red-zone plays still counts as one of the "last 4 games" downstream.
team_games AS (
    SELECT DISTINCT game_id, season, season_type, week, team
    FROM stg_plays
),

situations AS (
    SELECT DISTINCT situation FROM plays_by_situation
)

SELECT
    g.season,
    g.season_type,
    g.week,
    g.game_id,
    g.team,
    s.situation,
    COALESCE(t.plays, 0)             AS plays,
    COALESCE(t.pass_plays, 0)        AS pass_plays,
    COALESCE(t.shotgun_plays, 0)     AS shotgun_plays,
    COALESCE(t.xpass_plays, 0)       AS xpass_plays,
    COALESCE(t.xpass_pass_plays, 0)  AS xpass_pass_plays,
    COALESCE(t.sum_xpass, 0)         AS sum_xpass,
    COALESCE(t.sum_epa, 0)           AS sum_epa,
    COALESCE(t.sum_pass_epa, 0)      AS sum_pass_epa,
    COALESCE(t.sum_run_epa, 0)       AS sum_run_epa,
    COALESCE(t.success_plays, 0)     AS success_plays
FROM team_games g
CROSS JOIN situations s
LEFT JOIN situation_totals t
       ON t.game_id   = g.game_id
      AND t.team      = g.team
      AND t.situation = s.situation;
