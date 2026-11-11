-- betting_trends: how each team has done against the betting lines, for the
-- live page's Predictions tab. One row per season x as_of_week x team x span
-- (season / last4) x split (all, home, away, favorite, underdog).
--
-- These are records against past closing lines, not predictions. Same windows
-- and leakage rule as the tendencies (game_windows: only games before the
-- report's week). A split with fewer than 4 games is marked small on the page.
--
-- From the team's side: team_line is its spread in betting notation (favorite
-- negative), cover_margin = its margin + team_line (> 0 covered, 0 push),
-- total_vs_line = points scored by both teams minus the total line.

CREATE OR REPLACE TABLE betting_trends AS
WITH team_lines AS (
    SELECT game_id, home_team AS team, TRUE AS is_home,
           home_line AS team_line, result AS margin, total_points, total_line
    FROM stg_market_lines WHERE is_complete
    UNION ALL
    SELECT game_id, away_team, FALSE, -home_line, -result, total_points, total_line
    FROM stg_market_lines WHERE is_complete
),
g AS (
    SELECT w.season, w.as_of_week, w.team, s.span, t.*,
           t.margin + t.team_line           AS cover_margin,
           t.total_points - t.total_line    AS total_vs_line
    FROM game_windows w
    JOIN team_lines t ON t.game_id = w.game_id AND t.team = w.team
    CROSS JOIN (VALUES ('season'), ('last4')) s(span)
    WHERE s.span = 'season' OR w.in_last4
),
split AS (
    SELECT g.*, x.split
    FROM g
    CROSS JOIN (VALUES ('all'), ('home'), ('away'), ('favorite'), ('underdog')) x(split)
    WHERE x.split = 'all'
       OR (x.split = 'home' AND g.is_home)
       OR (x.split = 'away' AND NOT g.is_home)
       OR (x.split = 'favorite' AND g.team_line < 0)
       OR (x.split = 'underdog' AND g.team_line > 0)
),
agg AS (
    SELECT
        season, as_of_week, team, span, split,
        count(*)                                           AS games,
        count(*) FILTER (WHERE margin > 0)                 AS su_wins,
        count(*) FILTER (WHERE margin < 0)                 AS su_losses,
        count(*) FILTER (WHERE margin = 0)                 AS su_ties,
        count(team_line)                                   AS lined_games,
        count(*) FILTER (WHERE cover_margin > 0)           AS ats_wins,
        count(*) FILTER (WHERE cover_margin < 0)           AS ats_losses,
        count(*) FILTER (WHERE cover_margin = 0)           AS ats_pushes,
        avg(cover_margin)                                  AS avg_cover_margin,
        count(*) FILTER (WHERE total_vs_line > 0)          AS overs,
        count(*) FILTER (WHERE total_vs_line < 0)          AS unders,
        count(*) FILTER (WHERE total_vs_line = 0)          AS total_pushes,
        avg(total_vs_line)                                 AS avg_total_vs_line
    FROM split
    GROUP BY ALL
)

SELECT
    a.*,
    a.ats_wins / NULLIF(a.ats_wins + a.ats_losses, 0)  AS cover_rate,
    a.overs / NULLIF(a.overs + a.unders, 0)            AS over_rate,
    -- league rank of cover rate (1 = covers most), among teams with a decided game
    CASE WHEN a.ats_wins + a.ats_losses > 0 THEN
        rank() OVER (PARTITION BY a.season, a.as_of_week, a.span, a.split,
                                  (a.ats_wins + a.ats_losses > 0)
                     ORDER BY a.ats_wins / NULLIF(a.ats_wins + a.ats_losses, 0) DESC) END AS cover_rank,
    CASE WHEN a.overs + a.unders > 0 THEN
        rank() OVER (PARTITION BY a.season, a.as_of_week, a.span, a.split,
                                  (a.overs + a.unders > 0)
                     ORDER BY a.overs / NULLIF(a.overs + a.unders, 0) DESC) END AS over_rank,
    count(*) FILTER (WHERE a.ats_wins + a.ats_losses > 0)
        OVER (PARTITION BY a.season, a.as_of_week, a.span, a.split) AS league_teams
FROM agg a;
