-- No game in a report week's window may be from that week or later.
SELECT * FROM game_windows WHERE week >= as_of_week;
