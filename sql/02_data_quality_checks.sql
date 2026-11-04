-- =====================================================================
-- 02_data_quality_checks.sql
-- Purpose : Check the loaded data for problems BEFORE any analysis, so
--           every number later in the project can be trusted.
-- Business question: "Can we trust this data, and what rules do we need
--                    to apply so revenue, delivery and customer numbers
--                    are correct?"
-- Run     : mysql -t olist < sql/02_data_quality_checks.sql
-- Output  : read-only checks (this file changes nothing). Every decision
--           made from these results is written up in docs/cleaning_log.md.
-- =====================================================================

USE olist;

-- ---------------------------------------------------------------------
-- CHECK 1: Order statuses
-- Only 'delivered' orders count as revenue, so we need to know how many
-- orders sit in every other status.
-- ---------------------------------------------------------------------
SELECT
    order_status,
    COUNT(*)                                          AS orders,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_orders
FROM orders
GROUP BY order_status
ORDER BY orders DESC;

-- ---------------------------------------------------------------------
-- CHECK 2: Nulls in key date columns, split by status
-- A missing delivery date is expected for a cancelled order, but NOT
-- for a delivered one (we can't tell if it was late).
-- ---------------------------------------------------------------------
SELECT
    order_status,
    COUNT(*)                                        AS orders,
    SUM(order_approved_at IS NULL)                  AS null_approved_at,
    SUM(order_delivered_carrier_date IS NULL)       AS null_delivered_carrier,
    SUM(order_delivered_customer_date IS NULL)      AS null_delivered_customer,
    SUM(order_estimated_delivery_date IS NULL)      AS null_estimated_delivery
FROM orders
GROUP BY order_status
ORDER BY orders DESC;

-- ---------------------------------------------------------------------
-- CHECK 3: Nulls in other key columns
-- ---------------------------------------------------------------------
SELECT
    'products'                          AS table_name,
    'product_category_name'             AS column_name,
    SUM(product_category_name IS NULL)  AS null_rows,
    COUNT(*)                            AS total_rows
FROM products
UNION ALL
SELECT
    'customers',
    'customer_unique_id',
    SUM(customer_unique_id IS NULL OR customer_unique_id = ''),
    COUNT(*)
FROM customers;

-- ---------------------------------------------------------------------
-- CHECK 4: Duplicate IDs
-- Primary keys already stop exact duplicates in most tables, so this
-- mainly confirms the load. review_id is the exception: it is allowed
-- to repeat (see check 7).
-- ---------------------------------------------------------------------
SELECT 'orders.order_id' AS id_column, COUNT(*) - COUNT(DISTINCT order_id) AS duplicate_rows FROM orders
UNION ALL SELECT 'customers.customer_id', COUNT(*) - COUNT(DISTINCT customer_id) FROM customers
UNION ALL SELECT 'products.product_id',   COUNT(*) - COUNT(DISTINCT product_id)  FROM products
UNION ALL SELECT 'sellers.seller_id',     COUNT(*) - COUNT(DISTINCT seller_id)   FROM sellers
UNION ALL SELECT 'order_reviews.review_id', COUNT(*) - COUNT(DISTINCT review_id) FROM order_reviews;

-- ---------------------------------------------------------------------
-- CHECK 5: customer_id vs customer_unique_id
-- customer_id is created fresh for every order, so it can't be used to
-- count repeat customers. customer_unique_id is the real person.
-- ---------------------------------------------------------------------
SELECT
    COUNT(*)                            AS customer_id_rows,
    COUNT(DISTINCT customer_unique_id)  AS unique_customers,
    COUNT(*) - COUNT(DISTINCT customer_unique_id) AS extra_ids_from_repeat_orders
FROM customers;

-- ---------------------------------------------------------------------
-- CHECK 6: Orders with no items or no payment, by status
-- NOT EXISTS returns orders that have no matching row in the other table.
-- ---------------------------------------------------------------------
SELECT
    o.order_status,
    COUNT(*) AS orders_with_no_items
FROM orders AS o
WHERE NOT EXISTS (
    SELECT 1
    FROM order_items AS oi
    WHERE oi.order_id = o.order_id
)
GROUP BY o.order_status
ORDER BY orders_with_no_items DESC;

SELECT
    o.order_status,
    COUNT(*) AS orders_with_no_payment
FROM orders AS o
WHERE NOT EXISTS (
    SELECT 1
    FROM order_payments AS p
    WHERE p.order_id = o.order_id
)
GROUP BY o.order_status;

-- ---------------------------------------------------------------------
-- CHECK 7: Reviews
-- (a) Orders with more than one review - we keep only the latest one.
-- (b) Of those, how many have reviews with DIFFERENT scores (so the
--     choice actually matters).
-- (c) Orders with no review at all.
-- ---------------------------------------------------------------------
WITH reviews_per_order AS (
    SELECT
        order_id,
        COUNT(*)            AS review_count,
        MIN(review_score)   AS min_score,
        MAX(review_score)   AS max_score
    FROM order_reviews
    GROUP BY order_id
)
SELECT
    SUM(review_count > 1)                             AS orders_with_multiple_reviews,
    SUM(CASE WHEN review_count > 1 THEN review_count END) AS review_rows_on_those_orders,
    SUM(review_count > 1 AND min_score <> max_score)  AS multi_review_orders_with_different_scores
FROM reviews_per_order;

SELECT
    COUNT(*) AS orders_with_no_review
FROM orders AS o
WHERE NOT EXISTS (
    SELECT 1
    FROM order_reviews AS r
    WHERE r.order_id = o.order_id
);

-- (d) Can "latest review" be decided without ties? If the latest
--     review_answer_timestamp is never shared within an order, yes.
SELECT
    COUNT(*) AS orders_with_tied_latest_review
FROM (
    SELECT
        order_id
    FROM order_reviews
    GROUP BY order_id
    HAVING COUNT(*) > 1
       AND COUNT(DISTINCT review_answer_timestamp) < COUNT(*)
) AS tied;

-- ---------------------------------------------------------------------
-- CHECK 8: Product categories with no English translation
-- Blank categories and the two categories missing from the translation
-- table will be shown as 'unknown'.
-- ---------------------------------------------------------------------
SELECT
    COALESCE(p.product_category_name, '(blank)') AS category_portuguese,
    COUNT(*)                                      AS products
FROM products AS p
LEFT JOIN product_category_name_translation AS t
    ON t.product_category_name = p.product_category_name
WHERE t.product_category_name IS NULL
GROUP BY p.product_category_name
ORDER BY products DESC;

-- How much delivered revenue falls into 'unknown'?
SELECT
    COALESCE(t.product_category_name_english, 'unknown') = 'unknown' AS is_unknown_category,
    COUNT(DISTINCT oi.order_id)  AS delivered_orders,
    SUM(oi.price)                AS revenue
FROM orders AS o
JOIN order_items AS oi
    ON oi.order_id = o.order_id
JOIN products AS p
    ON p.product_id = oi.product_id
LEFT JOIN product_category_name_translation AS t
    ON t.product_category_name = p.product_category_name
WHERE o.order_status = 'delivered'
GROUP BY is_unknown_category;

-- ---------------------------------------------------------------------
-- CHECK 9: Orphan rows (foreign keys with no match)
-- ---------------------------------------------------------------------
SELECT 'orders without a customer' AS check_name, COUNT(*) AS rows_found
FROM orders AS o
LEFT JOIN customers AS c ON c.customer_id = o.customer_id
WHERE c.customer_id IS NULL
UNION ALL
SELECT 'order items without a product', COUNT(*)
FROM order_items AS oi
LEFT JOIN products AS p ON p.product_id = oi.product_id
WHERE p.product_id IS NULL
UNION ALL
SELECT 'order items without a seller', COUNT(*)
FROM order_items AS oi
LEFT JOIN sellers AS s ON s.seller_id = oi.seller_id
WHERE s.seller_id IS NULL;

-- ---------------------------------------------------------------------
-- CHECK 10: Impossible or suspicious values
-- ---------------------------------------------------------------------
SELECT
    SUM(price <= 0)          AS items_zero_or_negative_price,
    SUM(freight_value < 0)   AS items_negative_freight,
    SUM(freight_value = 0)   AS items_free_freight
FROM order_items;

SELECT
    SUM(order_delivered_customer_date < order_purchase_timestamp) AS delivered_before_purchase,
    SUM(order_status <> 'delivered'
        AND order_delivered_customer_date IS NOT NULL)            AS not_delivered_status_but_has_delivery_date
FROM orders;

-- ---------------------------------------------------------------------
-- CHECK 11: How should "late" be measured?
-- The estimated delivery date is always midnight (no time part). Comparing
-- full timestamps would mark an order delivered at 2pm ON the promised
-- day as late. Comparing calendar dates treats that as on time.
-- ---------------------------------------------------------------------
SELECT
    COUNT(*)                                                                 AS delivered_with_dates,
    SUM(TIME(order_estimated_delivery_date) <> '00:00:00')                   AS estimates_with_a_time_part,
    SUM(order_delivered_customer_date > order_estimated_delivery_date)       AS late_by_timestamp,
    SUM(DATE(order_delivered_customer_date) > DATE(order_estimated_delivery_date)) AS late_by_calendar_date
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL;

-- ---------------------------------------------------------------------
-- CHECK 12: Date range and orders per month
-- Months at the start and end of the data are very sparse; they would
-- distort a trend chart (see cleaning_log.md for the decision).
-- ---------------------------------------------------------------------
SELECT
    MIN(order_purchase_timestamp) AS first_order,
    MAX(order_purchase_timestamp) AS last_order
FROM orders;

SELECT
    DATE_FORMAT(order_purchase_timestamp, '%Y-%m') AS order_month,
    COUNT(*)                                       AS all_orders,
    SUM(order_status = 'delivered')                AS delivered_orders
FROM orders
GROUP BY order_month
ORDER BY order_month;

-- ---------------------------------------------------------------------
-- CHECK 13: Headline totals the analysis should reconcile to
-- ---------------------------------------------------------------------
SELECT
    COUNT(DISTINCT o.order_id) AS delivered_orders,
    SUM(oi.price)              AS revenue_excl_freight,
    SUM(oi.freight_value)      AS freight
FROM orders AS o
JOIN order_items AS oi
    ON oi.order_id = o.order_id
WHERE o.order_status = 'delivered';
