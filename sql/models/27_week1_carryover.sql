-- Week 1 carryover. Week 1 has no earlier games that season, so the notes and
-- the report card scout it from last season's full regular season instead.
--
-- with_week1(t) returns as-of table t plus a copy of its "after the regular
-- season" rows (as_of_week = last regular-season week + 1, so every regular-
-- season game and no playoff game) relabeled as next season's Week 1. The
-- tables themselves are not changed, so the live page's own Week 1 fallback
-- and the leakage tests are untouched; draft_notes, scout_picks and
-- report_card read through it. Week 1 rows are flagged (basis = 'last_season')
-- wherever they are shown.
--
-- coaching_changes: offseason staff changes typed into
-- config/coaching_changes_manual.csv, named in the Week 1 notes.

CREATE OR REPLACE MACRO with_week1(t) AS TABLE
    SELECT * FROM query_table(t)
    UNION ALL BY NAME
    SELECT * REPLACE (season + 1 AS season, 1 AS as_of_week)
    FROM query_table(t) q
    WHERE q.as_of_week = (SELECT MAX(s.week) + 1 FROM stg_team_games s
                          WHERE s.season = q.season AND s.game_type = 'REG');

CREATE OR REPLACE TABLE coaching_changes AS
SELECT CAST(season AS INTEGER) AS season, team, role, name, note
FROM read_csv('config/coaching_changes_manual.csv', comment = '#', header = true, delim = ',', quote = '"', auto_detect = false,
              columns = {'season': 'VARCHAR', 'team': 'VARCHAR', 'role': 'VARCHAR', 'name': 'VARCHAR', 'note': 'VARCHAR'})
WHERE season IS NOT NULL AND trim(season) <> '';
