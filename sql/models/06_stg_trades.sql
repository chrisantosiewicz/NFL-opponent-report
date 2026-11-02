-- stg_trades: one row per PLAYER who changed teams during the season, from
-- the season's first game on (Week 1 through the deadline; offseason trades
-- are not here, because none of this season's numbers came before them).
-- Draft picks are dropped: they don't change who is on the field.
--
-- Sources, best first:
--   raw_trades           nflverse trade feed (nflreadr::load_trades). It can
--                        lag by months, so it is not enough on its own.
--   raw_trades_manual    config/trades_manual.csv, typed in by hand. Dropped
--                        once the feed has the same player going to the same
--                        team within a week.
--   raw_rosters_weekly   the safety net: a player on one team's roster one
--                        week and another team's the next (53-man or reserve
--                        lists, not practice squads or cuts). Catches trades
--                        nobody typed in, and waiver claims. Dropped when a
--                        listed trade covers the same move within 3 weeks.
--                        Its date is the day after the old team's last game
--                        with him, since rosters don't say when he moved.
--
-- Player matching: the feed and rosters carry a PFR id. A manual row without
-- one is matched by name to that season's rosters and snap counts. The PFR id
-- then finds the gsis id (raw_players) used in play-by-play.

CREATE OR REPLACE TABLE stg_trades AS
WITH feed AS (
    SELECT
        'nflverse-' || CAST(trade_id AS VARCHAR) AS trade_id,
        TRY_CAST(trade_date AS DATE)             AS trade_date,
        gave                                     AS from_code,
        received                                 AS to_code,
        NULLIF(pfr_id, '')                       AS pfr_id,
        pfr_name                                 AS player_name,
        CAST(NULL AS VARCHAR)                    AS position,
        CAST(NULL AS VARCHAR)                    AS gsis_id,
        CAST(NULL AS VARCHAR)                    AS notes,
        'nflverse'                               AS source
    FROM raw_trades
    WHERE NULLIF(pfr_name, '') IS NOT NULL       -- player rows only, no picks
),

manual AS (
    SELECT
        'manual-' || CAST(ROW_NUMBER() OVER (ORDER BY trade_date, player_name) AS VARCHAR),
        TRY_CAST(trade_date AS DATE),
        from_team,
        to_team,
        NULLIF(pfr_id, ''),
        player_name,
        NULLIF(position, ''),
        CAST(NULL AS VARCHAR),
        notes,
        'manual'
    FROM raw_trades_manual
),

roster_weeks AS (
    SELECT
        CAST(r.season AS INTEGER) AS season,
        CAST(r.week AS INTEGER)   AS week,
        r.team, r.status, r.full_name, r.position,
        NULLIF(r.gsis_id, '') AS gsis_id, NULLIF(r.pfr_id, '') AS pfr_id,
        LAG(r.team)   OVER w AS prev_team,
        LAG(r.status) OVER w AS prev_status,
        LAG(CAST(r.week AS INTEGER)) OVER w AS prev_week
    FROM raw_rosters_weekly r
    WHERE r.game_type = 'REG' AND NULLIF(r.gsis_id, '') IS NOT NULL
    WINDOW w AS (PARTITION BY r.season, r.gsis_id ORDER BY CAST(r.week AS INTEGER))
),

roster AS (
    SELECT
        'roster-' || rw.gsis_id || '-' || CAST(rw.season AS VARCHAR) || '-' || CAST(rw.week AS VARCHAR),
        -- the day after the old team's last game with him (or the last game
        -- of that week, if the old team was on bye)
        COALESCE(g.gameday, wk.last_game) + INTERVAL 1 DAY,
        rw.prev_team,
        rw.team,
        rw.pfr_id,
        rw.full_name,
        rw.position,
        rw.gsis_id,
        'detected from weekly rosters',
        'roster'
    FROM roster_weeks rw
    LEFT JOIN stg_team_games g
      ON g.season = rw.season AND g.week = rw.prev_week AND g.team = rw.prev_team
    LEFT JOIN (SELECT season, week, MAX(gameday) AS last_game FROM stg_team_games GROUP BY ALL) wk
      ON wk.season = rw.season AND wk.week = rw.prev_week
    WHERE rw.prev_team IS NOT NULL
      AND rw.prev_team <> rw.team
      AND rw.prev_status NOT IN ('CUT', 'DEV')
      AND rw.status NOT IN ('CUT', 'DEV')
),

both_sources AS (
    SELECT
        t.trade_id, t.trade_date,
        COALESCE(a_from.team, t.from_code) AS from_team,
        COALESCE(a_to.team, t.to_code)   AS to_team,
        t.pfr_id, t.player_name, t.position, t.gsis_id, t.notes, t.source,
        -- "Marvin Harrison Jr." and "Marvin Harrison" are the same key
        trim(regexp_replace(regexp_replace(lower(t.player_name), '[^a-z ]', '', 'g'),
                            '\s+(jr|sr|ii|iii|iv|v)$', '')) AS name_key
    FROM (SELECT * FROM feed UNION ALL SELECT * FROM manual UNION ALL SELECT * FROM roster) t
    LEFT JOIN team_alias a_from ON a_from.alias = t.from_code
    LEFT JOIN team_alias a_to ON a_to.alias = t.to_code
),

deduped AS (
    SELECT b.*
    FROM both_sources b
    WHERE b.source = 'nflverse'
       OR (b.source = 'manual' AND NOT EXISTS (
            SELECT 1 FROM both_sources f
            WHERE f.source = 'nflverse'
              AND f.to_team = b.to_team
              AND (f.pfr_id = b.pfr_id OR f.name_key = b.name_key)
              AND abs(date_diff('day', f.trade_date, b.trade_date)) <= 7))
       OR (b.source = 'roster' AND NOT EXISTS (
            SELECT 1 FROM both_sources f
            WHERE f.source IN ('nflverse', 'manual')
              AND f.to_team = b.to_team
              AND (f.pfr_id = b.pfr_id OR f.name_key = b.name_key)
              AND abs(date_diff('day', f.trade_date, b.trade_date)) <= 21))
),

seasons AS (
    SELECT season, MIN(gameday) AS first_game
    FROM stg_team_games
    WHERE game_type = 'REG'
    GROUP BY season
),

in_season AS (
    -- The season whose first game is the latest one on or before the trade.
    SELECT d.*, s.season,
           ROW_NUMBER() OVER (PARTITION BY d.trade_id, d.name_key ORDER BY s.season DESC) AS pick
    FROM deduped d
    JOIN seasons s ON s.first_game <= d.trade_date
    WHERE d.trade_date <= s.first_game + INTERVAL 200 DAY  -- through the Super Bowl
),

name_lookup AS (
    -- Who wore which name for which team that season: weekly rosters (which
    -- include backups who never took a snap), then snap counts.
    SELECT DISTINCT CAST(season AS INTEGER) AS season, team,
           NULLIF(pfr_id, '') AS pfr_id, NULLIF(gsis_id, '') AS gsis_id, full_name AS player_name
    FROM raw_rosters_weekly
    WHERE NULLIF(pfr_id, '') IS NOT NULL OR NULLIF(gsis_id, '') IS NOT NULL
    UNION
    SELECT DISTINCT season, team, pfr_id, CAST(NULL AS VARCHAR), player_name
    FROM stg_snap_counts
),

name_keys AS (
    -- one row per name per team-season, with whichever ids any source had
    SELECT l.season, COALESCE(a.team, l.team) AS team_code,
           trim(regexp_replace(regexp_replace(lower(l.player_name), '[^a-z ]', '', 'g'),
                               '\s+(jr|sr|ii|iii|iv|v)$', '')) AS name_key,
           MAX(l.pfr_id) AS pfr_id, MAX(l.gsis_id) AS gsis_id
    FROM name_lookup l
    LEFT JOIN team_alias a ON a.alias = l.team
    GROUP BY ALL
),

matched AS (
    -- A row without ids is matched by name to someone on the old team that
    -- season, or failing that the new team.
    SELECT
        i.*,
        COALESCE(i.pfr_id, nk.pfr_id)   AS pfr_id_matched,
        COALESCE(i.gsis_id, nk.gsis_id) AS gsis_id_matched,
        ROW_NUMBER() OVER (
            PARTITION BY i.trade_id, i.name_key
            ORDER BY (nk.team_code = i.from_team) DESC, nk.pfr_id
        ) AS dup
    FROM in_season i
    LEFT JOIN name_keys nk
      ON i.pfr_id IS NULL
     AND nk.season = i.season
     AND nk.team_code IN (i.from_team, i.to_team)
     AND nk.name_key = i.name_key
    WHERE i.pick = 1
)

SELECT
    m.trade_id,
    m.season,
    m.trade_date,
    m.from_team,
    m.to_team,
    m.player_name,
    COALESCE(p.position, m.position) AS position,
    COALESCE(m.pfr_id_matched, pg.pfr_id) AS pfr_id,
    COALESCE(m.gsis_id_matched, p.gsis_id) AS gsis_id,
    CASE WHEN m.source = 'roster' THEN 'roster move' ELSE 'trade' END AS move_type,
    m.notes,
    m.source
FROM matched m
LEFT JOIN (
    SELECT pfr_id, gsis_id, position,
           ROW_NUMBER() OVER (PARTITION BY pfr_id ORDER BY gsis_id) AS r
    FROM raw_players
    WHERE NULLIF(pfr_id, '') IS NOT NULL
) p ON p.pfr_id = m.pfr_id_matched AND p.r = 1
LEFT JOIN (
    -- a roster row can have a gsis id but no PFR id
    SELECT gsis_id, MAX(NULLIF(pfr_id, '')) AS pfr_id
    FROM raw_players
    GROUP BY gsis_id
) pg ON pg.gsis_id = m.gsis_id_matched
WHERE m.dup = 1;
