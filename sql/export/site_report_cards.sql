-- site_report_cards: every graded matchup of a season for the archive page,
-- as one JSON object. export_report_cards() in R/pipeline.R fills {{season}}
-- and {{path}}. A matchup is the notes written about one offense ("team") for
-- the team that played it ("opponent"); calls are the condensed notes.

COPY (
    SELECT
        {{season}} AS season,
        strftime(now() AT TIME ZONE 'UTC', '%Y-%m-%d %H:%M UTC') AS updated,
        (SELECT list({team: team, name: team_name, nick: team_nick, color: color_primary} ORDER BY team)
         FROM dim_team) AS teams,
        (SELECT list(g ORDER BY g.week DESC, g.team)
         FROM (SELECT {week: week, team: team, opponent: opponent,
                       gameday: strftime(gameday, '%Y-%m-%d'), is_home: is_home,
                       team_score: team_score, opponent_score: opponent_score,
                       calls: list({n: call_no, side: side, kind: kind, call: call,
                                    said: said, happened: happened, verdict: verdict} ORDER BY call_no)} AS g, week, team
               FROM report_card
               WHERE season = {{season}}
               GROUP BY week, team, opponent, gameday, is_home, team_score, opponent_score)) AS games,
        -- How each kind of call has held up across the league this season
        (SELECT list({n: call_no, call: label, graded: graded, correct: right_n} ORDER BY call_no)
         FROM (SELECT call_no,
                      CASE call_no WHEN 4 THEN 'Top target''s share' WHEN 5 THEN 'Take away the top target'
                                   WHEN 12 THEN 'Target the position they cover worst' ELSE any_value(call) END AS label,
                      COUNT(*) FILTER (WHERE verdict <> 'Didn''t come up') AS graded,
                      COUNT(*) FILTER (WHERE verdict IN ('Hit', 'Held')) AS right_n
               FROM report_card WHERE season = {{season}} GROUP BY call_no)) AS call_summary
) TO '{{path}}' (FORMAT JSON);
