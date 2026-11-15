-- stg_charting: hand-charted detail for scrimmage plays, one row per play in
-- stg_plays that FTN or last season's participation data covers.
--
--   FTN charting (this season, within 48 hours of each game):
--     is_blitz       = 1+ blitzers (FTN n_blitzers > 0)
--     pass_rushers   = FTN n_pass_rushers
--     box            = defenders in the box at the snap (FTN n_defense_box)
--     is_heavy_box   = 8+ in the box
--     is_play_action = FTN play-action pass
--   Participation (last season only; FTN releases it after the postseason):
--     man_zone       = 'man' / 'zone' (defense_man_zone_type)
--     coverage       = shell, e.g. COVER_3, 2_MAN, COMBO (defense_coverage_type)
-- A failed feed loads as an empty table, so every column is cast here.
-- Source: FTN Data via nflverse.

CREATE OR REPLACE TABLE stg_charting AS
WITH ftn AS (
    SELECT CAST(nflverse_game_id AS VARCHAR)       AS game_id,
           CAST(nflverse_play_id AS INTEGER)       AS play_id,
           TRY_CAST(n_blitzers AS INTEGER)         AS n_blitzers,
           TRY_CAST(n_pass_rushers AS INTEGER)     AS pass_rushers,
           TRY_CAST(n_defense_box AS INTEGER)      AS box,
           TRY_CAST(is_play_action AS BOOLEAN)     AS is_play_action
    FROM raw_ftn_charting
),

part AS (
    SELECT CAST(nflverse_game_id AS VARCHAR)                AS game_id,
           CAST(play_id AS INTEGER)                         AS play_id,
           lower(CAST(defense_man_zone_type AS VARCHAR))    AS man_zone_raw,
           upper(CAST(defense_coverage_type AS VARCHAR))    AS coverage
    FROM raw_participation
)

SELECT
    p.game_id, p.play_id, p.season, p.week, p.team, p.opponent,
    f.n_blitzers IS NOT NULL                        AS has_ftn,
    CASE WHEN f.n_blitzers IS NULL THEN NULL WHEN f.n_blitzers > 0 THEN 1 ELSE 0 END AS is_blitz,
    f.pass_rushers,
    f.box,
    CASE WHEN f.box IS NULL THEN NULL WHEN f.box >= 8 THEN 1 ELSE 0 END AS is_heavy_box,
    CAST(f.is_play_action AS INTEGER)               AS is_play_action,
    CASE WHEN r.man_zone_raw LIKE '%man%'  THEN 'man'
         WHEN r.man_zone_raw LIKE '%zone%' THEN 'zone' END AS man_zone,
    NULLIF(r.coverage, '')                          AS coverage
FROM stg_plays p
LEFT JOIN ftn  f ON f.game_id = p.game_id AND f.play_id = p.play_id
LEFT JOIN part r ON r.game_id = p.game_id AND r.play_id = p.play_id
WHERE f.game_id IS NOT NULL OR r.game_id IS NOT NULL;
