-- =====================================================================
-- File:     06_late_delivery_impact.sql
-- Question: Do late deliveries hurt customer review scores, and by how much?
-- Run:      mysql olist < sql/06_late_delivery_impact.sql
-- Export:   python3 -I scripts/export_results.py sql/06_late_delivery_impact.sql
--
-- Notes:
--   * Base = delivered orders WITH a customer delivery date (96,470 orders).
--     The 8 delivered orders with no delivery date are left out, because we
--     cannot tell whether they were late (see docs/cleaning_log.md).
--   * Late = DATE(delivered) > DATE(estimated). The estimated date is always
--     midnight, so we compare calendar dates: arriving on the promised day
--     counts as on time.
--   * Days late = DATEDIFF(delivered, estimated). DATEDIFF already ignores
--     the time of day, so it matches the calendar-date rule above.
--   * Review score = the customer's LATEST review for the order. Orders with
--     no review still count towards % late, but are left out of score metrics.
--   * Each exported query repeats the same CTEs, because the export script
--     runs every query on its own.
-- =====================================================================

USE olist;


-- ---------------------------------------------------------------------
-- 06a: How many delivered orders arrive late, and by how many days?
-- ---------------------------------------------------------------------
-- export: 06a_late_delivery_overall
WITH delivered_orders AS (
    -- One row per delivered order that has a delivery date, flagged late or not
    SELECT
        o.order_id,
        CASE
            WHEN DATE(o.order_delivered_customer_date) > DATE(o.order_estimated_delivery_date) THEN 1
            ELSE 0
        END AS is_late,
        DATEDIFF(o.order_delivered_customer_date, o.order_estimated_delivery_date) AS days_vs_estimate
    FROM orders AS o
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
)
SELECT
    COUNT(*) AS total_orders,
    SUM(is_late) AS late_orders,
    ROUND(100 * SUM(is_late) / COUNT(*), 2) AS pct_late,
    -- AVG ignores NULLs, so only late orders are averaged here
    ROUND(AVG(CASE WHEN is_late = 1 THEN days_vs_estimate END), 2) AS avg_days_late
FROM delivered_orders;


-- ---------------------------------------------------------------------
-- 06b: Review scores for late vs on-time orders
-- ---------------------------------------------------------------------
-- export: 06b_review_late_vs_ontime
WITH latest_review AS (
    -- Rank each order's reviews, newest answer first; rank 1 = latest review
    SELECT
        order_id,
        review_score,
        ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY review_answer_timestamp DESC) AS review_rank
    FROM order_reviews
),
delivered_orders AS (
    -- Delivered orders with a delivery date, labelled Late / On time,
    -- with their latest review score (NULL if the order has no review)
    SELECT
        o.order_id,
        CASE
            WHEN DATE(o.order_delivered_customer_date) > DATE(o.order_estimated_delivery_date) THEN 'Late'
            ELSE 'On time'
        END AS delivery_group,
        lr.review_score
    FROM orders AS o
    LEFT JOIN latest_review AS lr
        ON lr.order_id = o.order_id
       AND lr.review_rank = 1
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
),
group_summary AS (
    SELECT
        delivery_group,
        COUNT(*) AS orders,
        COUNT(review_score) AS reviewed_orders,   -- COUNT(column) skips orders with no review
        AVG(review_score) AS avg_score,
        SUM(CASE WHEN review_score = 1 THEN 1 ELSE 0 END) AS one_star_reviews,
        SUM(CASE WHEN review_score = 5 THEN 1 ELSE 0 END) AS five_star_reviews
    FROM delivered_orders
    GROUP BY delivery_group
)
SELECT
    delivery_group,
    orders,
    reviewed_orders,
    ROUND(avg_score, 2) AS avg_review_score,
    ROUND(100 * one_star_reviews / reviewed_orders, 2) AS pct_1_star,
    ROUND(100 * five_star_reviews / reviewed_orders, 2) AS pct_5_star,
    -- Gap = on-time average minus this group's average.
    -- The window MAX(...) OVER () picks the on-time average and puts it on
    -- every row, so the 'Late' row shows how many points lower late orders score.
    ROUND(MAX(CASE WHEN delivery_group = 'On time' THEN avg_score END) OVER () - avg_score, 2)
        AS score_gap_vs_on_time
FROM group_summary
ORDER BY delivery_group DESC;   -- 'On time' first, then 'Late'


-- ---------------------------------------------------------------------
-- 06c: Full 1-5 star distribution for late vs on-time orders
-- ---------------------------------------------------------------------
-- export: 06c_review_distribution
WITH latest_review AS (
    SELECT
        order_id,
        review_score,
        ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY review_answer_timestamp DESC) AS review_rank
    FROM order_reviews
),
reviewed_orders AS (
    -- Inner join: only orders that have a review are needed here
    SELECT
        o.order_id,
        CASE
            WHEN DATE(o.order_delivered_customer_date) > DATE(o.order_estimated_delivery_date) THEN 'Late'
            ELSE 'On time'
        END AS delivery_group,
        lr.review_score
    FROM orders AS o
    JOIN latest_review AS lr
        ON lr.order_id = o.order_id
       AND lr.review_rank = 1
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
),
score_counts AS (
    SELECT
        delivery_group,
        review_score,
        COUNT(*) AS reviewed_orders
    FROM reviewed_orders
    GROUP BY
        delivery_group,
        review_score
)
SELECT
    delivery_group,
    review_score,
    reviewed_orders,
    -- Share of the group's reviews: divide by the group total, which
    -- SUM(...) OVER (PARTITION BY delivery_group) puts on every row
    ROUND(100 * reviewed_orders / SUM(reviewed_orders) OVER (PARTITION BY delivery_group), 2)
        AS pct_of_group
FROM score_counts
ORDER BY
    delivery_group DESC,
    review_score;


-- ---------------------------------------------------------------------
-- 06d: Does the score get worse the later the order arrives?
-- ---------------------------------------------------------------------
-- export: 06d_review_by_days_late
WITH latest_review AS (
    SELECT
        order_id,
        review_score,
        ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY review_answer_timestamp DESC) AS review_rank
    FROM order_reviews
),
delivered_orders AS (
    SELECT
        o.order_id,
        DATEDIFF(o.order_delivered_customer_date, o.order_estimated_delivery_date) AS days_vs_estimate,
        lr.review_score
    FROM orders AS o
    LEFT JOIN latest_review AS lr
        ON lr.order_id = o.order_id
       AND lr.review_rank = 1
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
),
bucketed AS (
    -- days_vs_estimate <= 0 means delivered on or before the promised day
    SELECT
        order_id,
        review_score,
        CASE
            WHEN days_vs_estimate <= 0 THEN 1
            WHEN days_vs_estimate <= 3 THEN 2
            WHEN days_vs_estimate <= 7 THEN 3
            WHEN days_vs_estimate <= 14 THEN 4
            ELSE 5
        END AS bucket_order,
        CASE
            WHEN days_vs_estimate <= 0 THEN 'On time or early'
            WHEN days_vs_estimate <= 3 THEN '1-3 days late'
            WHEN days_vs_estimate <= 7 THEN '4-7 days late'
            WHEN days_vs_estimate <= 14 THEN '8-14 days late'
            ELSE '15+ days late'
        END AS lateness_bucket
    FROM delivered_orders
)
SELECT
    bucket_order,
    lateness_bucket,
    COUNT(*) AS orders,
    COUNT(review_score) AS reviewed_orders,
    ROUND(AVG(review_score), 2) AS avg_review_score,
    ROUND(100 * SUM(CASE WHEN review_score = 1 THEN 1 ELSE 0 END) / COUNT(review_score), 2) AS pct_1_star
FROM bucketed
GROUP BY
    bucket_order,
    lateness_bucket
ORDER BY bucket_order;
