-- Every pass or run play has a down. (The staging filter enforces this today;
-- the test catches it if someone loosens the filter later.)
SELECT game_id, play_id
FROM stg_plays
WHERE down IS NULL;
