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
-- Attack calls on our side that are graded on EPA (soft/stout early-down
-- defense, the position they cover worst, red-zone throws) are graded on net
-- points: our EPA in that part of the game minus what our offense usually gets
-- on the same number of plays (its season to date, blended with 30 plays of
-- league average). Within 1.5 points either way = No real impact (set Nov 24,
-- 2026; reassess at season's end); one big play
-- can still decide it. (Changed Nov 24, 2026.)
-- Didn't come up = too few plays in the game to say (thresholds below).
-- Warnings need only one play: a threat or soft spot is about what a play
-- does, and one 19-yard, +0.91 EPA throw into their hot spot is the threat
-- showing up, not "didn't come up". Net-point grades already absorb small
-- samples (a single play rarely moves 1.5 points). (Changed Nov 25, 2026:
-- the hot spot needed 2 throws, red-zone and position calls 3 plays, which
-- hid 1-2 play results of up to 4 points.)
-- Calls with no clear lean that week are left out, as they are in the notes.
-- Week 1 is scouted from last season's full regular season (basis =
-- 'last_season'), so its grades are kept apart from the in-season rates.

CREATE OR REPLACE MACRO net_points(sum_epa, n, prior_sum, prior_n, league) AS
    sum_epa - n * (COALESCE(prior_sum, 0) + 30 * league) / (COALESCE(prior_n, 0) + 30);
CREATE OR REPLACE MACRO note_net(x) AS
    CASE WHEN round(x, 1) >= 0 THEN '+' ELSE '−' END || CAST(round(abs(x), 1) AS VARCHAR) || ' points vs. our usual';
CREATE OR REPLACE MACRO net_verdict(net, called_soft) AS CASE
    WHEN abs(net) < 1.5 THEN 'No real impact'
    WHEN (net > 0) = called_soft THEN 'Hit' ELSE 'Miss' END;

-- Locked at kickoff (Nov 25, 2026): what each call said, and every pregame
-- number its grade uses, is kept in site/data/report-card-locks-<season>.json
-- by export_report_card_locks() in R/pipeline.R. Each run rewrites the rows of
-- games that haven't kicked off; once a game kicks off its rows are never
-- rewritten. nflverse revises play-by-play after games (EPA, run gaps), so
-- without the lock "We said" drifted from the notes as published (week 11
-- NO: deep middle +0.93 EPA in the notes, +0.99 in the archive). Games graded
-- before the lock existed (2026 weeks 1-11) have no rows and are recomputed.
--
-- report_card_pregame_fresh  every call for every scheduled game, from today's data
-- report_card_pregame        a game's locked rows where it has them, else fresh
-- report_card                pregame call x that game's plays -> verdict

CREATE OR REPLACE TABLE report_card_pregame_fresh AS
WITH
    -- Week 1 reads last season's full year (27_week1_carryover.sql)
    tendency_ranks      AS (FROM with_week1('main.tendency_ranks')),
    top_target          AS (FROM with_week1('main.top_target')),
    defense_splits      AS (FROM with_week1('main.defense_splits')),
    defense_vs_position AS (FROM with_week1('main.defense_vs_position')),
    score_splits        AS (FROM with_week1('main.score_splits')),
g AS (   -- every scheduled game with as-of numbers for the offense ("team")
    SELECT g.season, g.week, g.team, g.opponent, g.game_id
    FROM stg_team_games g
    WHERE EXISTS (SELECT 1 FROM tendency_ranks t WHERE t.season = g.season AND t.as_of_week = g.week AND t.team = g.team)
),

-- our offense (the team that plays "team") in the games before this one: what "our usual" means
our_prior AS (
    SELECT g.season, g.week, g.team, p.* EXCLUDE (season, week, team)
    FROM g JOIN stg_plays p ON p.season = g.season AND p.team = g.opponent AND p.week < g.week
),

tr AS (
    SELECT season, as_of_week AS week, team, situation, metric, value, league_rank, league_teams, n, league_avg
    FROM tendency_ranks WHERE span = 'season'
),

ds AS (
    SELECT season, as_of_week AS week, defense AS team, situation, play_type, plays, epa_allowed, rank_allowed, teams, league_epa,
           epa_vs_expected, rank_allowed_adj
    FROM defense_splits WHERE span = 'season'
),

-- 1. Early-down identity
p_identity AS (
    SELECT g.season, g.week, g.team, 1 AS call_no, 'defense' AS side, 'tendency' AS kind, 'Early-down identity' AS call,
        CASE WHEN t.league_rank >= t.league_teams - 7 THEN concat('Run-first: ', note_ord(t.league_rank), ' in early-down pass rate over expected')
             WHEN t.league_rank <= 8 THEN concat('Pass-first: ', note_ord(t.league_rank), ' in early-down pass rate over expected')
             ELSE concat('Balanced: ', note_value('proe', t.value), ' over expected (', note_ord(t.league_rank), ')') END AS said,
        t.league_rank AS p_rank, t.league_teams AS p_teams
    FROM g JOIN tr t ON t.season = g.season AND t.week = g.week AND t.team = g.team AND t.situation = 'early_down' AND t.metric = 'proe'
),

-- 2 and 3. Whether their early-down runs / dropbacks work
p_works AS (
    SELECT g.season, g.week, g.team, CASE t.metric WHEN 'epa_run' THEN 2 ELSE 3 END AS call_no, 'defense' AS side, 'tendency' AS kind,
        CASE t.metric WHEN 'epa_run' THEN 'Early-down runs' ELSE 'Early-down dropbacks' END AS call,
        concat(CASE WHEN t.league_rank <= 10 THEN 'They work: ' ELSE 'They don''t work: ' END,
               note_epa(t.value), ' EPA per play (', note_ord(t.league_rank), ')') AS said,
        t.league_rank AS p_rank, t.league_teams AS p_teams, t.league_avg AS p_num
    FROM g JOIN tr t ON t.season = g.season AND t.week = g.week AND t.team = g.team AND t.situation = 'early_down'
             AND t.metric IN ('epa_run', 'epa_pass') AND (t.league_rank <= 10 OR t.league_rank >= t.league_teams - 9)
),

-- 4 and 5. Top target: volume (tendency) and production (warning)
p_target AS (
    SELECT g.season, g.week, g.team, 4 AS call_no, 'defense' AS side, 'tendency' AS kind, concat(tt.receiver_name, '''s target share') AS call,
        concat(note_pct(tt.share), ' of their targets') AS said,
        tt.receiver_id AS p_id, tt.receiver_name AS p_name, tt.share AS p_num
    FROM g JOIN top_target tt ON tt.season = g.season AND tt.as_of_week = g.week AND tt.team = g.team
    WHERE tt.share >= 0.22 AND tt.targets >= 20
    UNION ALL
    SELECT g.season, g.week, g.team, 5, 'defense', 'warning', concat('Take away ', tt.receiver_name),
        concat(note_epa(tt.epa_per_target), ' EPA per target; everyone else ', note_epa(tt.others_epa_per_target)),
        tt.receiver_id, tt.receiver_name, NULL
    FROM g JOIN top_target tt ON tt.season = g.season AND tt.as_of_week = g.week AND tt.team = g.team
    WHERE tt.share >= 0.22 AND tt.targets >= 20 AND tt.epa_per_target - tt.others_epa_per_target >= 0.30
),

-- 6. Early-down run lean
p_lean AS (
    SELECT g.season, g.week, g.team, 6 AS call_no, 'defense' AS side, 'tendency' AS kind, 'Early-down run direction' AS call,
        concat(note_pct(sp.share), ' of early-down runs ', note_bucket(sp.bucket), ' (league ', note_pct(sp.league_share), ')') AS said,
        sp.bucket AS p_bucket, sp.bucket_type AS p_bucket_type, sp.league_share AS p_num
    FROM g JOIN scout_picks sp ON sp.season = g.season AND sp.week = g.week AND sp.team = g.team AND sp.pick = 'run_lean'
),

-- 7. 3rd & long: dropped Nov 24, 2026. How often a team faces 3rd & 7+ follows
-- from its early downs that week, not a habit: split-half correlation about 0 in
-- 2025-26, 54% right in 2026, and calls 10+ points off the league went 36-36.
-- Third-and-long conversion rate and the 3rd & 7+ top target were tested as
-- replacements and didn't hold either. Call number 7 stays unused.

-- 8. Hot spot (warning)
p_hot AS (
    SELECT g.season, g.week, g.team, 8 AS call_no, 'defense' AS side, 'warning' AS kind, 'Their most dangerous throws' AS call,
        concat(upper(note_area(sp.bucket, sp.most_often)[1]), note_area(sp.bucket, sp.most_often)[2:], ': ', note_yds(sp.yards_per_play), ' yards and ',
               note_epa(sp.epa_per_play), ' EPA per throw') AS said,
        sp.bucket AS p_bucket, sp.bucket_type AS p_bucket_type, sp.most_often AS p_bucket2, sp.league_epa AS p_num
    FROM g JOIN scout_picks sp ON sp.season = g.season AND sp.week = g.week AND sp.team = g.team AND sp.pick = 'hot_spot'
),

-- 9. Late in halves, tied or trailing
p_late AS (
    SELECT g.season, g.week, g.team, 9 AS call_no, 'defense' AS side, 'tendency' AS kind, 'Late in halves, tied or trailing' AS call,
        concat(CASE WHEN s.epa_rank <= 8 THEN 'Dangerous: ' ELSE 'Struggle: ' END, note_ord(s.epa_rank), ' at ',
               note_epa(s.epa_per_play), ' EPA per play (', note_epa(s.epa_wo_best), ' without the best play)') AS said,
        s.epa_rank <= 8 AS p_flag
    FROM g JOIN score_splits s ON s.season = g.season AND s.as_of_week = g.week AND s.team = g.team
         AND s.side = 'offense' AND s.situation = 'two_minute' AND s.score_state = 'not_leading'
         AND s.plays >= 20 AND (s.epa_rank <= 8 OR s.epa_rank >= s.ranked_teams - 7)
),

-- 10 and 11. Their early-down run and pass defense
-- Only when the evidence is strong: top or bottom 5 after adjusting for the
-- offenses they've faced (rank_allowed_adj). Top/bottom 10 on raw EPA hit 53%;
-- top/bottom 5 adjusted hit 60% in a weeks 3-11 2026 backtest. Not called in
-- weeks 2-4: with 1-3 games of data the pick was a coin flip in both 2025
-- (48%) and 2026 (52%) in weeks 3-4. Week 1 (last season's full year) stays.
p_defense AS (
    SELECT g.season, g.week, g.team, CASE d.play_type WHEN 'run' THEN 10 ELSE 11 END AS call_no, 'offense' AS side, 'tendency' AS kind,
        CASE d.play_type WHEN 'run' THEN 'Their early-down run defense' ELSE 'Their early-down pass defense' END AS call,
        concat(CASE WHEN d.rank_allowed_adj <= 5 THEN 'Soft: ' ELSE 'Stout: ' END, note_epa(d.epa_vs_expected), ' EPA per ',
               CASE d.play_type WHEN 'run' THEN 'run' ELSE 'dropback' END, ' vs. what offenses usually get (',
               note_most(d.rank_allowed_adj, d.teams), ')') AS said,
        d.rank_allowed_adj <= 5 AS p_flag, d.league_epa AS p_num, pr.sum_epa AS p_prior_sum, pr.n AS p_prior_n
    FROM g
    JOIN ds d ON d.season = g.season AND d.week = g.week AND d.team = g.team AND d.situation = 'early_down'
             AND (d.rank_allowed_adj <= 5 OR d.rank_allowed_adj >= d.teams - 4)
             AND (g.week = 1 OR g.week >= 5)
    LEFT JOIN (SELECT season, week, team, CASE WHEN is_pass = 1 THEN 'pass' ELSE 'run' END AS play_type,
                      COUNT(*) AS n, SUM(COALESCE(epa, 0)) AS sum_epa
               FROM our_prior WHERE is_early_down AND is_neutral_wp GROUP BY ALL) pr
      ON pr.season = g.season AND pr.week = g.week AND pr.team = g.team AND pr.play_type = d.play_type
),

-- 12. The position they cover worst (warning, our side)
p_position AS (
    SELECT g.season, g.week, g.team, 12 AS call_no, 'offense' AS side, 'warning' AS kind, concat('Target their coverage of ', note_pos(v.position)) AS call,
        concat(note_epa(v.epa_per_target), ' EPA per target allowed (', note_most(v.rank_allowed, v.teams), ')') AS said,
        v.position AS p_bucket, v.league_epa_per_target AS p_num, pr.sum_epa AS p_prior_sum, pr.n AS p_prior_n
    FROM g
    JOIN (SELECT *, ROW_NUMBER() OVER (PARTITION BY season, as_of_week, defense ORDER BY rank_allowed, position) AS pick_no
          FROM defense_vs_position WHERE targets >= 20) v
      ON v.season = g.season AND v.as_of_week = g.week AND v.defense = g.team AND v.pick_no = 1
    LEFT JOIN (SELECT o.season, o.week, o.team, CASE WHEN pl.position IN ('FB', 'HB') THEN 'RB' ELSE pl.position END AS position,
                      COUNT(*) AS n, SUM(COALESCE(o.epa, 0)) AS sum_epa
               FROM our_prior o JOIN (SELECT DISTINCT gsis_id, position FROM raw_players) pl ON pl.gsis_id = o.receiver_id
               WHERE o.is_pass = 1 GROUP BY ALL) pr
      ON pr.season = g.season AND pr.week = g.week AND pr.team = g.team AND pr.position = v.position
),

-- 13. Run lanes against them. Picked on EPA per run allowed, so the line
-- shows EPA and its rank first (yards can point the other way: week 11 NO,
-- inside 4.2 a carry and 4th-most EPA, around end 5.0 but 14th-fewest).
p_lanes AS (
    SELECT g.season, g.week, g.team, 13 AS call_no, 'offense' AS side, 'tendency' AS kind, 'Run lanes against them' AS call,
        concat('Most vulnerable ', note_bucket(s.bucket), ' (', note_epa(s.epa_per_play), ' EPA a carry, ', note_most(s.epa_rank, s.ranked_teams),
               '; ', note_yds(s.yards_per_play), ' yards), toughest ',
               note_bucket(h.bucket), ' (', note_epa(h.epa_per_play), ', ', note_most(h.epa_rank, h.ranked_teams),
               '; ', note_yds(h.yards_per_play), ' yards)') AS said,
        s.bucket AS p_bucket, h.bucket AS p_bucket2
    FROM g
    JOIN scout_picks s ON s.season = g.season AND s.week = g.week AND s.team = g.team AND s.pick = 'soft_lane'
    JOIN scout_picks h ON h.season = g.season AND h.week = g.week AND h.team = g.team AND h.pick = 'hard_lane'
    WHERE s.bucket <> h.bucket
),

-- 14. Red-zone throws (warning, our side)
p_redzone AS (
    SELECT g.season, g.week, g.team, 14 AS call_no, 'offense' AS side, 'warning' AS kind, 'Throw it in the red zone' AS call,
        concat(note_epa(d.epa_allowed), ' per dropback allowed inside the 20 (', note_most(d.rank_allowed, d.teams), ')') AS said,
        d.league_epa AS p_num, pr.sum_epa AS p_prior_sum, pr.n AS p_prior_n
    FROM g
    JOIN ds d ON d.season = g.season AND d.week = g.week AND d.team = g.team AND d.situation = 'red_zone'
             AND d.play_type = 'pass' AND d.plays >= 15 AND d.rank_allowed <= 8
    LEFT JOIN (SELECT season, week, team, COUNT(*) AS n, SUM(COALESCE(epa, 0)) AS sum_epa
               FROM our_prior WHERE is_red_zone AND is_pass = 1 GROUP BY ALL) pr
      ON pr.season = g.season AND pr.week = g.week AND pr.team = g.team
),

calls AS (
    FROM p_identity UNION ALL BY NAME FROM p_works UNION ALL BY NAME FROM p_target
    UNION ALL BY NAME FROM p_lean UNION ALL BY NAME FROM p_hot UNION ALL BY NAME FROM p_late
    UNION ALL BY NAME FROM p_defense UNION ALL BY NAME FROM p_position UNION ALL BY NAME FROM p_lanes
    UNION ALL BY NAME FROM p_redzone
)

SELECT g.season, g.week, g.team, g.game_id, c.call_no, c.side, c.kind, c.call, c.said,
       CAST(c.p_rank AS INTEGER) AS p_rank, CAST(c.p_teams AS INTEGER) AS p_teams, CAST(c.p_flag AS BOOLEAN) AS p_flag,
       CAST(c.p_id AS VARCHAR) AS p_id, CAST(c.p_name AS VARCHAR) AS p_name,
       CAST(c.p_bucket AS VARCHAR) AS p_bucket, CAST(c.p_bucket_type AS VARCHAR) AS p_bucket_type,
       CAST(c.p_bucket2 AS VARCHAR) AS p_bucket2, CAST(c.p_num AS DOUBLE) AS p_num,
       CAST(c.p_prior_sum AS DOUBLE) AS p_prior_sum, CAST(c.p_prior_n AS INTEGER) AS p_prior_n
FROM calls c JOIN g USING (season, week, team);

-- raw_report_card_locks is loaded from site/data/report-card-locks-*.json
-- (load_report_card_locks() in R/pipeline.R; empty before the first lock).
CREATE OR REPLACE TABLE report_card_pregame AS
SELECT l.* EXCLUDE (locked_at), TRUE AS locked, l.locked_at
FROM raw_report_card_locks l
UNION ALL BY NAME
SELECT f.*, FALSE AS locked, CAST(NULL AS VARCHAR) AS locked_at
FROM report_card_pregame_fresh f
WHERE NOT EXISTS (SELECT 1 FROM raw_report_card_locks l WHERE l.game_id = f.game_id AND l.team = f.team);

CREATE OR REPLACE TABLE report_card AS
WITH
m AS (
    SELECT g.season, g.week, g.team, g.opponent, g.game_id, g.gameday, g.is_home,
           g.team_score, g.opponent_score
    FROM stg_team_games g
    WHERE g.is_complete
      AND EXISTS (SELECT 1 FROM report_card_pregame c WHERE c.season = g.season AND c.week = g.week AND c.team = g.team)
),

pc AS (SELECT c.* FROM report_card_pregame c JOIN m USING (season, week, team)),

-- Fumbles after the catch (added Nov 27, 2026): a completed pass is graded on
-- its value up to the moment the receiver lost the ball, so a lost fumble
-- doesn't turn an open receiver into a coverage "win" (week 12 of 2026: a
-- 5-yard catch by an open Bears tight end at Detroit's 22, +0.02 EPA before
-- the fumble and -3.83 after, flipped "target their tight ends" to a Miss).
-- Interceptions, sacks and run fumbles still count in full.
theirs AS (   -- their offense in the graded game
    SELECT m.season, m.week, m.team, p.* EXCLUDE (season, week, team) REPLACE (p.epa_before_fumble AS epa)
    FROM m JOIN stg_plays p ON p.game_id = m.game_id AND p.team = m.team
),

ours AS (     -- our offense against their defense in the graded game
    SELECT m.season, m.week, m.team, p.* EXCLUDE (season, week, team) REPLACE (p.epa_before_fumble AS epa)
    FROM m JOIN stg_plays p ON p.game_id = m.game_id AND p.team = m.opponent
),

-- 1. Early-down identity -------------------------------------------------------
-- Graded only on early downs within one score (7 points). A team up or down
-- big runs or throws because of the score, not its identity: in week 10 of
-- 2026, 4 of the 12 misses on all neutral downs were blowouts.
c_identity AS (
    SELECT c.season, c.week, c.team, c.call_no, c.side, c.kind, c.call, c.said,
        CASE WHEN COALESCE(g.n, 0) < 10
             THEN concat('Only ', COALESCE(g.n, 0), ' of ', COALESCE(a.n, 0), ' early downs came with the game within 7 points: too few to grade')
             ELSE concat(CASE WHEN g.proe < 0 THEN 'Ran ' ELSE 'Passed ' END, CAST(abs(round(100 * g.proe)) AS INTEGER),
                         ' pts more than expected on ', g.n, ' early downs within one score') END AS happened,
        CASE WHEN COALESCE(g.n, 0) < 10 THEN 'Didn''t come up'
             WHEN c.p_rank >= c.p_teams - 7 THEN CASE WHEN g.proe < 0 THEN 'Hit' ELSE 'Miss' END
             WHEN c.p_rank <= 8 THEN CASE WHEN g.proe > 0 THEN 'Hit' ELSE 'Miss' END
             ELSE CASE WHEN abs(g.proe) <= 0.07 THEN 'Hit' ELSE 'Miss' END END AS verdict
    FROM pc c
    LEFT JOIN (SELECT season, week, team, COUNT(*) AS n, AVG(is_pass - xpass) AS proe
               FROM theirs WHERE is_early_down AND is_neutral_wp AND xpass IS NOT NULL
                 AND abs(score_differential) <= 7 GROUP BY ALL) g USING (season, week, team)
    LEFT JOIN (SELECT season, week, team, COUNT(*) AS n
               FROM theirs WHERE is_early_down AND xpass IS NOT NULL GROUP BY ALL) a USING (season, week, team)
    WHERE c.call_no = 1
),

-- 2. Whether their early-down runs / dropbacks work ----------------------------
-- 10 plays (was 6; changed Nov 25, 2026): EPA per play on fewer is noise.
c_works AS (
    SELECT c.season, c.week, c.team, c.call_no, c.side, c.kind, c.call, c.said,
        concat(note_epa(g.epa), ' EPA and ', note_yds(g.ypp), ' yards per play on ', g.n, ' (league ', note_epa(c.p_num), ')'),
        CASE WHEN g.n < 10 THEN 'Didn''t come up'
             WHEN (c.p_rank <= 10) = (g.epa > c.p_num) THEN 'Hit' ELSE 'Miss' END
    FROM pc c
    JOIN (SELECT season, week, team, CASE WHEN is_pass = 1 THEN 3 ELSE 2 END AS call_no,
                 COUNT(*) AS n, AVG(epa) AS epa, AVG(yards_gained) AS ypp
          FROM theirs WHERE is_early_down AND is_neutral_wp GROUP BY ALL) g USING (season, week, team, call_no)
    WHERE c.call_no IN (2, 3)
),

-- 3 and 4. Top target: volume (tendency) and production (warning) --------------
tt_game AS (
    SELECT c.season, c.week, c.team, c.call_no, COUNT(t.play_id) AS team_targets,
           COUNT(t.play_id) FILTER (WHERE t.receiver_id = c.p_id) AS targets,
           COALESCE(SUM(COALESCE(t.yards_gained, 0)) FILTER (WHERE t.receiver_id = c.p_id), 0) AS yards,
           COALESCE(SUM(COALESCE(t.epa, 0)) FILTER (WHERE t.receiver_id = c.p_id), 0) AS epa
    FROM pc c
    JOIN theirs t ON t.season = c.season AND t.week = c.week AND t.team = c.team
         AND t.is_pass = 1 AND t.receiver_id IS NOT NULL
    WHERE c.call_no IN (4, 5)
    GROUP BY ALL
),

-- The top target sat out the game (gameday inactive or on reserve), so the
-- call says nothing about the scouting: graded "Didn't come up", not Miss.
tt_out AS (
    SELECT DISTINCT c.season, c.week, c.team
    FROM pc c
    JOIN raw_rosters_weekly ro
      ON CAST(ro.season AS INTEGER) = c.season AND CAST(ro.week AS INTEGER) = c.week AND ro.gsis_id = c.p_id
    WHERE c.call_no IN (4, 5) AND ro.status IN ('INA', 'RES')
),

c_target AS (
    SELECT c.season, c.week, c.team, c.call_no, c.side, c.kind, c.call, c.said,
        CASE WHEN o.team IS NOT NULL THEN concat(c.p_name, ' didn''t play')
             WHEN c.call_no = 4 THEN concat(g.targets, ' of ', g.team_targets, ' (', note_pct(g.targets * 1.0 / g.team_targets), ')')
             ELSE concat(g.targets, ' targets, ', CAST(g.yards AS INTEGER), ' yards, ', note_epa(g.epa), ' EPA') END,
        CASE WHEN c.call_no = 4 THEN
                CASE WHEN g.team_targets < 10 OR o.team IS NOT NULL THEN 'Didn''t come up'
                     WHEN g.targets * 1.0 / g.team_targets >= c.p_num - 0.08 THEN 'Hit' ELSE 'Miss' END
             ELSE
                CASE WHEN g.targets = 0 OR o.team IS NOT NULL THEN 'Didn''t come up'   -- likely out, not covered
                     WHEN g.epa / g.targets <= 0.10 THEN 'Held' ELSE 'Called it' END END
    FROM pc c
    JOIN tt_game g USING (season, week, team, call_no)
    LEFT JOIN tt_out o USING (season, week, team)
    WHERE c.call_no IN (4, 5)
),

-- 5. Early-down run lean -------------------------------------------------------
-- 10 runs (was 6; changed Nov 25, 2026): 6-9 runs went 5-5 in 2026.
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
    SELECT c.season, c.week, c.team, c.call_no, c.side, c.kind, c.call, c.said,
        concat(COUNT(l.width) FILTER (WHERE (c.p_bucket_type = 'width' AND l.width = c.p_bucket) OR (c.p_bucket_type = 'side' AND l.run_location = c.p_bucket)),
               ' of ', COUNT(l.width), ' runs'),
        CASE WHEN COUNT(l.width) < 10 THEN 'Didn''t come up'
             WHEN COUNT(l.width) FILTER (WHERE (c.p_bucket_type = 'width' AND l.width = c.p_bucket) OR (c.p_bucket_type = 'side' AND l.run_location = c.p_bucket)) * 1.0
                  / COUNT(l.width) >= c.p_num + 0.04 THEN 'Hit' ELSE 'Miss' END
    FROM pc c
    LEFT JOIN lean_game l ON l.season = c.season AND l.week = c.week AND l.team = c.team
    WHERE c.call_no = 6
    GROUP BY c.season, c.week, c.team, c.call_no, c.side, c.kind, c.call, c.said, c.p_bucket, c.p_bucket_type, c.p_num
),

-- 7. Hot spot (warning) --------------------------------------------------------
c_hot AS (
    SELECT c.season, c.week, c.team, c.call_no, c.side, c.kind, c.call, c.said,
        CASE WHEN COUNT(t.play_id) = 0 THEN 'No throws there'
             ELSE concat(COUNT(t.play_id), CASE WHEN COUNT(t.play_id) = 1 THEN ' throw, ' ELSE ' throws, ' END, CAST(SUM(t.yards_gained) AS INTEGER), ' yards, ',
                         note_epa(AVG(t.epa)), CASE WHEN COUNT(t.play_id) = 1 THEN ' EPA' ELSE ' EPA each' END) END,
        CASE WHEN COUNT(t.play_id) = 0 THEN 'Didn''t come up'
             WHEN AVG(t.epa) > c.p_num THEN 'Called it' ELSE 'Held' END
    FROM pc c
    LEFT JOIN theirs t ON t.season = c.season AND t.week = c.week AND t.team = c.team
         AND t.is_pass = 1 AND t.pass_location IS NOT NULL AND t.pass_length IS NOT NULL
         AND CASE c.p_bucket_type
               WHEN 'lane' THEN t.pass_length || CASE WHEN t.pass_location = 'middle' THEN '_middle' ELSE '_outside' END
               ELSE t.pass_length || '_' || t.pass_location END = c.p_bucket
    WHERE c.call_no = 8
    GROUP BY c.season, c.week, c.team, c.call_no, c.side, c.kind, c.call, c.said, c.p_num
),

-- 8. Late in halves, tied or trailing --------------------------------------------
-- 6 plays (was 4; changed Nov 25, 2026): 4-7 plays hit 73%, 8+ hit 45% in 2026.
c_late AS (
    SELECT c.season, c.week, c.team, c.call_no, c.side, c.kind, c.call, c.said,
        CASE WHEN g.n IS NULL THEN 'No late-half snaps tied or trailing'
             WHEN g.n < 6 THEN concat(g.n, CASE WHEN g.n = 1 THEN ' play' ELSE ' plays' END, ', ', note_epa(g.med), ' median EPA')
             ELSE concat(g.n, ' plays: median ', note_epa(g.med), ' EPA, best play ', note_epa(g.best), ', ',
                         note_epa(g.wo_best), ' per play without it') END,
        CASE WHEN COALESCE(g.n, 0) < 6 THEN 'Didn''t come up'
             WHEN c.p_flag = (g.med > 0) THEN 'Hit' ELSE 'Miss' END
    FROM pc c
    LEFT JOIN (SELECT season, week, team, COUNT(*) AS n, MEDIAN(epa) AS med, MAX(epa) AS best,
                      CASE WHEN COUNT(*) > 1 THEN (SUM(epa) - MAX(epa)) / (COUNT(*) - 1) END AS wo_best
               FROM theirs WHERE is_two_minute AND score_differential <= 0 GROUP BY ALL) g USING (season, week, team)
    WHERE c.call_no = 9
),

-- 9 and 10. Their early-down run and pass defense --------------------------------
c_defense AS (
    SELECT c.season, c.week, c.team, c.call_no, c.side, c.kind, c.call, c.said,
        concat('We had ', note_epa(g.epa), ' EPA per play on ', g.n, ', ',
               note_net(net_points(g.sum_epa, g.n, c.p_prior_sum, c.p_prior_n, c.p_num))),
        CASE WHEN g.n < 6 THEN 'Didn''t come up'
             ELSE net_verdict(net_points(g.sum_epa, g.n, c.p_prior_sum, c.p_prior_n, c.p_num), c.p_flag) END
    FROM pc c
    JOIN (SELECT season, week, team, CASE WHEN is_pass = 1 THEN 11 ELSE 10 END AS call_no,
                 COUNT(*) AS n, AVG(epa) AS epa, SUM(COALESCE(epa, 0)) AS sum_epa
          FROM ours WHERE is_early_down AND is_neutral_wp GROUP BY ALL) g USING (season, week, team, call_no)
    WHERE c.call_no IN (10, 11)
),

-- 11. The position they cover worst (warning, our side) --------------------------
c_position AS (
    SELECT c.season, c.week, c.team, c.call_no, c.side, c.kind, c.call, c.said,
        concat(COUNT(o.play_id), CASE WHEN COUNT(o.play_id) = 1 THEN ' target, ' ELSE ' targets, ' END, CAST(COALESCE(SUM(o.yards_gained), 0) AS INTEGER), ' yards, ',
               note_epa(COALESCE(SUM(o.epa), 0)), ' EPA, ',
               note_net(net_points(COALESCE(SUM(o.epa), 0), COUNT(o.play_id), c.p_prior_sum, c.p_prior_n, c.p_num))),
        CASE WHEN COUNT(o.play_id) = 0 THEN 'Didn''t come up'
             ELSE net_verdict(net_points(COALESCE(SUM(o.epa), 0), COUNT(o.play_id), c.p_prior_sum, c.p_prior_n, c.p_num), true) END
    FROM pc c
    LEFT JOIN (SELECT o.*, CASE WHEN pl.position IN ('FB', 'HB') THEN 'RB' ELSE pl.position END AS position
               FROM ours o JOIN (SELECT DISTINCT gsis_id, position FROM raw_players) pl ON pl.gsis_id = o.receiver_id
               WHERE o.is_pass = 1) o
      ON o.season = c.season AND o.week = c.week AND o.team = c.team AND o.position = c.p_bucket
    WHERE c.call_no = 12
    GROUP BY c.season, c.week, c.team, c.call_no, c.side, c.kind, c.call, c.said, c.p_prior_sum, c.p_prior_n, c.p_num
),

-- 12. Run lanes against them ---------------------------------------------------
-- 5 runs in each lane (was 2; changed Nov 25, 2026): one big run decided
-- 2-4 run lanes (week 11 NO: a 30-yard run made 4 runs around end 10.8 a carry).
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
    SELECT c.season, c.week, c.team, c.call_no, c.side, c.kind, c.call, c.said,
        concat(upper(note_bucket(c.p_bucket)[1]), note_bucket(c.p_bucket)[2:], ': ', COALESCE(ls.n, 0), CASE WHEN ls.n = 1 THEN ' run' ELSE ' runs' END,
               CASE WHEN ls.n > 0 THEN concat(', ', note_epa(ls.epa), ' EPA and ', note_yds(ls.ypc), ' yards a carry') ELSE '' END,
               '; ', note_bucket(c.p_bucket2), ': ', COALESCE(lh.n, 0), CASE WHEN lh.n = 1 THEN ' run' ELSE ' runs' END,
               CASE WHEN lh.n > 0 THEN concat(', ', note_epa(lh.epa), ' EPA and ', note_yds(lh.ypc), ' yards a carry') ELSE '' END),
        -- yards and EPA both have to agree for a Hit or a Miss
        CASE WHEN COALESCE(ls.n, 0) < 5 OR COALESCE(lh.n, 0) < 5 THEN 'Didn''t come up'
             WHEN ls.epa > lh.epa AND ls.ypc > lh.ypc THEN 'Hit'
             WHEN ls.epa <= lh.epa AND ls.ypc <= lh.ypc THEN 'Miss' ELSE 'Mixed' END
    FROM pc c
    LEFT JOIN our_lanes ls ON ls.season = c.season AND ls.week = c.week AND ls.team = c.team AND ls.width = c.p_bucket
    LEFT JOIN our_lanes lh ON lh.season = c.season AND lh.week = c.week AND lh.team = c.team AND lh.width = c.p_bucket2
    WHERE c.call_no = 13
),

-- 13. Red-zone throws (warning, our side) -----------------------------------------
c_redzone AS (
    SELECT c.season, c.week, c.team, c.call_no, c.side, c.kind, c.call, c.said,
        CASE WHEN g.n IS NULL THEN 'No red-zone dropbacks'
             ELSE concat(g.n, CASE WHEN g.n = 1 THEN ' dropback, ' ELSE ' dropbacks, ' END,
                         note_epa(g.epa), CASE WHEN g.n = 1 THEN ' EPA, ' ELSE ' EPA each, ' END, g.td, ' TD, ',
                         note_net(net_points(g.sum_epa, g.n, c.p_prior_sum, c.p_prior_n, c.p_num))) END,
        CASE WHEN g.n IS NULL THEN 'Didn''t come up'
             ELSE net_verdict(net_points(g.sum_epa, g.n, c.p_prior_sum, c.p_prior_n, c.p_num), true) END
    FROM pc c
    LEFT JOIN (SELECT season, week, team, COUNT(*) AS n, AVG(epa) AS epa, SUM(COALESCE(epa, 0)) AS sum_epa,
                      COUNT(*) FILTER (WHERE yards_gained >= yardline_100) AS td   -- gained the whole field left
               FROM ours WHERE is_red_zone AND is_pass = 1 GROUP BY ALL) g USING (season, week, team)
    WHERE c.call_no = 14
),

-- A starting quarterback the calls weren't built on: the game's main passer
-- (most dropbacks) threw under a third of the team's dropbacks in the games
-- before the week. The pass/run identity and run/dropback efficiency calls
-- describe another offense, so they are graded "Didn't come up" (week 10 of
-- 2026: Cousins for Minnesota after a trade, Brissett for Baltimore, DeVito for
-- New England). Week 1 is not checked.
qb_dropbacks AS (
    SELECT season, week, team, passer_id, COUNT(*) AS n
    FROM stg_plays WHERE is_pass = 1 AND passer_id IS NOT NULL GROUP BY ALL
),

qb_change AS (
    SELECT g.season, g.week, g.team, COALESCE(pl.display_name, g.qb) AS new_qb
    FROM (SELECT season, week, team, arg_max(passer_id, n) AS qb FROM qb_dropbacks GROUP BY ALL) g
    JOIN m USING (season, week, team)
    JOIN qb_dropbacks b ON b.season = g.season AND b.team = g.team AND b.week < g.week
    LEFT JOIN (SELECT gsis_id, any_value(display_name) AS display_name FROM raw_players GROUP BY ALL) pl
      ON pl.gsis_id = g.qb
    WHERE g.week > 1
    GROUP BY ALL
    HAVING COALESCE(SUM(b.n) FILTER (WHERE b.passer_id = g.qb), 0) < SUM(b.n) / 3.0
),

calls AS (
    SELECT * FROM c_identity UNION ALL SELECT * FROM c_works UNION ALL SELECT * FROM c_target
    UNION ALL SELECT * FROM c_lean UNION ALL SELECT * FROM c_hot
    UNION ALL SELECT * FROM c_late UNION ALL SELECT * FROM c_defense UNION ALL SELECT * FROM c_position
    UNION ALL SELECT * FROM c_lanes UNION ALL SELECT * FROM c_redzone
)

SELECT m.season, m.week, m.team, m.opponent, m.gameday, m.is_home, m.team_score, m.opponent_score,
       CASE WHEN m.week = 1 THEN 'last_season' ELSE 'in_season' END AS basis,   -- Week 1 is scouted from last season
       c.call_no, c.side, c.kind, c.call, c.said,
       CASE WHEN q.new_qb IS NOT NULL AND c.call_no IN (1, 2, 3)
            THEN concat('New QB (', q.new_qb, '): ', c.happened) ELSE c.happened END AS happened,
       CASE WHEN q.new_qb IS NOT NULL AND c.call_no IN (1, 2, 3) THEN 'Didn''t come up' ELSE c.verdict END AS verdict,
       CASE WHEN c.verdict = 'Called it' THEN 'Hurt us' END AS outcome   -- what it did on the field
FROM calls c
JOIN m USING (season, week, team)
LEFT JOIN qb_change q USING (season, week, team);
