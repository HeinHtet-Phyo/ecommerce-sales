-- =============================================================================
-- File:     08_top_sellers_by_state.sql
-- Question: Who are the top 3 sellers in each state by revenue?
-- How to run:
--     mysql olist < sql/08_top_sellers_by_state.sql
--     python3 -I scripts/export_results.py sql/08_top_sellers_by_state.sql
--     (writes data/exports/08_top_sellers_by_state.csv)
-- Notes:
--   * Revenue = SUM(order_items.price), freight excluded, delivered orders only.
--   * "State" here is the SELLER's state (sellers.seller_state), not the
--     customer's. We are ranking sellers, so we group them by where they are
--     based. A seller in SP who ships to customers all over Brazil still counts
--     as an SP seller. Customer state is used in file 05 (revenue by state).
--   * Revenue is credited to the seller of each item (order_items.seller_id),
--     so an order with items from two sellers is split between them.
--   * seller_id is a 32-character code; the data has no seller names.
--     seller_short_id (first 8 characters) is only there to make charts and
--     tables easier to read in Power BI. The full seller_id is the real key.
--   * Ranking uses RANK(), not DENSE_RANK() or ROW_NUMBER(). For example, if two
--     sellers tie for 2nd place:
--       - RANK()       gives 1, 2, 2, 4  -> both tied sellers are kept, so a
--                      state can return more than 3 rows. Nobody is dropped
--                      unfairly and the next rank is skipped.
--       - DENSE_RANK() gives 1, 2, 2, 3  -> no gap, so "top 3" could return
--                      4 or more sellers (ranks 1, 2, 2 and 3).
--       - ROW_NUMBER() gives 1, 2, 3, 4  -> always exactly 3 rows, but which
--                      tied seller gets 3rd vs 4th is arbitrary.
--     RANK() is the fairest reading of "top 3": a seller is in the top 3 if
--     fewer than 3 sellers beat them.
--   * States with fewer than 3 sellers simply return fewer rows.
-- =============================================================================

USE olist;

-- export: 08_top_sellers_by_state
WITH seller_revenue AS (
    -- One row per seller: revenue, delivered orders and items sold.
    SELECT
        s.seller_id,
        s.seller_state,
        s.seller_city,
        SUM(oi.price)                AS revenue,
        COUNT(DISTINCT oi.order_id)  AS delivered_orders,
        COUNT(*)                     AS items_sold
    FROM order_items AS oi
    JOIN orders AS o
        ON o.order_id = oi.order_id
    JOIN sellers AS s
        ON s.seller_id = oi.seller_id
    WHERE o.order_status = 'delivered'
    GROUP BY
        s.seller_id,
        s.seller_state,
        s.seller_city
),
ranked_sellers AS (
    -- Rank each seller within their own state (PARTITION BY restarts the
    -- ranking for every state). SUM() OVER the same partition gives the
    -- state's total seller revenue on every row, so we can work out each
    -- seller's share without a separate GROUP BY.
    SELECT
        seller_id,
        seller_state,
        seller_city,
        revenue,
        delivered_orders,
        items_sold,
        RANK() OVER (PARTITION BY seller_state ORDER BY revenue DESC) AS seller_rank,
        SUM(revenue) OVER (PARTITION BY seller_state)                 AS state_revenue,
        COUNT(*) OVER (PARTITION BY seller_state)                     AS sellers_in_state
    FROM seller_revenue
)
SELECT
    seller_state,
    seller_rank,
    seller_id,
    LEFT(seller_id, 8)                          AS seller_short_id,
    seller_city,
    ROUND(revenue, 2)                           AS revenue,
    delivered_orders,
    items_sold,
    ROUND(100 * revenue / state_revenue, 2)     AS pct_of_state_revenue,
    ROUND(state_revenue, 2)                     AS state_revenue,
    sellers_in_state
FROM ranked_sellers
WHERE seller_rank <= 3
ORDER BY
    state_revenue DESC,
    seller_rank,
    seller_id;
