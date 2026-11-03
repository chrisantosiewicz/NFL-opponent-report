-- report_card: after each game, every call the scouting notes made for that
-- matchup, in one line, next to what happened. One row per season x week x
-- team (the offense that was scouted) x call. `opponent` is "we".
--
-- The calls come from the same as-of tables the notes use (games before the
-- week only); "happened" comes from that week's game alone. Two kinds:
--   tendency  a claim about what they do (run-first, lean right, 3rd & long).
--             Hit when the game showed it, Miss when it didn't.
--   warning   a threat to take away (top target, hot spot, a soft spot in
--             their defense for us). Graded on production, not volume, since
--             fewer targets can mean our coverage worked:
--             defense side: Called it (it showed up and hurt us; outcome =
--             'Hurt us') / Held (we took it away, so the game can't say
--             whether the call was right)
--             offense side: Hit (we got it) / Miss
-- Mixed = yards and EPA disagree (run lanes).
-- Didn't come up = too few plays in the game to say (thresholds below).
-- Calls with no clear lean that week are left out, as they are in the notes.
-- Week 1 is scouted from last season's full regular season (basis =
-- 'last_season'), so its grades are kept apart from the in-season rates.

CREATE OR REPLACE TABLE report_card AS
WITH
    -- Week 1 reads last season's full year (27_week1_carryover.sql)
    tendency_ranks      AS (FROM with_week1('main.tendency_ranks')),
    formation_tells     AS (FROM with_week1('main.formation_tells')),
    top_target          AS (FROM with_week1('main.top_target')),
    defense_splits      AS (FROM with_week1('main.defense_splits')),
    defense_vs_position AS (FROM with_week1('main.defense_vs_position')),
    team_yards          AS (FROM with_week1('main.team_yards')),
    play_direction      AS (FROM with_week1('main.play_direction')),
    score_splits        AS (FROM with_week1('main.score_splits')),
m AS (
    SELECT g.season, g.week, g.team, g.opponent, g.game_id, g.gameday, g.is_home,
           g.team_score, g.opponent_score
    FROM stg_team_games g
    WHERE g.is_complete
      AND EXISTS (SELECT 1 FROM tendency_ranks t WHERE t.season = g.season AND t.as_of_week = g.week AND t.team = g.team)
),

theirs AS (   -- their offense in the graded game
    SELECT m.season, m.week, m.team, p.* EXCLUDE (season, week, team)
    FROM m JOIN stg_plays p ON p.game_id = m.game_id AND p.team = m.team
),

ours AS (     -- our offense against their defense in the graded game
    SELECT m.season, m.week, m.team, p.* EXCLUDE (season, week, team)
    FROM m JOIN stg_plays p ON p.game_id = m.game_id AND p.team = m.opponent
),

tr AS (
    SELECT season, as_of_week AS week, team, situation, metric, value, league_rank, league_teams, n, league_avg
    FROM tendency_ranks WHERE span = 'season'
),

ds AS (
    SELECT season, as_of_week AS week, defense AS team, situation, play_type, plays, epa_allowed, rank_allowed, teams, league_epa
    FROM defense_splits WHERE span = 'season'
),

-- 1. Early-down identity -------------------------------------------------------
c_identity AS (
    SELECT m.season, m.week, m.team, 1 AS call_no, 'defense' AS side, 'tendency' AS kind, 'Early-down identity' AS call,
        CASE WHEN t.league_rank >= t.league_teams - 7 THEN concat('Run-first: ', note_ord(t.league_rank), ' in early-down pass rate over expected')
             WHEN t.league_rank <= 8 THEN concat('Pass-first: ', note_ord(t.league_rank), ' in early-down pass rate over expected')
             ELSE concat('Balanced: ', note_value('proe', t.value), ' over expected (', note_ord(t.league_rank), ')') END AS said,
        CASE WHEN g.n < 10 THEN concat('Only ', g.n, ' neutral early-down plays')
             ELSE concat(CASE WHEN g.proe < 0 THEN 'Ran ' ELSE 'Passed ' END, CAST(abs(round(100 * g.proe)) AS INTEGER),
                         ' pts more than expected on ', g.n, ' neutral early downs') END AS happened,
        CASE WHEN g.n < 10 THEN 'Didn''t come up'
             WHEN t.league_rank >= t.league_teams - 7 THEN CASE WHEN g.proe < 0 THEN 'Hit' ELSE 'Miss' END
             WHEN t.league_rank <= 8 THEN CASE WHEN g.proe > 0 THEN 'Hit' ELSE 'Miss' END
             ELSE CASE WHEN abs(g.proe) <= 0.07 THEN 'Hit' ELSE 'Miss' END END AS verdict
    FROM m
    JOIN tr t ON t.season = m.season AND t.week = m.week AND t.team = m.team AND t.situation = 'early_down' AND t.metric = 'proe'
    JOIN (SELECT season, week, team, COUNT(*) AS n, AVG(is_pass - xpass) AS proe
          FROM theirs WHERE is_early_down AND is_neutral_wp AND xpass IS NOT NULL GROUP BY ALL) g
      ON g.season = m.season AND g.week = m.week AND g.team = m.team
),

-- 2. Whether their early-down runs / dropbacks work ----------------------------
c_works AS (
    SELECT m.season, m.week, m.team, CASE t.metric WHEN 'epa_run' THEN 2 ELSE 3 END, 'defense', 'tendency',
        CASE t.metric WHEN 'epa_run' THEN 'Early-down runs' ELSE 'Early-down dropbacks' END,
        concat(CASE WHEN t.league_rank <= 10 THEN 'They work: ' ELSE 'They don''t work: ' END,
               note_epa(t.value), ' EPA per play (', note_ord(t.league_rank), ')'),
        concat(note_epa(g.epa), ' EPA and ', note_yds(g.ypp), ' yards per play on ', g.n, ' (league ', note_epa(t.league_avg), ')'),
        CASE WHEN g.n < 6 THEN 'Didn''t come up'
             WHEN (t.league_rank <= 10) = (g.epa > t.league_avg) THEN 'Hit' ELSE 'Miss' END
    FROM m
    JOIN tr t ON t.season = m.season AND t.week = m.week AND t.team = m.team AND t.situation = 'early_down'
             AND t.metric IN ('epa_run', 'epa_pass') AND (t.league_rank <= 10 OR t.league_rank >= t.league_teams - 9)
    JOIN (SELECT season, week, team, CASE WHEN is_pass = 1 THEN 'epa_pass' ELSE 'epa_run' END AS metric,
                 COUNT(*) AS n, AVG(epa) AS epa, AVG(yards_gained) AS ypp
          FROM theirs WHERE is_early_down AND is_neutral_wp GROUP BY ALL) g
      ON g.season = m.season AND g.week = m.week AND g.team = m.team AND g.metric = t.metric
),

-- 3 and 4. Top target: volume (tendency) and production (warning) --------------
tt_game AS (
    SELECT t.season, t.week, t.team, COUNT(*) AS team_targets,
           COUNT(*) FILTER (WHERE t.receiver_id = tt.receiver_id) AS targets,
           COALESCE(SUM(COALESCE(t.yards_gained, 0)) FILTER (WHERE t.receiver_id = tt.receiver_id), 0) AS yards,
           COALESCE(SUM(COALESCE(t.epa, 0)) FILTER (WHERE t.receiver_id = tt.receiver_id), 0) AS epa
    FROM theirs t
    JOIN top_target tt ON tt.season = t.season AND tt.as_of_week = t.week AND tt.team = t.team
    WHERE t.is_pass = 1 AND t.receiver_id IS NOT NULL
    GROUP BY ALL
),

c_target AS (
    SELECT m.season, m.week, m.team, 4, 'defense', 'tendency', concat(tt.receiver_name, '''s target share'),
        concat(note_pct(tt.share), ' of their targets'),
        concat(g.targets, ' of ', g.team_targets, ' (', note_pct(g.targets * 1.0 / g.team_targets), ')'),
        CASE WHEN g.team_targets < 10 THEN 'Didn''t come up'
             WHEN g.targets * 1.0 / g.team_targets >= tt.share - 0.08 THEN 'Hit' ELSE 'Miss' END
    FROM m
    JOIN top_target tt ON tt.season = m.season AND tt.as_of_week = m.week AND tt.team = m.team
    JOIN tt_game g ON g.season = m.season AND g.week = m.week AND g.team = m.team
    WHERE tt.share >= 0.22 AND tt.targets >= 20
    UNION ALL
    SELECT m.season, m.week, m.team, 5, 'defense', 'warning', concat('Take away ', tt.receiver_name),
        concat(note_epa(tt.epa_per_target), ' EPA per target; everyone else ', note_epa(tt.others_epa_per_target)),
        concat(g.targets, ' targets, ', CAST(g.yards AS INTEGER), ' yards, ', note_epa(g.epa), ' EPA'),
        CASE WHEN g.targets = 0 THEN 'Didn''t come up'   -- likely out, not covered
             WHEN g.epa / g.targets <= 0.10 THEN 'Held' ELSE 'Called it' END
    FROM m
    JOIN top_target tt ON tt.season = m.season AND tt.as_of_week = m.week AND tt.team = m.team
    JOIN tt_game g ON g.season = m.season AND g.week = m.week AND g.team = m.team
    WHERE tt.share >= 0.22 AND tt.targets >= 20 AND tt.epa_per_target - tt.others_epa_per_target >= 0.30
),

-- 5. Early-down run lean -------------------------------------------------------
lean_game AS (
    SELECT season, week, team, run_location, run_gap,
           CASE WHEN run_location = 'middle' OR run_gap = 'guard' THEN 'inside'
                WHEN run_gap = 'tackle' THEN 'off_tackle' ELSE 'outside' END AS width,
           yards_gained, epa
    FROM theirs
    WHERE is_run = 1 AND is_early_down AND is_neutral_wp AND run_location IS NOT NULL
      AND (run_location = 'middle' OR run_gap IS NOT NULL)
),

c_lean AS (
    SELECT m.season, m.week, m.team, 6, 'defense', 'tendency', 'Early-down run direction',
        concat(note_pct(sp.share), ' of early-down runs ', note_bucket(sp.bucket), ' (league ', note_pct(sp.league_share), ')'),
        concat(COUNT(*) FILTER (WHERE (sp.bucket_type = 'width' AND l.width = sp.bucket) OR (sp.bucket_type = 'side' AND l.run_location = sp.bucket)),
               ' of ', COUNT(*), ' runs'),
        CASE WHEN COUNT(*) < 6 THEN 'Didn''t come up'
             WHEN COUNT(*) FILTER (WHERE (sp.bucket_type = 'width' AND l.width = sp.bucket) OR (sp.bucket_type = 'side' AND l.run_location = sp.bucket)) * 1.0
                  / COUNT(*) >= sp.league_share + 0.04 THEN 'Hit' ELSE 'Miss' END
    FROM m
    JOIN scout_picks sp ON sp.season = m.season AND sp.week = m.week AND sp.team = m.team AND sp.pick = 'run_lean'
    LEFT JOIN lean_game l ON l.season = m.season AND l.week = m.week AND l.team = m.team
    GROUP BY m.season, m.week, m.team, sp.share, sp.bucket, sp.bucket_type, sp.league_share
),

-- 6. 3rd & long -----------------------------------------------------------------
third AS (
    SELECT season, as_of_week AS week, team,
           MAX(n) FILTER (WHERE situation = 'third_long' AND metric = 'pass_rate') * 1.0
             / NULLIF(SUM(n) FILTER (WHERE situation IN ('third_short', 'third_medium', 'third_long') AND metric = 'pass_rate'), 0) AS long_share
    FROM tendency_ranks WHERE span = 'season'
    GROUP BY ALL
),

c_third AS (
    SELECT m.season, m.week, m.team, 7, 'defense', 'tendency', 'Third-down distance',
        concat(note_pct(t.long_share), ' of third downs 7+ to go (league ', note_pct(lg.lg), ')'),
        concat(g.long_n, ' of ', g.n, ' were 7+, ', g.conv, ' converted'),
        CASE WHEN g.n < 4 THEN 'Didn''t come up'
             WHEN (t.long_share > lg.lg) = (g.long_n * 1.0 / g.n > lg.lg) THEN 'Hit' ELSE 'Miss' END
    FROM m
    JOIN third t USING (season, week, team)
    JOIN (SELECT season, week, AVG(long_share) AS lg FROM third GROUP BY ALL) lg USING (season, week)
    JOIN (SELECT season, week, team, COUNT(*) AS n, COUNT(*) FILTER (WHERE ydstogo >= 7) AS long_n,
                 COUNT(*) FILTER (WHERE yards_gained >= ydstogo) AS conv
          FROM theirs WHERE down = 3 GROUP BY ALL) g USING (season, week, team)
    WHERE abs(t.long_share - lg.lg) >= 0.05
),

-- 7. Hot spot (warning) --------------------------------------------------------
c_hot AS (
    SELECT m.season, m.week, m.team, 8, 'defense', 'warning', 'Their most dangerous throws',
        concat(upper(note_area(sp.bucket, sp.most_often)[1]), note_area(sp.bucket, sp.most_often)[2:], ': ', note_yds(sp.yards_per_play), ' yards and ',
               note_epa(sp.epa_per_play), ' EPA per throw'),
        CASE WHEN COUNT(t.play_id) = 0 THEN 'No throws there'
             ELSE concat(COUNT(t.play_id), ' throws, ', CAST(SUM(t.yards_gained) AS INTEGER), ' yards, ',
                         note_epa(AVG(t.epa)), ' EPA each') END,
        CASE WHEN COUNT(t.play_id) < 2 THEN 'Didn''t come up'
             WHEN AVG(t.epa) > sp.league_epa THEN 'Called it' ELSE 'Held' END
    FROM m
    JOIN scout_picks sp ON sp.season = m.season AND sp.week = m.week AND sp.team = m.team AND sp.pick = 'hot_spot'
    LEFT JOIN theirs t ON t.season = m.season AND t.week = m.week AND t.team = m.team
         AND t.is_pass = 1 AND t.pass_location IS NOT NULL AND t.pass_length IS NOT NULL
         AND CASE sp.bucket_type
               WHEN 'lane' THEN t.pass_length || CASE WHEN t.pass_location = 'middle' THEN '_middle' ELSE '_outside' END
               ELSE t.pass_length || '_' || t.pass_location END = sp.bucket
    GROUP BY m.season, m.week, m.team, sp.bucket, sp.most_often, sp.yards_per_play, sp.epa_per_play, sp.league_epa
),

-- 8. Late in halves, tied or trailing --------------------------------------------
c_late AS (
    SELECT m.season, m.week, m.team, 9, 'defense', 'tendency', 'Late in halves, tied or trailing',
        concat(CASE WHEN s.epa_rank <= 8 THEN 'Dangerous: ' ELSE 'Struggle: ' END, note_ord(s.epa_rank), ' at ',
               note_epa(s.epa_per_play), ' EPA per play (', note_epa(s.epa_wo_best), ' without the best play)'),
        CASE WHEN g.n IS NULL THEN 'No late-half snaps tied or trailing'
             WHEN g.n < 4 THEN concat(g.n, CASE WHEN g.n = 1 THEN ' play' ELSE ' plays' END, ', ', note_epa(g.med), ' median EPA')
             ELSE concat(g.n, ' plays: median ', note_epa(g.med), ' EPA, best play ', note_epa(g.best), ', ',
                         note_epa(g.wo_best), ' per play without it') END,
        CASE WHEN COALESCE(g.n, 0) < 4 THEN 'Didn''t come up'
             WHEN (s.epa_rank <= 8) = (g.med > 0) THEN 'Hit' ELSE 'Miss' END
    FROM m
    JOIN score_splits s ON s.season = m.season AND s.as_of_week = m.week AND s.team = m.team
         AND s.side = 'offense' AND s.situation = 'two_minute' AND s.score_state = 'not_leading'
         AND s.plays >= 20 AND (s.epa_rank <= 8 OR s.epa_rank >= s.ranked_teams - 7)
    LEFT JOIN (SELECT season, week, team, COUNT(*) AS n, MEDIAN(epa) AS med, MAX(epa) AS best,
                      CASE WHEN COUNT(*) > 1 THEN (SUM(epa) - MAX(epa)) / (COUNT(*) - 1) END AS wo_best
               FROM theirs WHERE is_two_minute AND score_differential <= 0 GROUP BY ALL) g
      ON g.season = m.season AND g.week = m.week AND g.team = m.team
),

-- 9 and 10. Their early-down run and pass defense --------------------------------
c_defense AS (
    SELECT m.season, m.week, m.team, CASE d.play_type WHEN 'run' THEN 10 ELSE 11 END, 'offense', 'tendency',
        CASE d.play_type WHEN 'run' THEN 'Their early-down run defense' ELSE 'Their early-down pass defense' END,
        concat(CASE WHEN d.rank_allowed <= 10 THEN 'Soft: ' ELSE 'Stout: ' END, note_epa(d.epa_allowed), ' EPA per ',
               CASE d.play_type WHEN 'run' THEN 'run' ELSE 'dropback' END, ' allowed (', note_most(d.rank_allowed, d.teams), ')'),
        concat('We had ', note_epa(g.epa), ' EPA and ', note_yds(g.ypp), ' yards per play on ', g.n, ' (league ', note_epa(d.league_epa), ')'),
        CASE WHEN g.n < 6 THEN 'Didn''t come up'
             WHEN (d.rank_allowed <= 10) = (g.epa > d.league_epa) THEN 'Hit' ELSE 'Miss' END
    FROM m
    JOIN ds d ON d.season = m.season AND d.week = m.week AND d.team = m.team AND d.situation = 'early_down'
             AND (d.rank_allowed <= 10 OR d.rank_allowed >= d.teams - 9)
    JOIN (SELECT season, week, team, CASE WHEN is_pass = 1 THEN 'pass' ELSE 'run' END AS play_type,
                 COUNT(*) AS n, AVG(epa) AS epa, AVG(yards_gained) AS ypp
          FROM ours WHERE is_early_down AND is_neutral_wp GROUP BY ALL) g
      ON g.season = m.season AND g.week = m.week AND g.team = m.team AND g.play_type = d.play_type
),

-- 11. The position they cover worst (warning, our side) --------------------------
c_position AS (
    SELECT m.season, m.week, m.team, 12, 'offense', 'warning', concat('Target their coverage of ', note_pos(v.position)),
        concat(note_epa(v.epa_per_target), ' EPA per target allowed (', note_most(v.rank_allowed, v.teams), ')'),
        concat(COUNT(o.play_id), ' targets, ', CAST(COALESCE(SUM(o.yards_gained), 0) AS INTEGER), ' yards, ',
               note_epa(COALESCE(SUM(o.epa), 0)), ' EPA'),
        CASE WHEN COUNT(o.play_id) < 3 THEN 'Didn''t come up'
             WHEN AVG(o.epa) > v.league_epa_per_target THEN 'Hit' ELSE 'Miss' END
    FROM m
    JOIN (SELECT *, ROW_NUMBER() OVER (PARTITION BY season, as_of_week, defense ORDER BY rank_allowed, position) AS pick_no
          FROM defense_vs_position WHERE targets >= 20) v
      ON v.season = m.season AND v.as_of_week = m.week AND v.defense = m.team AND v.pick_no = 1
    LEFT JOIN (SELECT o.*, CASE WHEN pl.position IN ('FB', 'HB') THEN 'RB' ELSE pl.position END AS position
               FROM ours o JOIN (SELECT DISTINCT gsis_id, position FROM raw_players) pl ON pl.gsis_id = o.receiver_id
               WHERE o.is_pass = 1) o
      ON o.season = m.season AND o.week = m.week AND o.team = m.team AND o.position = v.position
    GROUP BY m.season, m.week, m.team, v.position, v.epa_per_target, v.rank_allowed, v.teams, v.league_epa_per_target
),

-- 12. Run lanes against them ---------------------------------------------------
our_lanes AS (
    SELECT season, week, team,
           CASE WHEN run_location = 'middle' OR run_gap = 'guard' THEN 'inside'
                WHEN run_gap = 'tackle' THEN 'off_tackle' ELSE 'outside' END AS width,
           COUNT(*) AS n, AVG(yards_gained) AS ypc, AVG(epa) AS epa
    FROM ours
    WHERE is_run = 1 AND is_early_down AND run_location IS NOT NULL AND (run_location = 'middle' OR run_gap IS NOT NULL)
    GROUP BY ALL
),

c_lanes AS (
    SELECT m.season, m.week, m.team, 13, 'offense', 'tendency', 'Run lanes against them',
        concat('Most vulnerable ', note_bucket(s.bucket), ' (', note_yds(s.yards_per_play), ' a carry), toughest ',
               note_bucket(h.bucket), ' (', note_yds(h.yards_per_play), ')'),
        concat(upper(note_bucket(s.bucket)[1]), note_bucket(s.bucket)[2:], ': ', COALESCE(ls.n, 0), ' runs', CASE WHEN ls.n > 0 THEN concat(', ', note_yds(ls.ypc), ' a carry') ELSE '' END,
               '; ', note_bucket(h.bucket), ': ', COALESCE(lh.n, 0), ' runs', CASE WHEN lh.n > 0 THEN concat(', ', note_yds(lh.ypc), ' a carry') ELSE '' END),
        -- yards and EPA both have to agree for a Hit or a Miss
        CASE WHEN COALESCE(ls.n, 0) < 2 OR COALESCE(lh.n, 0) < 2 THEN 'Didn''t come up'
             WHEN ls.epa > lh.epa AND ls.ypc > lh.ypc THEN 'Hit'
             WHEN ls.epa <= lh.epa AND ls.ypc <= lh.ypc THEN 'Miss' ELSE 'Mixed' END
    FROM m
    JOIN scout_picks s ON s.season = m.season AND s.week = m.week AND s.team = m.team AND s.pick = 'soft_lane'
    JOIN scout_picks h ON h.season = m.season AND h.week = m.week AND h.team = m.team AND h.pick = 'hard_lane'
    LEFT JOIN our_lanes ls ON ls.season = m.season AND ls.week = m.week AND ls.team = m.team AND ls.width = s.bucket
    LEFT JOIN our_lanes lh ON lh.season = m.season AND lh.week = m.week AND lh.team = m.team AND lh.width = h.bucket
    WHERE s.bucket <> h.bucket
),

-- 13. Red-zone throws (warning, our side) -----------------------------------------
c_redzone AS (
    SELECT m.season, m.week, m.team, 14, 'offense', 'warning', 'Throw it in the red zone',
        concat(note_epa(d.epa_allowed), ' per dropback allowed inside the 20 (', note_most(d.rank_allowed, d.teams), ')'),
        CASE WHEN g.n IS NULL THEN 'No red-zone dropbacks'
             ELSE concat(g.n, ' dropbacks, ', note_epa(g.epa), ' EPA each, ', g.td, ' TD') END,
        CASE WHEN COALESCE(g.n, 0) < 3 THEN 'Didn''t come up' WHEN g.epa > d.league_epa THEN 'Hit' ELSE 'Miss' END
    FROM m
    JOIN ds d ON d.season = m.season AND d.week = m.week AND d.team = m.team AND d.situation = 'red_zone'
             AND d.play_type = 'pass' AND d.plays >= 15 AND d.rank_allowed <= 8
    LEFT JOIN (SELECT season, week, team, COUNT(*) AS n, AVG(epa) AS epa,
                      COUNT(*) FILTER (WHERE yards_gained >= yardline_100) AS td   -- gained the whole field left
               FROM ours WHERE is_red_zone AND is_pass = 1 GROUP BY ALL) g
      ON g.season = m.season AND g.week = m.week AND g.team = m.team
),

calls AS (
    SELECT * FROM c_identity UNION ALL SELECT * FROM c_works UNION ALL SELECT * FROM c_target
    UNION ALL SELECT * FROM c_lean UNION ALL SELECT * FROM c_third UNION ALL SELECT * FROM c_hot
    UNION ALL SELECT * FROM c_late UNION ALL SELECT * FROM c_defense UNION ALL SELECT * FROM c_position
    UNION ALL SELECT * FROM c_lanes UNION ALL SELECT * FROM c_redzone
)

SELECT m.season, m.week, m.team, m.opponent, m.gameday, m.is_home, m.team_score, m.opponent_score,
       CASE WHEN m.week = 1 THEN 'last_season' ELSE 'in_season' END AS basis,   -- Week 1 is scouted from last season
       c.call_no, c.side, c.kind, c.call, c.said, c.happened, c.verdict,
       CASE WHEN c.verdict = 'Called it' THEN 'Hurt us' END AS outcome   -- what it did on the field
FROM calls c
JOIN m USING (season, week, team);
