-- =====================================================================
-- 05_revenue_by_state.sql
-- Business question: "Which customer states drive the most revenue, and
--                    where is delivery worst?"
-- Run     : mysql -t olist < sql/05_revenue_by_state.sql
-- Export  : python3 -I scripts/export_results.py sql/05_revenue_by_state.sql
--           -> data/exports/05_revenue_by_state.csv
-- Notes   :
--   * State = the CUSTOMER's state (customers.customer_state), i.e. where
--     the order was delivered to, not where the seller is.
--   * Revenue = SUM(order_items.price), freight excluded, delivered
--     orders only (all dates, not just the trend window).
--   * Late = DATE(delivered) > DATE(estimated). The base for % late is
--     delivered orders WITH a delivery date (8 orders have none; they
--     still count towards revenue and orders).
--   * Delivery days = DATEDIFF(delivered date, purchase date), i.e. how
--     many days the customer waited.
--   * Checks: 27 rows; revenue sums to 13,221,498.11; orders to 96,478;
--     late orders to 6,534; orders with a delivery date to 96,470.
-- =====================================================================

USE olist;

-- export: 05_revenue_by_state
-- Step 1 (order_revenue): squash order_items down to ONE row per order.
-- Revenue lives at item level, but "late" is an order-level fact. If we
-- joined items straight to the state totals, an order with 3 items would
-- be counted as 3 late orders and skew % late. So we total the price per
-- order first, then aggregate by state.
WITH order_revenue AS (
    SELECT
        o.order_id,
        c.customer_state,
        SUM(oi.price) AS order_revenue,
        -- 1 = late, 0 = on time, NULL = no delivery date (left out of % late)
        CASE
            WHEN o.order_delivered_customer_date IS NULL THEN NULL
            WHEN DATE(o.order_delivered_customer_date) > DATE(o.order_estimated_delivery_date) THEN 1
            ELSE 0
        END AS is_late,
        DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp) AS delivery_days
    FROM orders AS o
    JOIN customers AS c
        ON c.customer_id = o.customer_id
    JOIN order_items AS oi
        ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY
        o.order_id,
        c.customer_state,
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date,
        o.order_purchase_timestamp
),

-- Step 2 (state_summary): one row per customer state.
state_summary AS (
    SELECT
        customer_state,
        SUM(order_revenue)    AS revenue,
        COUNT(*)              AS delivered_orders,   -- one row per order, so COUNT(*) = orders
        SUM(is_late)          AS late_orders,        -- NULLs (no delivery date) are ignored
        COUNT(is_late)        AS orders_with_delivery_date,
        AVG(delivery_days)    AS avg_delivery_days   -- AVG ignores NULLs too
    FROM order_revenue
    GROUP BY customer_state
)

-- Step 3: final figures. SUM(revenue) OVER () is a window function that
-- gives the grand total on every row, so we can work out each state's share.
SELECT
    customer_state,
    ROUND(revenue, 2)                                       AS revenue,
    delivered_orders,
    ROUND(revenue / delivered_orders, 2)                    AS aov,
    ROUND(100 * revenue / SUM(revenue) OVER (), 2)          AS pct_of_revenue,
    late_orders,
    orders_with_delivery_date,
    ROUND(100 * late_orders / orders_with_delivery_date, 2) AS pct_late,
    ROUND(avg_delivery_days, 2)                             AS avg_delivery_days
FROM state_summary
ORDER BY revenue DESC;
