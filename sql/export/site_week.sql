-- site_week: everything the live page needs for one report week, written as
-- one JSON object. It holds all 32 teams, so the page can scout anyone.
--
-- export_site_data() in R/pipeline.R fills {{season}}, {{week}}, {{focal_team}}
-- and {{path}}. It runs after the data tests, so it only sees tested tables.
-- Same leakage rule as the report: the week's snapshot only (games before it).

COPY (
    SELECT
        {{season}}                                        AS season,
        {{week}}                                          AS week,
        '{{focal_team}}'                                  AS focal_team,
        (SELECT opponent FROM stg_team_games
         WHERE season = {{season}} AND week = {{week}}
           AND team = '{{focal_team}}')                   AS focal_opponent,
        strftime(now() AT TIME ZONE 'UTC', '%Y-%m-%d %H:%M UTC') AS updated,

        (SELECT list({team: team, name: team_name, nick: team_nick,
                      color: color_primary, color2: color_secondary}
                     ORDER BY team)
         FROM dim_team)                                   AS teams,

        -- Both rows of every game this week (team's view of the matchup).
        (SELECT list({team: team, opponent: opponent, is_home: is_home,
                      gameday: strftime(gameday, '%Y-%m-%d')}
                     ORDER BY gameday, game_id, is_home DESC)
         FROM stg_team_games
         WHERE season = {{season}} AND week = {{week}})   AS games,

        -- Every team x situation x span x metric known before this week.
        (SELECT list({team: team, situation: situation, span: span, metric: metric,
                      value: round(value, 4), n: CAST(n AS INTEGER),
                      rank: league_rank, teams: league_teams,
                      pctile: round(pctile, 4), avg: round(league_avg, 4),
                      games: games, through_week: through_week})
         FROM tendency_ranks
         WHERE season = {{season}} AND as_of_week = {{week}}) AS current,

        -- Last season's full regular season, for context (and the Week 1 fallback).
        (SELECT list({team: team, situation: situation, metric: metric,
                      value: round(value, 4), n: CAST(n AS INTEGER),
                      rank: league_rank, teams: league_teams,
                      pctile: round(pctile, 4), avg: round(league_avg, 4)})
         FROM last_season_ranks
         WHERE season = {{season}} - 1)                   AS last_season,

        -- "What stands out" picks, same rule as the one-pager.
        (SELECT list({team: team, priority: priority, situation: situation, metric: metric}
                     ORDER BY team, priority)
         FROM three_things
         WHERE season = {{season}} AND as_of_week = {{week}}) AS things
) TO '{{path}}' (FORMAT JSON);
