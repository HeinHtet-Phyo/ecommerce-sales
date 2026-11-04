-- =====================================================================
-- 07_repeat_customers.sql
-- Business question: "How many customers buy more than once, and what
--                    does that mean for the business?"
-- Run     : mysql -t olist < sql/07_repeat_customers.sql
-- Export  : python3 -I scripts/export_results.py sql/07_repeat_customers.sql
--           -> data/exports/07a_repeat_vs_onetime.csv
--           -> data/exports/07b_orders_per_customer.csv
-- Notes   :
--   * Base = DELIVERED orders only, so revenue matches every other file
--     (96,478 orders, R$13,221,498.11, freight excluded).
--   * A customer = customers.customer_unique_id.
--
--   THE customer_id TRAP:
--   In this dataset customer_id is created fresh for EVERY order, so one
--   real person who orders three times has three different customer_ids
--   but one customer_unique_id. If we counted customers by customer_id,
--   every "customer" would have exactly one order. Checked on delivered
--   orders: grouping by customer_id gives 96,478 "customers" and
--   0 repeat customers. Grouping by customer_unique_id gives 93,358
--   real customers, some of whom buy more than once.
-- =====================================================================

USE olist;

-- ---------------------------------------------------------------------
-- 07a: One-time vs repeat customers
-- Step 1 (order_revenue): add up item prices so we have ONE row per
--         delivered order. Doing this first stops orders with several
--         items being counted more than once.
-- Step 2 (customer_summary): ONE row per real customer, with their
--         number of delivered orders and total revenue.
-- Step 3: label each customer as one-time or repeat, then total up.
-- The % columns use SUM(...) OVER (), a window function that gives the
-- grand total across both groups without a separate query.
-- ---------------------------------------------------------------------
-- export: 07a_repeat_vs_onetime
WITH order_revenue AS (
    SELECT
        o.order_id,
        o.customer_id,
        SUM(oi.price) AS order_revenue
    FROM orders AS o
    JOIN order_items AS oi
        ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY
        o.order_id,
        o.customer_id
),
customer_summary AS (
    SELECT
        c.customer_unique_id,
        COUNT(orv.order_id)    AS delivered_orders,
        SUM(orv.order_revenue) AS customer_revenue
    FROM order_revenue AS orv
    JOIN customers AS c
        ON c.customer_id = orv.customer_id
    GROUP BY c.customer_unique_id
),
customer_groups AS (
    SELECT
        CASE
            WHEN delivered_orders = 1 THEN 'One-time (1 order)'
            ELSE 'Repeat (2+ orders)'
        END                   AS customer_group,
        COUNT(*)              AS customers,
        SUM(delivered_orders) AS orders,
        SUM(customer_revenue) AS revenue
    FROM customer_summary
    GROUP BY customer_group
)
SELECT
    customer_group,
    customers,
    ROUND(100 * customers / SUM(customers) OVER (), 2) AS pct_of_customers,
    orders,
    ROUND(revenue, 2)                                  AS revenue,
    ROUND(100 * revenue / SUM(revenue) OVER (), 2)     AS pct_of_revenue,
    ROUND(revenue / customers, 2)                      AS revenue_per_customer,
    ROUND(revenue / orders, 2)                         AS aov
FROM customer_groups
ORDER BY customer_group;

-- ---------------------------------------------------------------------
-- 07b: How many delivered orders does each customer place?
-- Same first two steps as 07a, then customers are bucketed into
-- 1, 2, 3 and 4+ orders (4+ is grouped because very few people order
-- that often). bucket_order is only there to sort the rows correctly.
-- ---------------------------------------------------------------------
-- export: 07b_orders_per_customer
WITH order_revenue AS (
    SELECT
        o.order_id,
        o.customer_id,
        SUM(oi.price) AS order_revenue
    FROM orders AS o
    JOIN order_items AS oi
        ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY
        o.order_id,
        o.customer_id
),
customer_summary AS (
    SELECT
        c.customer_unique_id,
        COUNT(orv.order_id) AS delivered_orders
    FROM order_revenue AS orv
    JOIN customers AS c
        ON c.customer_id = orv.customer_id
    GROUP BY c.customer_unique_id
),
customer_buckets AS (
    SELECT
        LEAST(delivered_orders, 4) AS bucket_order,
        CASE
            WHEN delivered_orders >= 4 THEN '4+'
            ELSE CAST(delivered_orders AS CHAR)
        END                        AS orders_per_customer,
        delivered_orders
    FROM customer_summary
)
SELECT
    orders_per_customer,
    COUNT(*)                                         AS customers,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_customers,
    SUM(delivered_orders)                            AS orders
FROM customer_buckets
GROUP BY
    bucket_order,
    orders_per_customer
ORDER BY bucket_order;
