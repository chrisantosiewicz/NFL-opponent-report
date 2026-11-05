-- scout_picks: the specific spots the notes call out each week, chosen once
-- here so the draft notes and the report card grade the same thing. One row
-- per season x week x team (the offense being scouted) x pick.
--
-- hot_spot   their most dangerous throw area on neutral downs. It must rank
--            top 8 with its single best play taken out and succeed at least as
--            often as the league there. When the best area is to one side and
--            the same depth outside the hashes on both sides also qualifies,
--            the pick is the outside lane ("deep outside the hashes, most often
--            right"), since a concept run to the other side is the same threat.
-- run_lean   the early-down run bucket they favor most over the league
--            (8+ points above league share, 4+ runs).
-- soft_lane / hard_lane  the early-down run width their defense handles
--            worst / best (15+ runs, ranked).

CREATE OR REPLACE TABLE scout_picks AS
WITH d AS (
    SELECT season, as_of_week AS week, team, side, situation, play_type, bucket_type, bucket,
           plays, type_plays, share, league_share, share - league_share AS lean,
           yards_per_play, success_rate, league_success, epa_per_play, league_epa,
           epa_wo_best, rank_wo_best, epa_rank, ranked_teams
    FROM with_week1('main.play_direction')   -- Week 1 picks come from last season
    WHERE span = 'season'
),

zone AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY season, week, team ORDER BY rank_wo_best, bucket) AS pick_no
    FROM d
    WHERE side = 'offense' AND situation = 'all_neutral' AND bucket_type = 'zone'
      AND plays >= 12 AND rank_wo_best <= 8 AND success_rate >= league_success
),

outside AS (
    SELECT * FROM d
    WHERE side = 'offense' AND situation = 'all_neutral' AND bucket_type = 'lane'
      AND bucket LIKE '%_outside'
      AND plays >= 12 AND rank_wo_best <= 8 AND success_rate >= league_success
),

hot AS (
    SELECT z.season, z.week, z.team, 'hot_spot' AS pick,
           CASE WHEN o.bucket IS NOT NULL THEN 'lane' ELSE 'zone' END AS bucket_type,
           COALESCE(o.bucket, z.bucket)                 AS bucket,
           CASE WHEN o.bucket IS NOT NULL THEN z.bucket END AS most_often,
           CASE WHEN o.bucket IS NOT NULL THEN z.plays END  AS most_often_plays,
           COALESCE(o.plays, z.plays) AS plays, COALESCE(o.type_plays, z.type_plays) AS type_plays,
           COALESCE(o.share, z.share) AS share, COALESCE(o.league_share, z.league_share) AS league_share,
           COALESCE(o.yards_per_play, z.yards_per_play) AS yards_per_play,
           COALESCE(o.success_rate, z.success_rate) AS success_rate,
           COALESCE(o.league_success, z.league_success) AS league_success,
           COALESCE(o.epa_per_play, z.epa_per_play) AS epa_per_play,
           COALESCE(o.league_epa, z.league_epa) AS league_epa,
           COALESCE(o.epa_wo_best, z.epa_wo_best) AS epa_wo_best,
           COALESCE(o.rank_wo_best, z.rank_wo_best) AS rank_wo_best,
           COALESCE(o.epa_rank, z.epa_rank) AS epa_rank,
           COALESCE(o.ranked_teams, z.ranked_teams) AS ranked_teams
    FROM zone z
    LEFT JOIN outside o
      ON o.season = z.season AND o.week = z.week AND o.team = z.team
     AND z.bucket NOT LIKE '%_middle'
     AND o.bucket = split_part(z.bucket, '_', 1) || '_outside'
     -- the other side has to carry some of it, or it's just the one side
     AND z.plays < o.plays
    WHERE z.pick_no = 1
),

lean AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY season, week, team ORDER BY lean DESC, plays DESC, bucket) AS pick_no
    FROM d
    WHERE side = 'offense' AND situation = 'early_down' AND play_type = 'run'
      AND plays >= 4 AND type_plays >= 6 AND lean >= 0.08
),

lane AS (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY season, week, team ORDER BY epa_rank, bucket)      AS soft_no,
        ROW_NUMBER() OVER (PARTITION BY season, week, team ORDER BY epa_rank DESC, bucket) AS hard_no
    FROM d
    WHERE side = 'defense' AND situation = 'early_down' AND play_type = 'run' AND bucket_type = 'width'
      AND plays >= 15 AND epa_rank IS NOT NULL
)

SELECT * FROM hot
UNION ALL BY NAME
SELECT season, week, team, 'run_lean' AS pick, bucket_type, bucket, plays, type_plays, share, league_share,
       yards_per_play, success_rate, league_success, epa_per_play, league_epa, epa_wo_best, rank_wo_best, epa_rank, ranked_teams
FROM lean WHERE pick_no = 1
UNION ALL BY NAME
SELECT season, week, team, 'soft_lane' AS pick, bucket_type, bucket, plays, type_plays, share, league_share,
       yards_per_play, success_rate, league_success, epa_per_play, league_epa, epa_wo_best, rank_wo_best, epa_rank, ranked_teams
FROM lane WHERE soft_no = 1
UNION ALL BY NAME
SELECT season, week, team, 'hard_lane' AS pick, bucket_type, bucket, plays, type_plays, share, league_share,
       yards_per_play, success_rate, league_success, epa_per_play, league_epa, epa_wo_best, rank_wo_best, epa_rank, ranked_teams
FROM lane WHERE hard_no = 1;
