-- epa_before_fumble may differ from epa only on completed passes, and must
-- never be missing when epa is there (the report card grades on it).
SELECT game_id, play_id, epa, epa_before_fumble, is_complete
FROM stg_plays
WHERE (epa IS NOT NULL AND epa_before_fumble IS NULL)
   OR (abs(epa_before_fumble - epa) > 1e-9 AND is_complete = 0);
