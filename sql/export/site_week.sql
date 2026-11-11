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
        '{{updated}}'                                     AS updated,

        (SELECT list({team: team, name: team_name, nick: team_nick,
                      color: color_primary, color2: color_secondary}
                     ORDER BY team)
         FROM dim_team)                                   AS teams,

        -- Both rows of every game this week (team's view of the matchup).
        (SELECT list({team: team, opponent: opponent, is_home: is_home,
                      gameday: CAST(gameday AS VARCHAR)}
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

        -- Generated draft notes for every team's offense this week (30_draft_notes.sql).
        (SELECT list({team: team, line: line, kind: kind, text: text} ORDER BY team, line)
         FROM draft_notes
         WHERE season = {{season}} AND week = {{week}})   AS drafts,

        -- This week's betting lines and the model's win % (Predictions tab).
        -- Lines from nflverse schedules; home_line is from the home side,
        -- favorite negative. The model is Elo (33_game_predictions.sql).
        (SELECT list({game_id: game_id, home_team: home_team, away_team: away_team,
                      home_line: home_line, total_line: total_line,
                      home_moneyline: home_moneyline, away_moneyline: away_moneyline,
                      market_home_win: round(market_home_win, 4),
                      model_home_win: round(model_home_win, 4),
                      model_version: model_version}
                     ORDER BY gameday, game_id)
         FROM game_predictions
         WHERE season = {{season}} AND week = {{week}})   AS lines,

        -- Records against past closing lines, every team, both windows
        -- (34_betting_trends.sql). Games before this week only.
        (SELECT list({team: team, span: span, split: split, games: games,
                      su_wins: su_wins, su_losses: su_losses, su_ties: su_ties,
                      lined: lined_games,
                      ats_wins: ats_wins, ats_losses: ats_losses, ats_pushes: ats_pushes,
                      cover_margin: round(avg_cover_margin, 2), cover_rate: round(cover_rate, 4),
                      cover_rank: cover_rank,
                      overs: overs, unders: unders, total_pushes: total_pushes,
                      total_vs_line: round(avg_total_vs_line, 2), over_rate: round(over_rate, 4),
                      over_rank: over_rank, teams: league_teams})
         FROM betting_trends
         WHERE season = {{season}} AND as_of_week = {{week}}) AS betting,

        -- Injury report behind the scouting page's injury flag (35_injury_report.sql):
        -- each team's latest report for this game, starters first.
        (SELECT list({team: team, report_week: report_week, current: is_current_report,
                      player: player_name, position: position, status: report_status,
                      injury: injury, practice: practice, flag: flag,
                      snap_share: round(snap_share, 3), games: games_played,
                      starter: is_starter, new: is_new}
                     ORDER BY team, is_starter DESC,
                              CASE flag WHEN 'out' THEN 1 WHEN 'questionable' THEN 2 ELSE 3 END,
                              snap_share DESC NULLS LAST, player_name)
         FROM injury_report
         WHERE season = {{season}} AND week = {{week}})   AS injuries,

        -- Kickoff forecast per game, domes neutral (36_game_weather.sql).
        (SELECT list({game_id: game_id, home_team: home_team, roof: roof_class,
                      neutral: is_neutral, stadium: stadium,
                      kickoff_et: strftime(kickoff_et, '%Y-%m-%d %H:%M'),
                      temp_f: round(temp_f, 0), wind_mph: round(wind_mph, 0),
                      gust_mph: round(gust_mph, 0), precip_prob: round(precip_prob, 0),
                      fetched_at: fetched_at, windy: is_windy, cold: is_cold, wet: is_wet})
         FROM game_weather
         WHERE season = {{season}} AND week = {{week}})   AS weather,

        -- Past outdoor totals in the same conditions, for context next to the forecast.
        (SELECT list({condition: condition, games: games, unders: unders, overs: overs,
                      under_rate: round(under_rate, 4), total_vs_line: round(avg_total_vs_line, 2)})
         FROM weather_history)                            AS weather_history,

        -- "What stands out" picks, same rule as the one-pager.
        (SELECT list({team: team, priority: priority, situation: situation, metric: metric}
                     ORDER BY team, priority)
         FROM three_things
         WHERE season = {{season}} AND as_of_week = {{week}}) AS things
) TO '{{path}}' (FORMAT JSON);
