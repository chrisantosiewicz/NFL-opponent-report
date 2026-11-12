-- game_weather: the kickoff forecast for each upcoming game, whether it is
-- played indoors (weather neutral), and simple flags; plus weather_history,
-- how totals went in past outdoor games in the same conditions, as context.
--
-- Sources: raw_schedules (roof, stadium, kickoff time in US Eastern),
-- raw_stadiums (config/stadiums.csv: roof type when the schedule leaves it
-- blank) and raw_weather_hourly (Open-Meteo hourly forecast, fetched by
-- fetch_weather() for games in the next 7 days, times in US Eastern).
-- Forecast window: the kickoff hour and the two hours after it.
-- Thresholds (definitions.md): windy = 15+ mph sustained, cold = 32F or below,
-- wet = 50%+ chance of precipitation in the window.
--
-- Weather is shown next to the total. It is not an input to the Elo win %.

CREATE OR REPLACE TABLE game_weather AS
WITH games AS (
    SELECT
        s.game_id, CAST(s.season AS INTEGER) AS season, CAST(s.week AS INTEGER) AS week,
        s.home_team, s.away_team, s.stadium_id, s.stadium,
        strptime(CAST(s.gameday AS VARCHAR) || ' ' || left(CAST(s.gametime AS VARCHAR), 5), '%Y-%m-%d %H:%M') AS kickoff_et,
        CASE
            WHEN lower(s.roof) IN ('dome', 'closed')    THEN 'indoor'
            WHEN lower(s.roof) IN ('outdoors', 'open')  THEN 'outdoor'
            WHEN st.roof = 'dome'                       THEN 'indoor'
            WHEN st.roof = 'retractable'                THEN 'retractable'
            WHEN st.roof = 'outdoors'                   THEN 'outdoor'
        END                                             AS roof_class,
        TRY_CAST(s.temp AS DOUBLE)                      AS actual_temp_f,
        TRY_CAST(s.wind AS DOUBLE)                      AS actual_wind_mph
    FROM raw_schedules s
    LEFT JOIN raw_stadiums st ON st.stadium_id = s.stadium_id
    WHERE s.gametime IS NOT NULL
),

forecast AS (
    SELECT
        g.game_id,
        count(*)                          AS forecast_hours,
        avg(TRY_CAST(w.temp_f AS DOUBLE))                     AS temp_f,
        max(TRY_CAST(w.wind_mph AS DOUBLE))                   AS wind_mph,
        max(TRY_CAST(w.gust_mph AS DOUBLE))                   AS gust_mph,
        max(TRY_CAST(w.precip_prob AS DOUBLE))                AS precip_prob,
        sum(TRY_CAST(w.precip_in AS DOUBLE))                  AS precip_in,
        max(CAST(w.fetched_at AS VARCHAR))                 AS fetched_at
    FROM games g
    JOIN raw_weather_hourly w ON w.game_id = g.game_id
    WHERE strptime(CAST(w.time AS VARCHAR), '%Y-%m-%dT%H:%M') >= date_trunc('hour', g.kickoff_et)
      AND strptime(CAST(w.time AS VARCHAR), '%Y-%m-%dT%H:%M') <  date_trunc('hour', g.kickoff_et) + INTERVAL 3 HOUR
    GROUP BY g.game_id
)

SELECT
    g.*,
    g.roof_class = 'indoor'                                   AS is_neutral,
    f.forecast_hours, f.temp_f, f.wind_mph, f.gust_mph, f.precip_prob, f.precip_in, f.fetched_at,
    NOT (g.roof_class = 'indoor') AND COALESCE(f.wind_mph >= 15, FALSE)     AS is_windy,
    NOT (g.roof_class = 'indoor') AND COALESCE(f.temp_f <= 32, FALSE)       AS is_cold,
    NOT (g.roof_class = 'indoor') AND COALESCE(f.precip_prob >= 50, FALSE)  AS is_wet
FROM games g
LEFT JOIN forecast f ON f.game_id = g.game_id;

-- Completed outdoor games since 2017 with the stadium's recorded kickoff
-- temperature and wind (nflverse schedules; blank for indoor games), and how
-- the total finished against the closing line, by condition. Rain and snow
-- come from the gamebook's kickoff weather text: the description before
-- "Temp:" names rain/showers/drizzle/storms (rain) or snow/flurries/sleet
-- (snow), and does not only forecast it ("chance of rain", "rain possible").
CREATE OR REPLACE TABLE weather_history AS
WITH gamebook AS (
    SELECT game_id, any_value(weather) AS weather
    FROM (
        SELECT game_id, weather FROM raw_gamebook_weather
        UNION ALL
        SELECT game_id, weather FROM raw_pbp WHERE weather IS NOT NULL
    )
    GROUP BY game_id
),

sky AS (
    SELECT game_id,
           lower(COALESCE(NULLIF(regexp_extract(weather, '^(.*?)Temp:', 1), ''), weather)) AS sky
    FROM gamebook
),

outdoor AS (
    SELECT
        TRY_CAST(s.temp AS DOUBLE)                            AS temp_f,
        TRY_CAST(s.wind AS DOUBLE)                            AS wind_mph,
        COALESCE(regexp_matches(k.sky, 'rain|shower|drizzle|thunder|storm')
                 AND NOT regexp_matches(k.sky, 'chance|possible|later|expected|forecast'), FALSE)
                                                              AS is_rain,
        COALESCE(regexp_matches(k.sky, 'snow|flurr|sleet')
                 AND NOT regexp_matches(k.sky, 'chance|possible|later|expected|forecast'), FALSE)
                                                              AS is_snow,
        CAST(s.home_score AS DOUBLE) + CAST(s.away_score AS DOUBLE) - CAST(s.total_line AS DOUBLE)
                                                              AS total_vs_line
    FROM raw_schedules_history s
    LEFT JOIN sky k ON k.game_id = s.game_id
    WHERE lower(s.roof) IN ('outdoors', 'open')
      AND s.result IS NOT NULL AND s.total_line IS NOT NULL
      AND TRY_CAST(s.temp AS DOUBLE) IS NOT NULL AND TRY_CAST(s.wind AS DOUBLE) IS NOT NULL
),

tagged AS (
    SELECT 'all_outdoor' AS condition, total_vs_line FROM outdoor
    UNION ALL SELECT 'windy', total_vs_line FROM outdoor WHERE wind_mph >= 15
    UNION ALL SELECT 'cold',  total_vs_line FROM outdoor WHERE temp_f <= 32
    UNION ALL SELECT 'rain',  total_vs_line FROM outdoor WHERE is_rain
    UNION ALL SELECT 'snow',  total_vs_line FROM outdoor WHERE is_snow
)

SELECT
    condition,
    count(*)                                        AS games,
    count(*) FILTER (WHERE total_vs_line < 0)       AS unders,
    count(*) FILTER (WHERE total_vs_line > 0)       AS overs,
    count(*) FILTER (WHERE total_vs_line = 0)       AS pushes,
    count(*) FILTER (WHERE total_vs_line < 0)
        / nullif(count(*) FILTER (WHERE total_vs_line <> 0), 0)
                                                    AS under_rate,
    avg(total_vs_line)                              AS avg_total_vs_line
FROM tagged
GROUP BY condition;
