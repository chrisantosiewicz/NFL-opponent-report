-- three_things: the rule-based "3 things to know" candidates.
--
-- Rule: a season-to-date metric in the league's top or bottom 10%
-- (pctile >= 0.9 or <= 0.1, i.e. top or bottom 4 of 32) on at least 30 plays.
-- Ranked by how extreme it is, keeping at most one metric per situation so the
-- box doesn't say the same thing three ways. The report shows the top 3.

CREATE OR REPLACE TABLE three_things AS
WITH qualifying AS (
    SELECT *,
           ABS(pctile - 0.5) AS extremity
    FROM tendency_ranks
    WHERE span = 'season'
      AND situation <> 'all_neutral'
      AND n >= 30
      AND (pctile >= 0.9 OR pctile <= 0.1)
),

best_per_situation AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY season, as_of_week, team, situation
               ORDER BY extremity DESC, n DESC
           ) AS situation_pick
    FROM qualifying
)

SELECT
    season, as_of_week, team, situation, metric, value, n, league_rank,
    league_teams, pctile, league_avg,
    ROW_NUMBER() OVER (
        PARTITION BY season, as_of_week, team
        ORDER BY extremity DESC, n DESC
    ) AS priority
FROM best_per_situation
WHERE situation_pick = 1;
