-- =====================================================================
-- 03_monthly_revenue.sql
-- Business question: "How is revenue trending month by month, and where
--                    are the dips?"
-- Run     : mysql -t olist < sql/03_monthly_revenue.sql
-- Export  : python3 -I scripts/export_results.py sql/03_monthly_revenue.sql
--           -> data/exports/03_monthly_revenue.csv
-- Notes   : - Revenue = SUM(order_items.price) for delivered orders only
--             (freight excluded). Currency: Brazilian reais (R$).
--           - AOV (average order value) = revenue / delivered orders.
--           - Month = month of order_purchase_timestamp.
--           - Trend window is Jan 2017 to Aug 2018 (20 full months).
--             2016 is the launch period with a missing month, and Sep-Oct
--             2018 have no delivered orders (see docs/cleaning_log.md).
--           - Revenue in the window should total R$13,181,027.13.
-- =====================================================================

USE olist;

-- -------------------------------------------------------------------------
-- Monthly revenue, orders and AOV, with month-on-month (MoM) % change.
-- Step 1 (CTE): add up revenue and orders for each month.
-- Step 2 (outer SELECT): LAG() looks back one row (the previous month) so
--         we can compare each month with the one before it.
-- The first month (2017-01) has no previous month, so its MoM columns
-- are NULL (blank in the CSV). That is expected, not missing data.
-- -------------------------------------------------------------------------
-- export: 03_monthly_revenue
WITH monthly AS (
    SELECT
        DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS order_month,
        SUM(oi.price)                                    AS revenue,
        COUNT(DISTINCT o.order_id)                       AS orders
    FROM orders AS o
    JOIN order_items AS oi
        ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
      -- Trend window: 1 Jan 2017 up to (not including) 1 Sep 2018
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp <  '2018-09-01'
    GROUP BY order_month
)
SELECT
    order_month,
    ROUND(revenue, 2)          AS revenue,
    orders,
    ROUND(revenue / orders, 2) AS aov,
    -- % change in revenue vs the previous month
    ROUND(
        100 * (revenue - LAG(revenue) OVER (ORDER BY order_month))
            / LAG(revenue) OVER (ORDER BY order_month),
        2
    )                          AS revenue_mom_pct,
    -- % change in delivered orders vs the previous month
    ROUND(
        100 * (orders - LAG(orders) OVER (ORDER BY order_month))
            / LAG(orders) OVER (ORDER BY order_month),
        2
    )                          AS orders_mom_pct
FROM monthly
ORDER BY order_month;
