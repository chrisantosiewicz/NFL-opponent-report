-- draft_notes: a first draft of the staff notes for every matchup, written as
-- how to stop their offense, how to attack their defense, and "what to look
-- for" on both sides, from the same tested tables the
-- report uses. One row per season x week x team (the offense being scouted)
-- x line. `opponent` is the team that plays them that week ("we" in the text).
--
-- Inputs, all as of the week (games before it only):
--   tendency_ranks   early-down identity, efficiency, 3rd down, 2-minute
--   formation_tells  what under center / shotgun says on early downs
--   top_target       their most-targeted receiver and where he gets the ball
--   defense_splits   their defense: EPA allowed vs run and pass by down and distance
--   defense_vs_position  production they allow to WR / TE / RB targets
--   trade_impact     key players who joined or left either team before the game
--
-- The wording is a template. It is meant to be edited: save an edited copy as
-- site/notes/<season>-week<NN>-<TEAM>.md and the live page shows that instead.
--
-- kind: 'h' heading, 'p' paragraph, 'li' bullet. line orders them.

CREATE OR REPLACE MACRO note_ord(n) AS
    CAST(n AS VARCHAR) || CASE WHEN n % 100 IN (11, 12, 13) THEN 'th'
                               WHEN n % 10 = 1 THEN 'st' WHEN n % 10 = 2 THEN 'nd'
                               WHEN n % 10 = 3 THEN 'rd' ELSE 'th' END;
CREATE OR REPLACE MACRO note_pct(x) AS CAST(CAST(round(100 * x) AS INTEGER) AS VARCHAR) || '%';
CREATE OR REPLACE MACRO note_epa(x) AS
    CASE WHEN round(x, 2) >= 0 THEN '+' ELSE '−' END || printf('%.2f', abs(round(x, 2)));
CREATE OR REPLACE MACRO note_day(d) AS strftime(CAST(d AS DATE), '%b %-d');
CREATE OR REPLACE MACRO note_sit(s) AS CASE s
    WHEN 'third_1_6' THEN 'on 3rd & 1-6'          WHEN 'third_long' THEN 'on 3rd & 7+'
    WHEN 'third_down' THEN 'on 3rd down'          WHEN 'early_down' THEN 'on early downs'
    WHEN 'red_zone' THEN 'in the red zone'        WHEN 'two_minute' THEN 'in the 2-minute drill'
    WHEN 'trailing_8plus' THEN 'when trailing by 8+'
    WHEN 'deep' THEN 'on throws 20+ yards downfield' ELSE s END;
CREATE OR REPLACE MACRO note_metric(m) AS CASE m
    WHEN 'proe' THEN 'pass rate over expected' WHEN 'shotgun_rate' THEN 'shotgun rate'
    WHEN 'epa_play' THEN 'EPA per play' WHEN 'pass_rate' THEN 'pass rate' ELSE m END;
CREATE OR REPLACE MACRO note_value(m, x) AS CASE
    WHEN m LIKE 'epa%' THEN note_epa(x)
    WHEN m = 'proe' THEN CASE WHEN round(100 * x) >= 0 THEN '+' ELSE '−' END
                         || CAST(CAST(abs(round(100 * x)) AS INTEGER) AS VARCHAR) || ' pts'
    ELSE note_pct(x) END;

CREATE OR REPLACE MACRO note_most(r, n) AS CASE
    WHEN r = 1 THEN 'the most' WHEN r = n THEN 'the fewest'
    WHEN r <= n / 2 THEN note_ord(r) || '-most' ELSE note_ord(n - r + 1) || '-fewest' END;
CREATE OR REPLACE MACRO note_pos(p) AS CASE p
    WHEN 'WR' THEN 'wide receivers' WHEN 'TE' THEN 'tight ends' WHEN 'RB' THEN 'running backs' ELSE p END;
CREATE OR REPLACE MACRO note_pos1(p) AS CASE p
    WHEN 'WR' THEN 'wide receiver' WHEN 'TE' THEN 'tight end' WHEN 'RB' THEN 'running back' ELSE p END;

CREATE OR REPLACE TABLE draft_notes AS
WITH matchups AS (
    SELECT g.season, g.week, g.team, g.opponent, g.gameday,
           t.team_nick AS nick, o.team_nick AS opp_nick
    FROM stg_team_games g
    JOIN dim_team t ON t.team = g.team
    JOIN dim_team o ON o.team = g.opponent
),

r AS (   -- season-to-date numbers, one column per number the template uses
    SELECT season, as_of_week AS week, team,
        MAX(games) AS games,
        MAX(value)       FILTER (WHERE situation = 'early_down' AND metric = 'proe')         AS ed_proe,
        MAX(league_rank) FILTER (WHERE situation = 'early_down' AND metric = 'proe')         AS ed_proe_rank,
        MAX(pctile)      FILTER (WHERE situation = 'early_down' AND metric = 'proe')         AS ed_proe_pct,
        MAX(pctile)      FILTER (WHERE situation = 'early_down' AND metric = 'shotgun_rate') AS ed_sg_pct,
        MAX(league_rank) FILTER (WHERE situation = 'early_down' AND metric = 'shotgun_rate') AS ed_sg_rank,
        MAX(value)       FILTER (WHERE situation = 'early_down' AND metric = 'epa_run')      AS ed_run,
        MAX(league_rank) FILTER (WHERE situation = 'early_down' AND metric = 'epa_run')      AS ed_run_rank,
        MAX(n)           FILTER (WHERE situation = 'early_down' AND metric = 'epa_run')      AS ed_run_n,
        MAX(value)       FILTER (WHERE situation = 'early_down' AND metric = 'epa_pass')     AS ed_pass,
        MAX(league_rank) FILTER (WHERE situation = 'early_down' AND metric = 'epa_pass')     AS ed_pass_rank,
        MAX(n)           FILTER (WHERE situation = 'early_down' AND metric = 'epa_pass')     AS ed_pass_n,
        MAX(value)       FILTER (WHERE situation = 'early_down' AND metric = 'epa_play')     AS ed_play,
        MAX(league_rank) FILTER (WHERE situation = 'early_down' AND metric = 'epa_play')     AS ed_play_rank,
        MAX(n)           FILTER (WHERE situation = 'early_down' AND metric = 'epa_play')     AS ed_n,
        SUM(n)           FILTER (WHERE situation LIKE 'third_%' AND metric = 'pass_rate')    AS third_n,
        MAX(n)           FILTER (WHERE situation = 'third_long' AND metric = 'pass_rate')    AS third_long_n,
        MAX(value)       FILTER (WHERE situation = 'third_long' AND metric = 'epa_play')     AS tl_play,
        MAX(league_rank) FILTER (WHERE situation = 'third_long' AND metric = 'epa_play')     AS tl_rank,
        MAX(value)       FILTER (WHERE situation = 'two_minute' AND metric = 'epa_play')     AS tm_play,
        MAX(league_rank) FILTER (WHERE situation = 'two_minute' AND metric = 'epa_play')     AS tm_rank,
        MAX(pctile)      FILTER (WHERE situation = 'two_minute' AND metric = 'epa_play')     AS tm_pct,
        MAX(n)           FILTER (WHERE situation = 'two_minute' AND metric = 'epa_play')     AS tm_n,
        MAX(league_teams) AS teams
    FROM tendency_ranks
    WHERE span = 'season'
    GROUP BY ALL
),

league_third AS (
    SELECT season, week, SUM(third_long_n) * 1.0 / NULLIF(SUM(third_n), 0) AS lg_long_share
    FROM r GROUP BY ALL
),

f AS (
    SELECT m.*, r.* EXCLUDE (season, week, team),
           r.third_long_n * 1.0 / NULLIF(r.third_n, 0) AS long_share, lt.lg_long_share,
           CASE WHEN r.ed_proe_pct >= 0.75 THEN 'pass' WHEN r.ed_proe_pct <= 0.25 THEN 'run' ELSE 'balanced' END AS lean,
           ft.uc_share, ft.uc_run_rate, ft.uc_epa, ft.sg_pass_rate, ft.league_uc_run_rate, ft.league_sg_pass_rate,
           tt.receiver_name, tt.share, tt.targets, tt.team_targets, tt.league_rank AS tt_rank,
           tt.share_last4, tt.epa_per_target, tt.others_epa_per_target,
           tt.sit1, tt.sit1_targets, tt.sit1_team_targets, tt.sit2, tt.sit2_targets, tt.sit2_team_targets,
           tt.deep_targets, tt.deep_team_targets
    FROM matchups m
    JOIN r USING (season, week, team)
    JOIN league_third lt USING (season, week)
    LEFT JOIN formation_tells ft ON ft.season = m.season AND ft.as_of_week = m.week AND ft.team = m.team
    LEFT JOIN top_target tt      ON tt.season = m.season AND tt.as_of_week = m.week AND tt.team = m.team
),

moves AS (   -- key players who moved before the game, sorted into the two halves of the notes
    SELECT season, week, team, kind,
           CASE WHEN kind IN ('off_in', 'off_out', 'def_in') THEN 'stop' ELSE 'attack' END AS section,
           * EXCLUDE (season, week, team, kind),
           ROW_NUMBER() OVER (PARTITION BY season, week, team,
                                           CASE WHEN kind IN ('off_in', 'off_out', 'def_in') THEN 'stop' ELSE 'attack' END
                              ORDER BY CASE kind WHEN 'off_in' THEN 1 WHEN 'off_out' THEN 2 WHEN 'def_in' THEN 3
                                                 WHEN 'their_def_in' THEN 1 WHEN 'their_def_out' THEN 2 ELSE 3 END,
                                       trade_date DESC, player_name) AS move_no
    FROM (
        SELECT m.season, m.week, m.team,
               CASE WHEN ti.side = 'offense' AND ti.to_team   = m.team     THEN 'off_in'
                    WHEN ti.side = 'offense' AND ti.from_team = m.team     THEN 'off_out'
                    WHEN ti.side = 'defense' AND ti.to_team   = m.opponent THEN 'def_in'
                    WHEN ti.side = 'defense' AND ti.to_team   = m.team     THEN 'their_def_in'
                    WHEN ti.side = 'defense' AND ti.from_team = m.team     THEN 'their_def_out'
                    WHEN ti.side = 'offense' AND ti.to_team   = m.opponent THEN 'our_off_in'
               END AS kind,
               ti.* EXCLUDE (season), ft.team_nick AS from_nick, tn.team_nick AS to_nick
        FROM matchups m
        JOIN trade_impact ti
          ON ti.season = m.season AND ti.as_of_week = m.week AND ti.trade_date < m.gameday AND ti.is_key
         AND (m.team IN (ti.from_team, ti.to_team) OR ti.to_team = m.opponent)
        LEFT JOIN dim_team ft ON ft.team = ti.from_team
        LEFT JOIN dim_team tn ON tn.team = ti.to_team
    ) k
    WHERE kind IS NOT NULL
),

move_text AS (
    SELECT season, week, team, section, move_no, kind, player_name, position, from_nick, to_nick, trade_date,
        CASE kind
          WHEN 'off_in' THEN concat('On ', note_day(trade_date), ' they added ', position, ' ', player_name,
               ' from the ', COALESCE(from_nick, from_team), '. ',
               CASE WHEN to_games_since = 0 THEN 'This is his first game with them, so none of these numbers include him.'
                    ELSE concat('He has played ', to_games_since, ' of their ', to_games, ' games.') END)
          WHEN 'off_out' THEN concat('On ', note_day(trade_date), ' they lost ', position, ' ', player_name,
               ' to the ', COALESCE(to_nick, to_team), ' after he played ', note_pct(off_snap_pct_before),
               ' of their offensive snaps', CASE WHEN from_games_since = 0 THEN ', and he was there for every game in this sample.'
               ELSE concat('; ', from_games_since, ' of their ', from_games, ' games came without him.') END)
          WHEN 'their_def_in' THEN concat('On ', note_day(trade_date), ' their defense added ', position, ' ', player_name,
               ' from the ', COALESCE(from_nick, from_team), '. ',
               CASE WHEN to_games_since = 0 THEN 'This is his first game with them, so none of these numbers include him.'
                    ELSE concat('He has played ', to_games_since, ' of their ', to_games, ' games.') END)
          WHEN 'their_def_out' THEN concat('On ', note_day(trade_date), ' their defense lost ', position, ' ', player_name,
               ' to the ', COALESCE(to_nick, to_team), ' after he played ', note_pct(def_snap_pct_before),
               ' of their defensive snaps', CASE WHEN from_games_since = 0 THEN ', and he was there for every game in this sample.'
               ELSE concat('; ', from_games_since, ' of their ', from_games, ' games came without him.') END)
          ELSE concat('We added ', position, ' ', player_name, ' from the ', COALESCE(from_nick, from_team), ' on ',
               note_day(trade_date), CASE WHEN to_games_since = 0 THEN ', and this is his first game with us.' ELSE '.' END)
        END AS sentence,
        CASE WHEN kind = 'off_in' THEN
          CASE WHEN position IN ('G', 'T', 'C', 'OL', 'OT', 'OG') THEN
                 concat('Early runs behind ', player_name, '. If they run at him on the first two series, that''s the trade showing up.')
               WHEN position IN ('WR', 'TE') THEN
                 concat('Early targets to ', player_name, ': how fast they work him into the passing game.')
               WHEN position = 'RB' THEN concat('Carries for ', player_name, ' and whether he takes over early downs.')
               WHEN position = 'QB' THEN concat(player_name, ' at quarterback: none of the passing numbers here are his.')
               ELSE concat(player_name, ' in the lineup and what changes around him.') END
             WHEN kind = 'their_def_in' THEN
               concat('Where ', player_name, ' lines up on their defense, and whether we test him early.')
        END AS look_for
    FROM moves
    WHERE move_no <= 4
),

our_def_add AS (
    SELECT season, week, team, string_agg(position || ' ' || player_name, ' and ' ORDER BY trade_date DESC) AS names
    FROM moves WHERE kind = 'def_in' GROUP BY ALL
),

shifts AS (   -- the one-pager's six watched numbers, flagged the same way
    SELECT s.season, s.as_of_week AS week, s.team, s.situation, s.metric, s.value AS season_value,
           l.value AS last4_value, l.n AS last4_n
    FROM tendency_ranks s
    JOIN tendency_ranks l USING (season, as_of_week, team, situation, metric)
    WHERE s.span = 'season' AND l.span = 'last4' AND s.games > 4 AND l.n >= 30
      AND (s.situation, s.metric) IN (('early_down', 'proe'), ('early_down', 'shotgun_rate'), ('early_down', 'epa_play'),
                                     ('third_short', 'pass_rate'), ('red_zone', 'pass_rate'), ('all_neutral', 'epa_play'))
      AND abs(l.value - s.value) >= CASE WHEN s.metric LIKE 'epa%' THEN 0.10 ELSE 0.05 END
),

dfn AS (   -- their defense, season to date (rank 1 = allows the most)
    SELECT season, as_of_week AS week, defense AS team,
        MAX(epa_allowed)  FILTER (WHERE situation = 'early_down' AND play_type = 'run')   AS ed_run,
        MAX(rank_allowed) FILTER (WHERE situation = 'early_down' AND play_type = 'run')   AS ed_run_rank,
        MAX(epa_allowed)  FILTER (WHERE situation = 'early_down' AND play_type = 'pass')  AS ed_pass,
        MAX(rank_allowed) FILTER (WHERE situation = 'early_down' AND play_type = 'pass')  AS ed_pass_rank,
        MAX(epa_allowed)  FILTER (WHERE situation = 'third_long' AND play_type = 'pass')  AS tl_pass,
        MAX(rank_allowed) FILTER (WHERE situation = 'third_long' AND play_type = 'pass')  AS tl_pass_rank,
        MAX(epa_allowed)  FILTER (WHERE situation = 'third_short' AND play_type = 'run')  AS ts_run,
        MAX(rank_allowed) FILTER (WHERE situation = 'third_short' AND play_type = 'run')  AS ts_run_rank,
        MAX(plays)        FILTER (WHERE situation = 'third_short' AND play_type = 'run')  AS ts_run_n,
        MAX(epa_allowed)  FILTER (WHERE situation = 'red_zone' AND play_type = 'pass')    AS rz_pass,
        MAX(rank_allowed) FILTER (WHERE situation = 'red_zone' AND play_type = 'pass')    AS rz_pass_rank,
        MAX(plays)        FILTER (WHERE situation = 'red_zone' AND play_type = 'pass')    AS rz_pass_n,
        MAX(epa_allowed)  FILTER (WHERE situation = 'red_zone' AND play_type = 'run')     AS rz_run,
        MAX(rank_allowed) FILTER (WHERE situation = 'red_zone' AND play_type = 'run')     AS rz_run_rank,
        MAX(plays)        FILTER (WHERE situation = 'red_zone' AND play_type = 'run')     AS rz_run_n,
        MAX(teams) AS teams
    FROM defense_splits
    WHERE span = 'season'
    GROUP BY ALL
),

pos AS (   -- the positions they cover worst and best (20+ targets)
    SELECT season, as_of_week AS week, defense AS team, position, targets, epa_per_target,
           rank_allowed, yards_per_game, teams, league_epa_per_target,
           ROW_NUMBER() OVER (PARTITION BY season, as_of_week, defense ORDER BY rank_allowed, position)      AS soft_pick,
           ROW_NUMBER() OVER (PARTITION BY season, as_of_week, defense ORDER BY rank_allowed DESC, position) AS hard_pick
    FROM defense_vs_position
    WHERE targets >= 20
),

attack AS (
    SELECT m.season, m.week, m.team,
        concat(
          CASE WHEN d.ed_run_rank <= 10 AND d.ed_pass_rank <= 10
                 THEN concat('The ', m.nick, ' defense is soft on early downs against both the run (', note_epa(d.ed_run),
                             ' EPA per run allowed, ', note_most(d.ed_run_rank, d.teams), ' in the league) and the pass (',
                             note_epa(d.ed_pass), ' per dropback, ', note_most(d.ed_pass_rank, d.teams), ').')
               WHEN least(d.ed_run_rank, d.ed_pass_rank) <= 12 AND d.ed_run_rank <= d.ed_pass_rank
                 THEN concat('Attack them on the ground on early downs: they allow ', note_epa(d.ed_run), ' EPA per run (',
                             note_most(d.ed_run_rank, d.teams), ' in the league), against ', note_epa(d.ed_pass), ' per dropback (',
                             note_most(d.ed_pass_rank, d.teams), ').')
               WHEN least(d.ed_run_rank, d.ed_pass_rank) <= 12
                 THEN concat('Attack them through the air on early downs: they allow ', note_epa(d.ed_pass), ' EPA per dropback (',
                             note_most(d.ed_pass_rank, d.teams), ' in the league), against ', note_epa(d.ed_run), ' per run (',
                             note_most(d.ed_run_rank, d.teams), ').')
               ELSE concat('There''s no soft spot on early downs: the ', m.nick, ' allow ', note_epa(d.ed_run), ' EPA per run (',
                           note_most(d.ed_run_rank, d.teams), ' in the league) and ', note_epa(d.ed_pass), ' per dropback (',
                           note_most(d.ed_pass_rank, d.teams), '), so expect to grind and take what they give.') END,
          ' On 3rd & 7+ they allow ', note_epa(d.tl_pass), ' per dropback (', note_most(d.tl_pass_rank, d.teams), ')',
          CASE WHEN d.ts_run_n >= 8 THEN concat(', and runs on 3rd & 1-3 get ', note_epa(d.ts_run), ' (', note_most(d.ts_run_rank, d.teams), ')') END,
          '.',
          CASE WHEN d.rz_pass_n >= 15 AND d.rz_pass_rank <= 8
                 THEN concat(' Inside their 20 they''ve been easier to throw on: ', note_epa(d.rz_pass), ' per dropback (',
                             note_most(d.rz_pass_rank, d.teams), ') on ', d.rz_pass_n, ' plays.')
               WHEN d.rz_run_n >= 15 AND d.rz_run_rank <= 8
                 THEN concat(' Inside their 20 they''ve been easier to run on: ', note_epa(d.rz_run), ' per run (',
                             note_most(d.rz_run_rank, d.teams), ') on ', d.rz_run_n, ' plays.') END,
          (SELECT ' ' || string_agg(sentence, ' ' ORDER BY move_no) FROM move_text mt
           WHERE mt.season = m.season AND mt.week = m.week AND mt.team = m.team AND mt.section = 'attack')
        ) AS p4,
        CASE WHEN ps.position IS NOT NULL THEN concat(
          'In the passing game, go at their coverage of ', note_pos(ps.position), ': they allow ', note_epa(ps.epa_per_target),
          ' EPA per target to them (', note_most(ps.rank_allowed, ps.teams), ' in the league; league average ',
          note_epa(ps.league_epa_per_target), ') and ', CAST(round(ps.yards_per_game) AS INTEGER), ' yards per game.',
          CASE WHEN ph.position <> ps.position
               THEN concat(' ', upper(note_pos(ph.position)[1]), note_pos(ph.position)[2:], ' have had the hardest time: ',
                           note_epa(ph.epa_per_target), ' per target (', note_most(ph.rank_allowed, ph.teams), ').') END,
          CASE WHEN ot.position = ps.position
                 THEN concat(' Our top target, ', ot.receiver_name, ' (', note_pct(ot.share), ' of our targets), is a ',
                             note_pos1(ot.position), ', so that matchup works for us.')
               WHEN ot.position = ph.position
                 THEN concat(' Our top target, ', ot.receiver_name, ' (', note_pct(ot.share), ' of our targets), is a ',
                             note_pos1(ot.position), ', the position they cover best, so get him the ball on our terms.') END
        ) END AS p5,
        CASE WHEN least(d.ed_run_rank, d.ed_pass_rank) <= 12 THEN concat(
          'Our early-down ', CASE WHEN d.ed_run_rank <= d.ed_pass_rank THEN 'runs' ELSE 'throws' END,
          ': that''s where they''re softest. If the first few work, stay with it.') END AS li_early,
        CASE WHEN ps.position IS NOT NULL THEN concat('Targets to our ', note_pos(ps.position), ': ',
          note_epa(ps.epa_per_target), ' EPA per target allowed (', note_most(ps.rank_allowed, ps.teams),
          '). Check early whether they''ve adjusted their coverage.') END AS li_position
    FROM matchups m
    JOIN dfn d USING (season, week, team)
    LEFT JOIN pos ps ON ps.season = m.season AND ps.week = m.week AND ps.team = m.team AND ps.soft_pick = 1
    LEFT JOIN pos ph ON ph.season = m.season AND ph.week = m.week AND ph.team = m.team AND ph.hard_pick = 1
    LEFT JOIN top_target ot ON ot.season = m.season AND ot.as_of_week = m.week AND ot.team = m.opponent
),

paragraphs AS (
    SELECT f.season, f.week, f.team, f.opponent, f.nick,
        -- 1. Identity and whether it works, plus roster moves on their offense and our defense
        concat(
          CASE f.lean
            WHEN 'run'  THEN concat('The ', f.nick, ' want to run. On early downs they run more than the situation calls for (',
                                    note_ord(f.ed_proe_rank), ' in pass rate over expected)')
            WHEN 'pass' THEN concat('The ', f.nick, ' want to throw. On early downs they pass more than the situation calls for (',
                                    note_ord(f.ed_proe_rank), ' in pass rate over expected)')
            ELSE concat('The ', f.nick, ' call it close to what the situation suggests: their early-down pass rate over expected is ',
                        note_value('proe', f.ed_proe), ' (', note_ord(f.ed_proe_rank), ')')
          END,
          CASE WHEN f.ed_sg_pct <= 0.25 THEN concat(', and they are under center ', note_pct(f.uc_share), ' of the time')
               WHEN f.ed_sg_pct >= 0.75 THEN concat(', and they are in shotgun ', note_pct(1 - f.uc_share), ' of the time') END,
          '. ',
          CASE f.lean
            WHEN 'run' THEN concat(
                CASE WHEN f.ed_run_rank <= 10 THEN 'It works: ' WHEN f.ed_run_rank >= 23 THEN 'It hasn''t worked: ' ELSE 'The results are middling: ' END,
                'their early-down runs are ', note_ord(f.ed_run_rank), ' at ', note_epa(f.ed_run), ' EPA per run on ', f.ed_run_n,
                ' plays, and their dropbacks are ', note_ord(f.ed_pass_rank), ' at ', note_epa(f.ed_pass), '.')
            WHEN 'pass' THEN concat(
                CASE WHEN f.ed_pass_rank <= 10 THEN 'It works: ' WHEN f.ed_pass_rank >= 23 THEN 'It hasn''t worked: ' ELSE 'The results are middling: ' END,
                'their early-down dropbacks are ', note_ord(f.ed_pass_rank), ' at ', note_epa(f.ed_pass), ' EPA per dropback on ', f.ed_pass_n,
                ' plays, and their runs are ', note_ord(f.ed_run_rank), ' at ', note_epa(f.ed_run), '.')
            ELSE concat('On early downs they are ', note_ord(f.ed_play_rank), ' at ', note_epa(f.ed_play), ' EPA per play: runs ',
                        note_ord(f.ed_run_rank), ' (', note_epa(f.ed_run), '), dropbacks ', note_ord(f.ed_pass_rank), ' (', note_epa(f.ed_pass), ').')
          END,
          (SELECT ' ' || string_agg(sentence, ' ' ORDER BY move_no) FROM move_text mt
           WHERE mt.season = f.season AND mt.week = f.week AND mt.team = f.team AND mt.section = 'stop')
        ) AS p1,

        -- 2. The passing game through the top target
        CASE WHEN f.receiver_name IS NOT NULL AND f.targets >= 20 THEN concat(
          CASE WHEN f.share >= 0.30 THEN concat('The passing game runs through ', f.receiver_name, '. He gets ')
               WHEN f.share >= 0.22 THEN concat('The passing game leans on ', f.receiver_name, '. He gets ')
               ELSE concat('They spread the ball around. ', f.receiver_name, ' leads them but gets only ') END,
          note_pct(f.share), ' of their targets (', f.targets, ' of ', f.team_targets, ')',
          CASE WHEN f.tt_rank = 1 THEN ', the highest share of any player in the NFL'
               WHEN f.tt_rank <= 5 THEN concat(', the ', note_ord(f.tt_rank), '-highest share in the NFL') END,
          CASE WHEN f.share_last4 IS NULL OR f.games <= 4 THEN '. '
               WHEN f.share_last4 - f.share >= 0.04 THEN concat(', and it''s growing: ', note_pct(f.share_last4), ' over the last 4 games. ')
               WHEN f.share_last4 - f.share <= -0.04 THEN concat(', though it''s dropped to ', note_pct(f.share_last4), ' over the last 4 games. ')
               ELSE concat(', and it''s held at ', note_pct(f.share_last4), ' over the last 4 games. ') END,
          'He averages ', note_epa(f.epa_per_target), ' EPA per target; everyone else they throw to averages ',
          note_epa(f.others_epa_per_target), '.',
          CASE WHEN f.epa_per_target - f.others_epa_per_target >= 0.30
               THEN concat(' The coverage plan starts with him: take him away and they''re throwing to targets averaging ',
                           note_epa(f.others_epa_per_target), ' EPA.')
               WHEN f.epa_per_target - f.others_epa_per_target <= -0.20
               THEN ' The volume hasn''t turned into production, so his targets are ones to welcome, not take away.' END,
          CASE WHEN f.sit1 IS NOT NULL THEN concat(' They go to him most ', note_sit(f.sit1), ' (', f.sit1_targets, ' of ', f.sit1_team_targets, ')',
               CASE WHEN f.sit2 IS NOT NULL THEN concat(' and ', note_sit(f.sit2), ' (', f.sit2_targets, ' of ', f.sit2_team_targets, ')') END, '.') END
        ) END AS p2,

        -- 3. Where drives end up: 3rd & long, and late in halves
        concat(
          CASE WHEN f.long_share >= f.lg_long_share + 0.05
               THEN concat('They live in 3rd & long: ', note_pct(f.long_share), ' of their third downs have been 7+ to go (league ',
                           note_pct(f.lg_long_share), '), ')
               WHEN f.long_share <= f.lg_long_share - 0.05
               THEN concat('They stay ahead of the chains: only ', note_pct(f.long_share), ' of their third downs have been 7+ to go (league ',
                           note_pct(f.lg_long_share), '), ')
               ELSE concat(note_pct(f.long_share), ' of their third downs have been 7+ to go (league ', note_pct(f.lg_long_share), '), ') END,
          'and there they are ', note_ord(f.tl_rank), ' at ', note_epa(f.tl_play), ' EPA per play.',
          CASE WHEN f.tm_n >= 30 AND f.tm_pct <= 0.25
                 THEN concat(' Late in halves they''ve been ', note_ord(f.tm_rank), ' of ', f.teams, ' (', note_epa(f.tm_play),
                             ' EPA per play on ', f.tm_n, ' plays), so keep everything in front.')
               WHEN f.tm_n >= 30 AND f.tm_pct >= 0.75
                 THEN concat(' Late in halves they''ve been dangerous: ', note_ord(f.tm_rank), ' at ', note_epa(f.tm_play),
                             ' EPA per play on ', f.tm_n, ' plays.') END
        ) AS p3,

        -- What to look for
        CASE WHEN f.ed_sg_pct <= 0.25 THEN concat('Under center on 1st and 2nd down: ', note_pct(f.uc_share),
               ' of their early downs. They''ve run on ', note_pct(f.uc_run_rate), ' of those snaps (league ',
               note_pct(f.league_uc_run_rate), ') for ', note_epa(f.uc_epa), ' EPA per play.')
             WHEN f.ed_sg_pct >= 0.75 THEN concat('Shotgun on early downs: ', note_pct(1 - f.uc_share),
               ' of their early downs. They''ve passed on ', note_pct(f.sg_pass_rate), ' of those snaps (league ',
               note_pct(f.league_sg_pass_rate), ').') END AS li_formation,
        CASE WHEN f.share >= 0.22 AND f.sit1 IS NOT NULL THEN concat('Where ', f.receiver_name, ' lines up ', note_sit(f.sit1), ': ',
               f.sit1_targets, ' of their ', f.sit1_team_targets, ' targets there',
               CASE WHEN f.sit1 <> 'deep' AND f.deep_targets >= 4
                    THEN concat('. He also has ', f.deep_targets, ' of their ', f.deep_team_targets, ' deep targets') END, '.') END AS li_target,
        (SELECT names FROM our_def_add d WHERE d.season = f.season AND d.week = f.week AND d.team = f.team) AS our_adds
    FROM f
),

lines AS (
    SELECT season, week, team, 10 AS line, 'h' AS kind, 'Stopping their offense' AS text FROM paragraphs
    UNION ALL SELECT season, week, team, 11, 'p', p1 FROM paragraphs
    UNION ALL SELECT season, week, team, 12, 'p', p2 FROM paragraphs WHERE p2 IS NOT NULL
    UNION ALL SELECT season, week, team, 13, 'p', p3 FROM paragraphs
    UNION ALL SELECT season, week, team, 14, 'h', 'Attacking their defense' FROM attack
    UNION ALL SELECT season, week, team, 15, 'p', p4 FROM attack
    UNION ALL SELECT season, week, team, 16, 'p', p5 FROM attack WHERE p5 IS NOT NULL
    UNION ALL SELECT season, week, team, 20, 'h', 'What to look for on defense' FROM paragraphs
    UNION ALL SELECT season, week, team, 50, 'h', 'What to look for on offense' FROM attack
    UNION ALL SELECT season, week, team, 51, 'li', li_early FROM attack WHERE li_early IS NOT NULL
    UNION ALL SELECT season, week, team, 52, 'li', li_position FROM attack WHERE li_position IS NOT NULL
    UNION ALL
    SELECT season, week, team, 52 + move_no, 'li', look_for FROM move_text WHERE kind = 'their_def_in'
    UNION ALL
    SELECT p.season, p.week, p.team, 20 + mt.move_no, 'li',
           concat(mt.look_for, CASE WHEN p.our_adds IS NOT NULL AND mt.position IN ('G', 'T', 'C', 'OL', 'OT', 'OG', 'RB')
                                    THEN concat(' See whether ', p.our_adds, ' is winning those snaps.') END)
    FROM paragraphs p
    JOIN move_text mt ON mt.season = p.season AND mt.week = p.week AND mt.team = p.team AND mt.kind = 'off_in'
    UNION ALL SELECT season, week, team, 30, 'li', li_formation FROM paragraphs WHERE li_formation IS NOT NULL
    UNION ALL SELECT season, week, team, 31, 'li', li_target FROM paragraphs WHERE li_target IS NOT NULL
    UNION ALL
    SELECT season, week, team, 40 + ROW_NUMBER() OVER (PARTITION BY season, week, team ORDER BY situation, metric), 'li',
           concat(CASE situation WHEN 'early_down' THEN 'Early-down ' WHEN 'third_short' THEN '3rd & 1-3 '
                                 WHEN 'red_zone' THEN 'Red-zone ' ELSE 'Neutral-down ' END,
                  note_metric(metric), ': ', note_value(metric, season_value), ' for the season, ',
                  note_value(metric, last4_value), ' over the last 4 games (', last4_n,
                  ' plays). Check early whether that''s the new normal.')
    FROM shifts
)

SELECT l.season, l.week, l.team, m.opponent, l.line, l.kind, l.text
FROM lines l
JOIN matchups m USING (season, week, team)
WHERE l.text IS NOT NULL AND l.text <> '';
