-- The top target is never a receiver already known to be out that week: on
-- reserve in the weekly roster (RES) or ruled Out on the injury report.
SELECT t.season, t.as_of_week, t.team, t.receiver_name, 'on reserve' AS problem
FROM top_target t
JOIN raw_rosters_weekly ro
  ON CAST(ro.season AS INTEGER) = t.season AND CAST(ro.week AS INTEGER) = t.as_of_week
 AND ro.gsis_id = t.receiver_id AND ro.status = 'RES'
LEFT JOIN team_alias a ON a.alias = ro.team
WHERE COALESCE(a.team, ro.team) = t.team
UNION ALL
SELECT t.season, t.as_of_week, t.team, t.receiver_name, 'ruled Out'
FROM top_target t
JOIN stg_injuries i
  ON i.season = t.season AND i.week = t.as_of_week AND i.team = t.team
 AND i.gsis_id = t.receiver_id AND i.report_status = 'Out';
