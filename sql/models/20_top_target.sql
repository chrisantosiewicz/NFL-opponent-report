-- top_target: each team's most-targeted receiver before each week, and the
-- situations where they go to him most. One row per season x as_of_week x team.
--
--   top receiver      most season-to-date targets (ties: higher EPA)
--   league_rank       his target share among every receiver in the league with
--                     at least 3 targets per team game played (1 = highest)
--   last-4 share      the same player's share over the team's last 4 games
--   others_epa        EPA per target to everyone else on the team
--   sit1 / sit2       the two situations where his share is highest, among
--                     those with 10+ team targets and 5+ of his. Shares there
--                     are compared with his overall share in the notes.

CREATE OR REPLACE TABLE top_target AS
WITH season_all AS (
    SELECT r.*, g.games
    FROM receiver_targets r
    JOIN (SELECT season, as_of_week, team, COUNT(*) AS games
          FROM game_windows GROUP BY ALL) g USING (season, as_of_week, team)
    WHERE r.span = 'season' AND r.situation = 'all'
),

ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY season, as_of_week, team
                              ORDER BY targets DESC, sum_epa DESC, receiver_id) AS team_pick,
           CASE WHEN targets >= 3 * games THEN
               RANK() OVER (PARTITION BY season, as_of_week, targets >= 3 * games ORDER BY share DESC)
           END AS league_rank
    FROM season_all
),

top AS (
    SELECT * FROM ranked WHERE team_pick = 1
),

situations AS (
    SELECT r.season, r.as_of_week, r.team, r.situation, r.targets, r.team_targets, r.share,
           ROW_NUMBER() OVER (PARTITION BY r.season, r.as_of_week, r.team
                              ORDER BY r.share DESC, r.team_targets DESC) AS pick
    FROM receiver_targets r
    JOIN top t USING (season, as_of_week, team, receiver_id)
    WHERE r.span = 'season' AND r.situation NOT IN ('all')
      AND r.team_targets >= 10 AND r.targets >= 5
)

SELECT
    t.season, t.as_of_week, t.team, t.games, t.through_week,
    t.receiver_id, t.receiver_name, t.position,
    t.targets, t.team_targets, t.share,
    t.sum_epa / t.targets                                                 AS epa_per_target,
    (t.team_sum_epa - t.sum_epa) / NULLIF(t.team_targets - t.targets, 0)  AS others_epa_per_target,
    t.league_rank,
    l4.targets       AS targets_last4,
    l4.team_targets  AS team_targets_last4,
    l4.share         AS share_last4,
    s1.situation     AS sit1, s1.targets AS sit1_targets, s1.team_targets AS sit1_team_targets, s1.share AS sit1_share,
    s2.situation     AS sit2, s2.targets AS sit2_targets, s2.team_targets AS sit2_team_targets, s2.share AS sit2_share,
    dp.targets       AS deep_targets,
    dp.team_targets  AS deep_team_targets
FROM top t
LEFT JOIN receiver_targets l4
  ON l4.season = t.season AND l4.as_of_week = t.as_of_week AND l4.team = t.team
 AND l4.receiver_id = t.receiver_id AND l4.span = 'last4' AND l4.situation = 'all'
LEFT JOIN situations s1
  ON s1.season = t.season AND s1.as_of_week = t.as_of_week AND s1.team = t.team AND s1.pick = 1
LEFT JOIN situations s2
  ON s2.season = t.season AND s2.as_of_week = t.as_of_week AND s2.team = t.team AND s2.pick = 2
LEFT JOIN receiver_targets dp
  ON dp.season = t.season AND dp.as_of_week = t.as_of_week AND dp.team = t.team
 AND dp.receiver_id = t.receiver_id AND dp.span = 'season' AND dp.situation = 'deep';
