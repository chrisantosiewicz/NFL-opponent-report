-- last_season_ranks: each team's full regular-season numbers and league ranks.
--
-- No new math: the snapshot taken before the first playoff week contains
-- exactly the regular season, so this reuses tendency_ranks at that week.
-- The report joins season S to last season S - 1.

CREATE OR REPLACE TABLE last_season_ranks AS
WITH first_playoff_week AS (
    SELECT season, MIN(week) AS as_of_week
    FROM stg_team_games
    WHERE game_type <> 'REG'
    GROUP BY season
)

SELECT r.*
FROM tendency_ranks r
JOIN first_playoff_week p
  ON p.season     = r.season
 AND p.as_of_week = r.as_of_week
WHERE r.span = 'season';
