-- player_trends: each team's main skill players as known before each week,
-- for the prop angles on the live page's attack view. One row per season x
-- as_of_week x team x player x role (a player can be in two roles, e.g. a
-- back who is a top rusher and a top receiver).
--
-- Stats come from the play-by-play, so they can differ a little from the
-- official box score (penalty-negated plays and two-point tries are out):
--   receiving: targets (receiver listed), receptions, yards on catches, TDs
--   rushing:   every carry with a rusher listed, scrambles included (that is
--              how box scores count QB rushing), yards, TDs
--   passing:   completions and yards on completions, passing TDs
-- Per-game averages divide by the games the player had a stat in, so a game
-- missed to injury doesn't drag the average down. recent_* list the last 4
-- of those games, newest first.
--
-- Picks per team: the QB with the most passing yards, the 2 backs with the
-- most carries, the 4 WR/TE with the most targets (season to date).

CREATE OR REPLACE TABLE player_trends AS
WITH rec AS (
    SELECT game_id, team, receiver_id AS player_id,
           COUNT(*) AS targets, SUM(is_complete) AS receptions,
           SUM(CASE WHEN is_complete = 1 THEN COALESCE(yards_gained, 0) ELSE 0 END) AS rec_yards,
           SUM(is_pass_td) AS rec_td
    FROM stg_plays
    WHERE is_pass = 1 AND receiver_id IS NOT NULL
    GROUP BY ALL
),

rush AS (
    SELECT game_id, team, rusher_id AS player_id,
           COUNT(*) AS carries, SUM(COALESCE(yards_gained, 0)) AS rush_yards, SUM(is_rush_td) AS rush_td
    FROM stg_plays
    WHERE rusher_id IS NOT NULL
    GROUP BY ALL
),

pass AS (
    SELECT game_id, team, passer_id AS player_id,
           SUM(is_complete) AS completions,
           SUM(CASE WHEN is_complete = 1 THEN COALESCE(yards_gained, 0) ELSE 0 END) AS pass_yards,
           SUM(is_pass_td) AS pass_td
    FROM stg_plays
    WHERE is_pass = 1 AND passer_id IS NOT NULL
    GROUP BY ALL
),

keys AS (
    SELECT game_id, team, player_id FROM rec
    UNION SELECT game_id, team, player_id FROM rush
    UNION SELECT game_id, team, player_id FROM pass
),

game_log AS (
    SELECT k.game_id, k.team, k.player_id,
           COALESCE(r.targets, 0) AS targets, COALESCE(r.receptions, 0) AS receptions,
           COALESCE(r.rec_yards, 0) AS rec_yards, COALESCE(r.rec_td, 0) AS rec_td,
           COALESCE(u.carries, 0) AS carries, COALESCE(u.rush_yards, 0) AS rush_yards,
           COALESCE(u.rush_td, 0) AS rush_td,
           COALESCE(p.completions, 0) AS completions, COALESCE(p.pass_yards, 0) AS pass_yards,
           COALESCE(p.pass_td, 0) AS pass_td
    FROM keys k
    LEFT JOIN rec  r USING (game_id, team, player_id)
    LEFT JOIN rush u USING (game_id, team, player_id)
    LEFT JOIN pass p USING (game_id, team, player_id)
),

windowed AS (
    SELECT w.season, w.as_of_week, w.team, w.week, w.in_last4, l.*  EXCLUDE (team)
    FROM game_windows w
    JOIN game_log l ON l.game_id = w.game_id AND l.team = w.team
),

totals AS (
    SELECT season, as_of_week, team, player_id,
           COUNT(*)                          AS games,
           COUNT(*) FILTER (WHERE in_last4)  AS last4_games,
           SUM(targets) AS targets, SUM(receptions) AS receptions, SUM(rec_yards) AS rec_yards,
           SUM(rec_td) AS rec_td, SUM(carries) AS carries, SUM(rush_yards) AS rush_yards,
           SUM(rush_td) AS rush_td, SUM(completions) AS completions,
           SUM(pass_yards) AS pass_yards, SUM(pass_td) AS pass_td,
           SUM(targets)    FILTER (WHERE in_last4) AS last4_targets,
           SUM(receptions) FILTER (WHERE in_last4) AS last4_receptions,
           SUM(rec_yards)  FILTER (WHERE in_last4) AS last4_rec_yards,
           SUM(carries)    FILTER (WHERE in_last4) AS last4_carries,
           SUM(rush_yards) FILTER (WHERE in_last4) AS last4_rush_yards,
           SUM(pass_yards) FILTER (WHERE in_last4) AS last4_pass_yards,
           -- last 4 games he played, newest first
           (list(rec_yards  ORDER BY week DESC))[1:4] AS recent_rec_yards,
           (list(receptions ORDER BY week DESC))[1:4] AS recent_receptions,
           (list(rush_yards ORDER BY week DESC))[1:4] AS recent_rush_yards,
           (list(pass_yards ORDER BY week DESC))[1:4] AS recent_pass_yards,
           (list(week       ORDER BY week DESC))[1:4] AS recent_weeks
    FROM windowed
    GROUP BY ALL
),

team_totals AS (
    SELECT season, as_of_week, team,
           SUM(targets) AS team_targets, SUM(carries) AS team_carries
    FROM totals GROUP BY ALL
),

named AS (
    SELECT t.*, tt.team_targets, tt.team_carries,
           COALESCE(pl.display_name, t.player_id) AS player_name,
           CASE WHEN pl.position IN ('RB', 'FB', 'HB') THEN 'RB' ELSE pl.position END AS position
    FROM totals t
    JOIN team_totals tt USING (season, as_of_week, team)
    LEFT JOIN (SELECT gsis_id, any_value(display_name) AS display_name, any_value(position) AS position
               FROM raw_players GROUP BY gsis_id) pl
      ON pl.gsis_id = t.player_id
),

picks AS (
    SELECT 'passer' AS role, ROW_NUMBER() OVER (PARTITION BY season, as_of_week, team
                                                ORDER BY pass_yards DESC, player_id) AS role_rank, *
    FROM named WHERE position = 'QB' AND completions > 0
    UNION ALL
    SELECT 'rusher', ROW_NUMBER() OVER (PARTITION BY season, as_of_week, team
                                        ORDER BY carries DESC, player_id), *
    FROM named WHERE position = 'RB' AND carries > 0
    UNION ALL
    SELECT 'receiver', ROW_NUMBER() OVER (PARTITION BY season, as_of_week, team
                                          ORDER BY targets DESC, player_id), *
    FROM named WHERE position IN ('WR', 'TE') AND targets > 0
)

SELECT *,
       targets * 1.0 / NULLIF(team_targets, 0) AS target_share,
       carries * 1.0 / NULLIF(team_carries, 0) AS carry_share
FROM picks
WHERE (role = 'passer' AND role_rank = 1)
   OR (role = 'rusher' AND role_rank <= 2)
   OR (role = 'receiver' AND role_rank <= 4);
