-- dim_team: the 32 current franchises. Every team abbreviation in the other
-- models must exist here (see tests/test_team_in_dim_team.sql).

CREATE OR REPLACE TABLE dim_team AS
SELECT
    team_abbr       AS team,
    team_name,
    team_nick,
    team_conf       AS conference,
    team_division   AS division,
    team_color      AS color_primary,
    team_color2     AS color_secondary
FROM raw_teams;
