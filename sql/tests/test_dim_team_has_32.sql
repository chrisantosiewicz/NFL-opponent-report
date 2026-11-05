-- dim_team has exactly 32 teams. Returns one row if not.
SELECT COUNT(*) AS teams
FROM dim_team
HAVING COUNT(*) <> 32;
