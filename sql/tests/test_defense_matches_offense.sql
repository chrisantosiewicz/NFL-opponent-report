-- Every play a defense allowed is a play some offense ran: per report week and
-- situation, plays and EPA summed over defenses equal the offense side
-- (tendency_snapshot), so the two views can't drift apart.
WITH d AS (
    SELECT season, as_of_week, span, situation, SUM(plays) AS plays, SUM(sum_epa) AS sum_epa
    FROM defense_splits GROUP BY ALL
),
o AS (
    SELECT season, as_of_week, span, situation, SUM(plays) AS plays, SUM(sum_epa) AS sum_epa
    FROM tendency_snapshot WHERE span = 'season' GROUP BY ALL
)
SELECT o.*, d.plays AS defense_plays
FROM o JOIN d USING (season, as_of_week, span, situation)
WHERE o.plays <> d.plays OR abs(o.sum_epa - d.sum_epa) > 0.01;
