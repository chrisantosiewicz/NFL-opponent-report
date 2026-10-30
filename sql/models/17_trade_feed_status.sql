-- trade_feed_status: one row saying whether the trade check had all its data,
-- for the report's footnote. latest_feed_trade shows how far behind
-- nflverse's trade feed is; in-season trades it lacks come from
-- config/trades_manual.csv and weekly rosters.

CREATE OR REPLACE TABLE trade_feed_status AS
SELECT
    (SELECT COALESCE(bool_and(ok), FALSE) FROM raw_feed_status
     WHERE feed IN ('raw_trades', 'raw_rosters_weekly'))        AS feeds_ok,
    (SELECT MAX(TRY_CAST(trade_date AS DATE)) FROM raw_trades)  AS latest_feed_trade;
