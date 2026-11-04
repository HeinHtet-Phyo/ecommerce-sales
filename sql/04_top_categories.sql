-- =====================================================================
-- 04_top_categories.sql
-- Business question: "Which product categories drive the most revenue?"
-- Run     : mysql -t olist < sql/04_top_categories.sql
-- Export  : python3 -I scripts/export_results.py sql/04_top_categories.sql
--           -> data/exports/04_top_categories.csv
-- Notes   :
--   * Revenue = SUM(order_items.price) for delivered orders only
--     (freight excluded). Money is in Brazilian reais (R$).
--   * Covers ALL delivered orders (no date window).
--   * Category = English name from the translation table. Products with a
--     blank category, or a category missing from the translation table,
--     are shown as 'unknown' (see docs/cleaning_log.md).
--   * "Delivered orders" for a category = delivered orders that contain
--     at least one item from that category. These counts can NOT be added
--     up across categories: one order can contain items from several
--     categories, so it would be counted once in each of them.
-- =====================================================================

USE olist;

-- export: 04_top_categories
WITH category_sales AS (
    -- Step 1: revenue, orders and items for EVERY category.
    SELECT
        COALESCE(t.product_category_name_english, 'unknown') AS category,
        SUM(oi.price)                                         AS revenue,
        COUNT(DISTINCT o.order_id)                            AS delivered_orders,
        COUNT(*)                                              AS items_sold,
        AVG(oi.price)                                         AS avg_item_price
    FROM orders AS o
    JOIN order_items AS oi
        ON oi.order_id = o.order_id
    JOIN products AS p
        ON p.product_id = oi.product_id
    LEFT JOIN product_category_name_translation AS t
        ON t.product_category_name = p.product_category_name
    WHERE o.order_status = 'delivered'
    GROUP BY COALESCE(t.product_category_name_english, 'unknown')
),
category_share AS (
    -- Step 2: each category's share of TOTAL revenue.
    -- SUM(revenue) OVER () adds up revenue across all rows (all categories)
    -- without collapsing them, so every row can be divided by the grand total.
    -- This must happen BEFORE we keep only the top 10: if we limited first,
    -- the total would only be the top 10's revenue and the shares would be
    -- inflated (the top 10 would always add up to 100%).
    SELECT
        category,
        revenue,
        delivered_orders,
        items_sold,
        avg_item_price,
        100 * revenue / SUM(revenue) OVER ()                          AS pct_of_revenue,
        -- Rank by revenue (highest = 1); category name breaks any tie.
        ROW_NUMBER() OVER (ORDER BY revenue DESC, category)           AS revenue_rank
    FROM category_sales
),
top_10 AS (
    -- Step 3: keep only the 10 biggest categories.
    SELECT *
    FROM category_share
    WHERE revenue_rank <= 10
)
-- Step 4: cumulative share = running total of pct_of_revenue, adding one
-- category at a time from rank 1 downwards. Row 3's value is the combined
-- share of the top 3 categories, and row 10's is the share of the top 10.
SELECT
    revenue_rank,
    category,
    ROUND(revenue, 2)                                                 AS revenue,
    delivered_orders,
    items_sold,
    ROUND(avg_item_price, 2)                                          AS avg_item_price,
    ROUND(pct_of_revenue, 2)                                          AS pct_of_revenue,
    ROUND(SUM(pct_of_revenue) OVER (ORDER BY revenue_rank), 2)        AS cumulative_pct_of_revenue
FROM top_10
ORDER BY revenue_rank;
