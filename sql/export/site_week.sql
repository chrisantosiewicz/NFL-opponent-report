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
                      color: color_primary, color2: color_secondary,
                      conference: conference, division: division, logo: logo_url}
                     ORDER BY team)
         FROM dim_team)                                   AS teams,

        -- Both rows of every game this week (team's view of the matchup).
        (SELECT list({team: team, opponent: opponent, is_home: is_home,
                      gameday: CAST(gameday AS VARCHAR)}
                     ORDER BY gameday, game_id, is_home DESC)
         FROM stg_team_games
         WHERE season = {{season}} AND week = {{week}})   AS games,

        -- Games with a final score whose play-by-play isn't posted yet
        -- (03_stg_team_games.sql): left out of the numbers; the page says so.
        (SELECT list({team: team, opponent: opponent, week: week, season: season,
                      is_home: is_home, gameday: CAST(gameday AS VARCHAR)})
         FROM stg_team_games
         WHERE awaiting_pbp AND season = {{season}} AND week < {{week}}) AS awaiting,

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

        -- This week's betting lines and the models' win % (Predictions tab).
        -- Lines from nflverse schedules; home_line is from the home side,
        -- favorite negative. Elo is 33_game_predictions.sql; W2 (Chris's
        -- betting repo, 38_w2_predictions.sql) is null for a game it hasn't run.
        (SELECT list({game_id: p.game_id, home_team: p.home_team, away_team: p.away_team,
                      home_line: p.home_line, total_line: p.total_line,
                      home_moneyline: p.home_moneyline, away_moneyline: p.away_moneyline,
                      market_home_win: round(p.market_home_win, 4),
                      model_home_win: round(p.model_home_win, 4),
                      model_version: p.model_version,
                      w2_home_win: round(w.w2_home_win, 4),
                      w2_home_line: round(w.w2_home_line, 1),
                      w2_total: round(w.w2_total, 1),
                      w2_run_at: w.w2_run_at}
                     ORDER BY p.gameday, p.game_id)
         FROM game_predictions p
         LEFT JOIN w2_predictions w USING (game_id)
         WHERE p.season = {{season}} AND p.week = {{week}})   AS lines,

        -- 1-5 star score on W2's side and total for each game (39_pick_stars.sql).
        (SELECT list({game_id: game_id, market: market, pick_team: pick_team,
                      pick_total: pick_total, pick_line: pick_line, pick_label: pick_label,
                      gap: gap, gap_pts: gap_pts, elo_pts: elo_pts,
                      support_pts: support_pts, risk_pts: risk_pts,
                      points: points, stars: stars, reasons: reasons}
                     ORDER BY stars DESC, points DESC, gap DESC, game_id, market)
         FROM pick_stars
         WHERE season = {{season}} AND week = {{week}})   AS picks,

        -- 1-5 star score on each player prop line pulled this week (40_prop_stars.sql).
        (SELECT list({game_id: game_id, team: team, player: player, position: position,
                      market: market, line: line, books: books, fetched_at: fetched_at,
                      pick: pick, pick_label: pick_label, season_avg: season_avg,
                      last4_avg: last4_avg, projection: projection,
                      gap_pts: gap_pts, agree_pts: agree_pts, support_pts: support_pts,
                      risk_pts: risk_pts, points: points, stars: stars, reasons: reasons}
                     ORDER BY stars DESC, points DESC, gap_share DESC, game_id, player, market)
         FROM prop_stars
         WHERE season = {{season}} AND week = {{week}})   AS prop_picks,

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

        -- Attack view: where each offense runs and throws and where each
        -- defense gets hit (26_play_direction.sql), season to date, neutral
        -- downs. Run side and pass area are from the offense's view on both.
        (SELECT list({team: team, side: side, play_type: play_type, bucket_type: bucket_type,
                      bucket: bucket, plays: CAST(plays AS INTEGER), share: round(share, 4),
                      epa: round(epa_per_play, 3), ypp: round(yards_per_play, 2),
                      success: round(success_rate, 3), rank: epa_rank, teams: ranked_teams,
                      league_share: round(league_share, 4), league_epa: round(league_epa, 3)})
         FROM play_direction
         WHERE season = {{season}} AND as_of_week = {{week}} AND span = 'season'
           AND situation = 'all_neutral' AND bucket_type IN ('side', 'width', 'zone')) AS direction,

        -- What each defense allows to WR / TE / RB targets (24_defense_vs_position.sql).
        (SELECT list({team: defense, position: position, targets: CAST(targets AS INTEGER),
                      games: games, ypg: round(yards_per_game, 1), tpg: round(targets_per_game, 1),
                      epa: round(epa_per_target, 3), rank: rank_allowed,
                      yards_rank: yards_rank_allowed, teams: teams,
                      league_epa: round(league_epa_per_target, 3)})
         FROM defense_vs_position
         WHERE season = {{season}} AND as_of_week = {{week}}) AS def_position,

        -- Rushing and passing yards per game, gained and allowed (25_team_yards.sql).
        (SELECT list({team: team, side: side, games: games,
                      rush_ypg: round(rush_ypg, 1), rush_rank: rush_ypg_rank,
                      ypc: round(yards_per_carry, 2), ypc_rank: ypc_rank,
                      pass_ypg: round(pass_ypg, 1), pass_rank: pass_ypg_rank, teams: teams})
         FROM team_yards
         WHERE season = {{season}} AND as_of_week = {{week}}) AS yards,

        -- Each team's QB, top 2 backs and top 4 WR/TE, with per-game trends
        -- for the prop angles (22_player_trends.sql).
        (SELECT list({team: team, role: role, role_rank: role_rank, player: player_name,
                      position: position, games: games, last4_games: last4_games,
                      targets: targets, receptions: receptions, rec_yards: rec_yards, rec_td: rec_td,
                      carries: carries, rush_yards: rush_yards, rush_td: rush_td,
                      completions: completions, pass_yards: pass_yards, pass_td: pass_td,
                      last4_targets: last4_targets, last4_receptions: last4_receptions,
                      last4_rec_yards: last4_rec_yards, last4_carries: last4_carries,
                      last4_rush_yards: last4_rush_yards, last4_pass_yards: last4_pass_yards,
                      target_share: round(target_share, 3), carry_share: round(carry_share, 3),
                      recent_weeks: recent_weeks, recent_rec_yards: recent_rec_yards,
                      recent_receptions: recent_receptions, recent_rush_yards: recent_rush_yards,
                      recent_pass_yards: recent_pass_yards}
                     ORDER BY team, role, role_rank)
         FROM player_trends
         WHERE season = {{season}} AND as_of_week = {{week}}) AS players,

        -- Coverage on the attack plan (37_coverage_matchup.sql): blitz, box
        -- and play action this season (FTN charting), man/zone last season.
        (SELECT list({team: team, side: side, dropbacks: dropbacks,
                      blitz_rate: round(blitz_rate, 3), blitz_rank: blitz_rank,
                      blitz_epa: round(blitz_epa, 3), noblitz_epa: round(noblitz_epa, 3),
                      blitz_epa_rank: blitz_epa_rank, blitzes: blitzes,
                      avg_rushers: round(avg_rushers, 2),
                      heavy_box_rate: round(heavy_box_rate, 3), heavy_box_rank: heavy_box_rank,
                      heavy_box_epa: round(heavy_box_epa, 3), runs: runs,
                      pa_rate: round(pa_rate, 3), pa_epa: round(pa_epa, 3), teams: teams,
                      league_blitz_rate: round(league_blitz_rate, 3),
                      league_blitz_epa: round(league_blitz_epa, 3), league_noblitz_epa: round(league_noblitz_epa, 3),
                      ly_dropbacks: ly_dropbacks, ly_man_rate: round(ly_man_rate, 3),
                      ly_zone_rate: round(ly_zone_rate, 3), ly_man_epa: round(ly_man_epa, 3),
                      ly_zone_epa: round(ly_zone_epa, 3), ly_top_coverage: ly_top_coverage,
                      ly_top_coverage_share: round(ly_top_coverage_share, 3)})
         FROM coverage_team
         WHERE season = {{season}} AND as_of_week = {{week}})  AS coverage,

        (SELECT list({team: team, player: player_name, position: position,
                      blitz_targets: blitz_targets, blitz_yards: blitz_yards, blitz_epa: round(blitz_sum_epa, 2),
                      noblitz_targets: noblitz_targets, noblitz_yards: noblitz_yards, noblitz_epa: round(noblitz_sum_epa, 2),
                      ly_man_targets: ly_man_targets, ly_man_yards: ly_man_yards, ly_man_epa: round(ly_man_sum_epa, 2),
                      ly_zone_targets: ly_zone_targets, ly_zone_yards: ly_zone_yards, ly_zone_epa: round(ly_zone_sum_epa, 2)})
         FROM coverage_players
         WHERE season = {{season}} AND as_of_week = {{week}})  AS coverage_players,

        -- "What stands out" picks, same rule as the one-pager.
        (SELECT list({team: team, priority: priority, situation: situation, metric: metric}
                     ORDER BY team, priority)
         FROM three_things
         WHERE season = {{season}} AND as_of_week = {{week}}) AS things
) TO '{{path}}' (FORMAT JSON);
