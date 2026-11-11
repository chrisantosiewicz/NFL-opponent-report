-- stg_injuries: the official injury report, one row per player per team per
-- week. nflverse keeps the latest version of each week's report, so a midweek
-- run sees the practice reports filed so far and a Saturday run sees the final
-- game statuses (Out / Doubtful / Questionable, filed Friday for Sunday games).
-- Source: raw_injuries (nflreadr::load_injuries). If that feed fails, the
-- table is empty and the scouting page says the report is unavailable.

CREATE OR REPLACE TABLE stg_injuries AS
SELECT
    CAST(i.season AS INTEGER)                               AS season,
    CAST(i.week AS INTEGER)                                 AS week,
    i.game_type,
    COALESCE(a.team, i.team)                                AS team,
    i.gsis_id,
    i.full_name                                             AS player_name,
    i.position,
    -- Game status. Blank until the final report of the week.
    CASE WHEN trim(i.report_status) IN ('Out', 'Doubtful', 'Questionable')
         THEN trim(i.report_status) END                     AS report_status,
    COALESCE(NULLIF(trim(i.report_primary_injury), ''),
             NULLIF(trim(i.practice_primary_injury), ''))   AS injury,
    -- Latest practice day on the report.
    CASE trim(i.practice_status)
        WHEN 'Did Not Participate In Practice'   THEN 'DNP'
        WHEN 'Limited Participation in Practice' THEN 'Limited'
        WHEN 'Full Participation in Practice'    THEN 'Full'
    END                                                     AS practice
FROM raw_injuries i
LEFT JOIN team_alias a ON a.alias = i.team
WHERE NULLIF(trim(i.gsis_id), '') IS NOT NULL
  AND TRY_CAST(i.week AS INTEGER) IS NOT NULL
-- The feed occasionally lists a player twice in one team-week (e.g. 2024 week
-- 15). Keep one row, preferring the one with a game status.
QUALIFY row_number() OVER (
    PARTITION BY CAST(i.season AS INTEGER), CAST(i.week AS INTEGER), COALESCE(a.team, i.team), i.gsis_id
    ORDER BY (trim(i.report_status) IN ('Out', 'Doubtful', 'Questionable')) DESC NULLS LAST,
             trim(i.practice_status) NULLS LAST
) = 1;
