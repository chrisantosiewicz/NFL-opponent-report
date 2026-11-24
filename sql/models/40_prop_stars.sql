-- prop_stars: a 1-5 star score on each player prop line in
-- config/prop_lines.csv (raw_prop_lines), for the Predictions tab. One row
-- per game x player x market; the pick is over or under. Same point scale and
-- star cutoffs as 39_pick_stars.sql. Rules: _shared/definitions.md, "Pick stars".
--
-- Only players in player_trends (each team's top QB, 2 backs, 4 WR/TE) can be
-- scored; the book's name is matched to his after dropping case, punctuation
-- and Jr./Sr./II-V. Other lines are left out.
--
--   projection  half season average, half last-4 average (per game played)
--   gap      0..4  projection vs the line, as a share of the line: under 5%
--                  0, 5-10% 1, 10-15% 2, 15-25% 3, 25%+ 4.
--   agree   -1..1  season and last-4 averages both on the pick's side of the
--                  line (+1), or on opposite sides (-1).
--   support  0..2  +1 each, at most 2: the opponent's defense is in the top
--                  quarter (over) or bottom quarter (under) for yards allowed
--                  to that stat; W2's game script (total 47+ for a passing or
--                  receiving over, 41 or less for an under; his team winning by
--                  3+ for a rushing over, losing by 3+ for an under); wind or
--                  rain for a passing or receiving under.
--   risk    -2..0  questionable (-1) or out/doubtful (-2) on the injury
--                  report, fewer than 4 games (-1), a passing or receiving over
--                  in wind or rain (-1). Floor -2.

CREATE OR REPLACE TABLE prop_stars AS
WITH lines AS (
    SELECT l.*, s.home_team, s.away_team, CAST(s.gameday AS DATE) AS gameday,
           trim(regexp_replace(regexp_replace(lower(l.player), '[^a-z ]', '', 'g'),
                               ' (jr|sr|ii|iii|iv|v)$', '')) AS name_key
    FROM raw_prop_lines l
    JOIN raw_schedules s ON s.game_id = l.game_id
    WHERE l.market IN ('pass_yds', 'rush_yds', 'rec_yds', 'receptions') AND l.line > 0
),

players AS (   -- a player can hold two roles in player_trends; his stats are the same
    SELECT DISTINCT ON (season, as_of_week, team, player_name)
           season, as_of_week, team, player_name, position, games, last4_games,
           receptions, rec_yards, rush_yards, pass_yards,
           last4_receptions, last4_rec_yards, last4_rush_yards, last4_pass_yards,
           trim(regexp_replace(regexp_replace(lower(player_name), '[^a-z ]', '', 'g'),
                               ' (jr|sr|ii|iii|iv|v)$', '')) AS name_key
    FROM player_trends
    ORDER BY season, as_of_week, team, player_name, role
),

matched AS (
    SELECT l.season, l.week, l.game_id, l.gameday, l.home_team, l.away_team,
           l.market, l.line, l.books, l.fetched_at,
           p.player_name AS player, p.name_key, p.team, p.position, p.games,
           CASE WHEN p.team = l.home_team THEN l.away_team ELSE l.home_team END AS opponent,
           CASE l.market WHEN 'pass_yds' THEN p.pass_yards WHEN 'rush_yds' THEN p.rush_yards
                         WHEN 'rec_yds' THEN p.rec_yards ELSE p.receptions END
               * 1.0 / NULLIF(p.games, 0)                                       AS season_avg,
           CASE l.market WHEN 'pass_yds' THEN p.last4_pass_yards WHEN 'rush_yds' THEN p.last4_rush_yards
                         WHEN 'rec_yds' THEN p.last4_rec_yards ELSE p.last4_receptions END
               * 1.0 / NULLIF(p.last4_games, 0)                                 AS last4_avg
    FROM lines l
    JOIN players p ON p.season = l.season AND p.as_of_week = l.week
                  AND p.team IN (l.home_team, l.away_team) AND p.name_key = l.name_key
),

picks AS (
    SELECT *,
           0.5 * season_avg + 0.5 * COALESCE(last4_avg, season_avg) AS projection
    FROM matched
    WHERE season_avg IS NOT NULL
),

sided AS (
    SELECT *,
           CASE WHEN projection >= line THEN 'over' ELSE 'under' END AS pick,
           abs(projection - line) / line                              AS gap_share
    FROM picks
),

-- What the opponent's defense allows to this stat (rank 1 = allows the most).
def_rank AS (
    SELECT s.game_id, s.team, s.market, s.player,
           CASE WHEN s.market = 'pass_yds' THEN ty.pass_ypg_rank
                WHEN s.market = 'rush_yds' THEN ty.rush_ypg_rank
                ELSE dp.yards_rank_allowed END AS rank_allowed,
           CASE WHEN s.market IN ('pass_yds', 'rush_yds') THEN ty.teams ELSE dp.teams END AS teams
    FROM sided s
    LEFT JOIN team_yards ty ON ty.season = s.season AND ty.as_of_week = s.week
                           AND ty.team = s.opponent AND ty.side = 'defense'
    LEFT JOIN defense_vs_position dp ON dp.season = s.season AND dp.as_of_week = s.week
                                    AND dp.defense = s.opponent AND dp.position = s.position
),

inj AS (
    SELECT season, week, team,
           trim(regexp_replace(regexp_replace(lower(player_name), '[^a-z ]', '', 'g'),
                               ' (jr|sr|ii|iii|iv|v)$', '')) AS name_key,
           min(CASE flag WHEN 'out' THEN 1 WHEN 'questionable' THEN 2 ELSE 3 END) AS worst
    FROM injury_report
    GROUP BY ALL
),

parts AS (
    SELECT s.*,
        CASE WHEN gap_share < 0.05 THEN 0 WHEN gap_share < 0.10 THEN 1 WHEN gap_share < 0.15 THEN 2
             WHEN gap_share < 0.25 THEN 3 ELSE 4 END                                     AS gap_pts,
        CASE WHEN last4_avg IS NULL THEN 0
             WHEN (season_avg >= line) = (last4_avg >= line) AND (season_avg >= line) = (pick = 'over') THEN 1
             WHEN (season_avg >= line) <> (last4_avg >= line) THEN -1
             ELSE 0 END                                                                    AS agree_pts,
        (d.rank_allowed IS NOT NULL AND
            ((pick = 'over'  AND d.rank_allowed <= d.teams / 4.0)
          OR (pick = 'under' AND d.rank_allowed >  d.teams * 3 / 4.0)))                    AS s_defense,
        (w.game_id IS NOT NULL AND
            CASE WHEN s.market = 'rush_yds' THEN
                     (pick = 'over'  AND (CASE WHEN s.team = s.home_team THEN 1 ELSE -1 END) * w.w2_home_margin >= 3)
                  OR (pick = 'under' AND (CASE WHEN s.team = s.home_team THEN 1 ELSE -1 END) * w.w2_home_margin <= -3)
                 ELSE (pick = 'over' AND w.w2_total >= 47) OR (pick = 'under' AND w.w2_total <= 41) END) AS s_script,
        (s.market <> 'rush_yds' AND pick = 'under' AND COALESCE(wx.is_windy OR wx.is_wet, FALSE)) AS s_weather,
        COALESCE(i.worst, 3)                                                               AS injury_level,
        (s.games < 4)                                                                      AS r_small,
        (s.market <> 'rush_yds' AND pick = 'over' AND COALESCE(wx.is_windy OR wx.is_wet, FALSE)) AS r_weather,
        d.rank_allowed, d.teams AS rank_teams, w.w2_total, w.w2_home_margin
    FROM sided s
    LEFT JOIN def_rank d ON d.game_id = s.game_id AND d.team = s.team AND d.market = s.market AND d.player = s.player
    LEFT JOIN w2_predictions w ON w.game_id = s.game_id
    LEFT JOIN game_weather wx ON wx.game_id = s.game_id
    LEFT JOIN inj i ON i.season = s.season AND i.week = s.week AND i.team = s.team AND i.name_key = s.name_key
),

scored AS (
    SELECT *,
        least(CAST(s_defense AS INTEGER) + CAST(COALESCE(s_script, FALSE) AS INTEGER)
              + CAST(s_weather AS INTEGER), 2)                                             AS support_pts,
        greatest(-(CASE injury_level WHEN 1 THEN 2 WHEN 2 THEN 1 ELSE 0 END
                   + CAST(r_small AS INTEGER) + CAST(r_weather AS INTEGER)), -2)           AS risk_pts
    FROM parts
)

SELECT
    season, week, gameday, game_id, home_team, away_team, team, opponent, player, position,
    market, line, books, fetched_at, pick,
    CASE pick WHEN 'over' THEN 'Over ' ELSE 'Under ' END || CAST(line AS VARCHAR) || ' '
        || CASE market WHEN 'pass_yds' THEN 'passing yds' WHEN 'rush_yds' THEN 'rushing yds'
                       WHEN 'rec_yds' THEN 'receiving yds' ELSE 'receptions' END AS pick_label,
    round(season_avg, 1) AS season_avg, round(last4_avg, 1) AS last4_avg,
    round(projection, 1) AS projection, round(gap_share, 3) AS gap_share,
    gap_pts, agree_pts, support_pts, risk_pts,
    gap_pts + agree_pts + support_pts + risk_pts AS points,
    CASE WHEN gap_pts + agree_pts + support_pts + risk_pts <= 1 THEN 1
         WHEN gap_pts + agree_pts + support_pts + risk_pts = 2 THEN 2
         WHEN gap_pts + agree_pts + support_pts + risk_pts <= 4 THEN 3
         WHEN gap_pts + agree_pts + support_pts + risk_pts <= 6 THEN 4
         ELSE 5 END AS stars,
    list_filter([
        'Projects ' || CAST(round(projection, 1) AS VARCHAR) || ' (season ' || CAST(round(season_avg, 1) AS VARCHAR)
            || COALESCE(', last 4 ' || CAST(round(last4_avg, 1) AS VARCHAR), '') || ')',
        CASE WHEN agree_pts = 1 THEN 'Season and last 4 agree' WHEN agree_pts = -1 THEN 'Season and last 4 split' END,
        CASE WHEN s_defense THEN opponent || ' ' || CASE WHEN rank_allowed <= rank_teams / 4.0 THEN 'allow' ELSE 'hold' END
                                 || ' (' || CAST(rank_allowed AS VARCHAR) || ' of ' || CAST(rank_teams AS VARCHAR) || ')' END,
        CASE WHEN s_script THEN 'W2 game script' END,
        CASE WHEN s_weather THEN 'Wind or rain' END,
        CASE injury_level WHEN 1 THEN 'Out or doubtful' WHEN 2 THEN 'Questionable' END,
        CASE WHEN r_small THEN 'Under 4 games' END,
        CASE WHEN r_weather THEN 'Over in wind or rain' END
    ], lambda x: x IS NOT NULL) AS reasons
FROM scored;
