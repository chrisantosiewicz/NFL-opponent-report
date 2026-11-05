-- The two roll-ups are exactly the sum of their score states, and states
-- never overlap: not_leading + leading = every play in the situation.
WITH s AS (
    SELECT season, as_of_week, team, side, situation,
        SUM(plays) FILTER (WHERE score_state IN ('trailing_9plus', 'trailing_1_8', 'tied')) AS nl_parts,
        SUM(plays) FILTER (WHERE score_state = 'not_leading') AS nl,
        SUM(plays) FILTER (WHERE score_state IN ('leading_1_8', 'leading_9plus')) AS l_parts,
        SUM(plays) FILTER (WHERE score_state = 'leading') AS l
    FROM score_splits GROUP BY ALL
)
SELECT s.*, 'roll-up does not match its states' AS problem
FROM s
WHERE COALESCE(nl_parts, 0) <> COALESCE(nl, 0) OR COALESCE(l_parts, 0) <> COALESCE(l, 0);
