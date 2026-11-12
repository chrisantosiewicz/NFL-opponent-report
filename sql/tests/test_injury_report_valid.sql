-- The injury report behind the scouting page's injury flag is well formed:
-- one row per player per team-week, a known team, a report from this week or
-- earlier, a flag that matches the status, and a snap share between 0 and 1.
SELECT season, week, team, gsis_id, 'duplicate player' AS problem
FROM injury_report
GROUP BY season, week, team, gsis_id
HAVING count(*) > 1

UNION ALL
SELECT season, week, team, gsis_id, 'unknown team'
FROM injury_report
WHERE team NOT IN (SELECT team FROM dim_team)

UNION ALL
SELECT season, week, team, gsis_id, 'report from a later week'
FROM injury_report
WHERE report_week > week

UNION ALL
SELECT season, week, team, gsis_id, 'flag does not match status'
FROM injury_report
WHERE (flag = 'out') <> COALESCE(report_status IN ('Out', 'Doubtful'), FALSE)
   OR (flag = 'questionable') <> COALESCE(report_status = 'Questionable', FALSE)

UNION ALL
SELECT season, week, team, gsis_id, 'snap share out of range'
FROM injury_report
WHERE snap_share < 0 OR snap_share > 1
   OR (is_starter AND games_played = 0);
