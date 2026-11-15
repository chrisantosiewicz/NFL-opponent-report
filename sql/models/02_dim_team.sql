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
    team_color2     AS color_secondary,
    -- ESPN logo URL from nflverse, for the team picker on the home page.
    -- nflverse points CAR at ESPN's dark-background variant (500-dark/);
    -- the light one matches the other 31 on a white tile.
    replace(team_logo_espn, '/500-dark/', '/500/') AS logo_url
FROM raw_teams;
