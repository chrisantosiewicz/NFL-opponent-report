-- team_alias: maps other sources' team codes (PFR, older nflverse files) to the
-- codes in dim_team. Every code in dim_team maps to itself, so a join through
-- this table never drops a team that already uses the right code. A code that
-- is in neither list fails tests/test_trades_teams_valid.sql.

CREATE OR REPLACE TABLE team_alias AS
SELECT team AS alias, team FROM dim_team
UNION ALL
SELECT alias, team
FROM (VALUES
    ('LAR', 'LA'), ('STL', 'LA'), ('RAM', 'LA'),
    ('OAK', 'LV'), ('LVR', 'LV'), ('RAI', 'LV'),
    ('SD',  'LAC'), ('SDG', 'LAC'),
    ('JAC', 'JAX'), ('WSH', 'WAS'),
    ('GNB', 'GB'), ('KAN', 'KC'), ('NWE', 'NE'), ('NOR', 'NO'),
    ('SFO', 'SF'), ('TAM', 'TB'), ('CRD', 'ARI'), ('HTX', 'HOU'),
    ('CLT', 'IND'), ('OTI', 'TEN'), ('RAV', 'BAL')
) AS v(alias, team)
WHERE alias NOT IN (SELECT team FROM dim_team);
