-- stg_plays: one row per real scrimmage play (pass or run), with the situation
-- flags every downstream model uses. Definitions live in the README; change them
-- here and nowhere else.
--
-- Source: raw_pbp (nflverse play-by-play, written by R/load_data.R)

CREATE OR REPLACE TABLE stg_plays AS
WITH scrimmage AS (
    SELECT *
    FROM raw_pbp
    WHERE play_type IN ('pass', 'run')  -- drops no_play (penalties), kicks, kneels, spikes
      AND down IS NOT NULL              -- drops two-point conversions
      AND posteam IS NOT NULL
)

SELECT
    game_id,
    play_id,
    season,
    season_type,
    week,
    posteam                        AS team,
    defteam                        AS opponent,

    -- nflverse "pass" = dropback: sacks and scrambles count as passes,
    -- which matches how xpass (expected dropback rate) is defined.
    CAST(pass AS INTEGER)          AS is_pass,
    1 - CAST(pass AS INTEGER)      AS is_run,
    CAST(shotgun AS INTEGER)       AS is_shotgun,
    CAST(no_huddle AS INTEGER)     AS is_no_huddle,

    down,
    ydstogo,
    yardline_100,
    half_seconds_remaining,
    score_differential,
    wp,
    xpass,
    epa,
    CAST(success AS INTEGER)       AS is_success,

    -- Situation flags
    down IN (1, 2)                 AS is_early_down,
    CASE
        WHEN down <> 3     THEN NULL
        WHEN ydstogo <= 3  THEN 'short'
        WHEN ydstogo <= 6  THEN 'medium'
        ELSE                    'long'
    END                            AS third_down_distance,
    yardline_100 <= 20             AS is_red_zone,
    half_seconds_remaining <= 120  AS is_two_minute,
    score_differential <= -8       AS is_trailing_8plus,
    wp BETWEEN 0.05 AND 0.95       AS is_neutral_wp
FROM scrimmage;
