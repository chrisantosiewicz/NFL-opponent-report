-- No leakage: a week-N row only knows trades made before week N's last game,
-- and only counts games from earlier weeks.
SELECT t.season, t.as_of_week, t.player_name, t.trade_date, t.week_end
FROM trade_impact t
WHERE t.trade_date >= t.week_end
   OR t.from_games > (SELECT COUNT(*) FROM stg_team_games g
                      WHERE g.season = t.season AND g.team = t.from_team
                        AND g.week < t.as_of_week AND g.is_complete);
