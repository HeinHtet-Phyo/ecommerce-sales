-- =====================================================================
-- 09_powerbi_views.sql
-- Purpose : Build clean, analysis-ready views for the Power BI dashboard,
--           arranged as a simple star schema, and export each one to CSV.
-- Business question: all four - this is the data model the dashboard
--                    uses to answer them interactively.
-- Run     : mysql olist < sql/09_powerbi_views.sql > /dev/null
--                                         (create views; the export SELECTs at
--                                          the bottom print ~200k rows, so the
--                                          output is discarded)
--           python3 -I scripts/export_results.py sql/09_powerbi_views.sql data/exports/powerbi
--                                                            (create + export CSVs)
--
-- Star schema (fact tables in the middle, dimension tables around them):
--
--                 dim_date (built in Power BI with DAX)
--                     |                  |
--   dim_seller --- fact_sales        fact_orders --- dim_state
--                     |      \        /    |
--                     |     dim_customer   |
--                     +------ dim_state ---+
--
--   fact_sales  : one row per ORDER ITEM  -> revenue by category / seller
--   fact_orders : one row per ORDER       -> delivery and review metrics
--   dim_*       : one row per thing we filter or group by
--
-- Why a star schema is good for Power BI:
--   * Each filter (date, state, seller, customer) lives in ONE small
--     table and flows one way into the facts, so slicers behave
--     predictably and DAX measures stay simple.
--   * Facts hold numbers, dimensions hold labels - no repeated text,
--     smaller model, faster visuals.
--   * Two facts are needed because the grains differ: revenue is per
--     item, but "late" and "review score" belong to the whole order.
--     Putting review score on every item row would count a 3-item
--     order's review three times in an average.
--
-- All business rules match docs/cleaning_log.md: delivered orders only,
-- revenue = price excl. freight, late = calendar-date comparison, latest
-- review per order, customer = customer_unique_id, 'unknown' category.
-- =====================================================================

USE olist;

-- ---------------------------------------------------------------------
-- fact_sales: one row per item in a delivered order.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW fact_sales AS
SELECT
    oi.order_id,
    oi.order_item_id,
    DATE(o.order_purchase_timestamp)                       AS order_date,
    c.customer_unique_id,
    c.customer_state,
    oi.product_id,
    COALESCE(t.product_category_name_english, 'unknown')  AS category,
    oi.seller_id,
    oi.price,
    oi.freight_value
FROM order_items AS oi
JOIN orders AS o
    ON o.order_id = oi.order_id
JOIN customers AS c
    ON c.customer_id = o.customer_id
JOIN products AS p
    ON p.product_id = oi.product_id
LEFT JOIN product_category_name_translation AS t   -- LEFT JOIN keeps products with no translation
    ON t.product_category_name = p.product_category_name
WHERE o.order_status = 'delivered';

-- ---------------------------------------------------------------------
-- fact_orders: one row per delivered order, with delivery and review facts.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW fact_orders AS
WITH order_totals AS (
    -- Roll items up to one row per order.
    SELECT
        order_id,
        COUNT(*)    AS item_count,
        SUM(price)  AS order_revenue
    FROM order_items
    GROUP BY order_id
),
latest_review AS (
    -- Some orders have 2+ reviews; number them newest first and keep #1.
    SELECT
        order_id,
        review_score,
        ROW_NUMBER() OVER (
            PARTITION BY order_id
            ORDER BY review_answer_timestamp DESC
        ) AS review_rank
    FROM order_reviews
)
SELECT
    o.order_id,
    DATE(o.order_purchase_timestamp) AS order_date,
    c.customer_unique_id,
    c.customer_state,
    ot.item_count,
    ot.order_revenue,
    -- 1 if we know when the customer received it, else 0
    CASE WHEN o.order_delivered_customer_date IS NOT NULL THEN 1 ELSE 0 END AS has_delivery_date,
    -- Late = delivered on a later calendar day than estimated.
    -- NULL (blank in Power BI) when there is no delivery date.
    CASE
        WHEN o.order_delivered_customer_date IS NULL THEN NULL
        WHEN DATE(o.order_delivered_customer_date) > DATE(o.order_estimated_delivery_date) THEN 1
        ELSE 0
    END AS is_late,
    CASE
        WHEN DATE(o.order_delivered_customer_date) > DATE(o.order_estimated_delivery_date)
            THEN DATEDIFF(o.order_delivered_customer_date, o.order_estimated_delivery_date)
    END AS days_late,
    DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp) AS delivery_days,
    lr.review_score,
    CASE
        WHEN o.order_delivered_customer_date IS NULL THEN 'Unknown'
        WHEN DATE(o.order_delivered_customer_date) > DATE(o.order_estimated_delivery_date) THEN 'Late'
        ELSE 'On time'
    END AS late_status
FROM orders AS o
JOIN customers AS c
    ON c.customer_id = o.customer_id
JOIN order_totals AS ot
    ON ot.order_id = o.order_id
LEFT JOIN latest_review AS lr          -- LEFT JOIN: orders with no review are kept, score is NULL
    ON lr.order_id = o.order_id
   AND lr.review_rank = 1
WHERE o.order_status = 'delivered';

-- ---------------------------------------------------------------------
-- dim_customer: one row per real customer (customer_unique_id) with a
-- delivered order, labelled One-time or Repeat (all-time).
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW dim_customer AS
WITH customer_orders AS (
    SELECT
        c.customer_unique_id,
        c.customer_state,
        o.order_id,
        -- A few people moved state between orders; rank their orders
        -- newest first so we can label them with their latest state.
        ROW_NUMBER() OVER (
            PARTITION BY c.customer_unique_id
            ORDER BY o.order_purchase_timestamp DESC
        ) AS order_recency
    FROM orders AS o
    JOIN customers AS c
        ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
)
SELECT
    customer_unique_id,
    MAX(CASE WHEN order_recency = 1 THEN customer_state END) AS customer_state,
    COUNT(*)                                                 AS delivered_orders,
    CASE WHEN COUNT(*) > 1 THEN 'Repeat' ELSE 'One-time' END AS customer_type
FROM customer_orders
GROUP BY customer_unique_id;

-- ---------------------------------------------------------------------
-- dim_seller: one row per seller. Seller IDs are long hashes with no
-- names in the data, so a short 8-character ID is added for readability.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW dim_seller AS
SELECT
    seller_id,
    LEFT(seller_id, 8) AS seller_short_id,
    seller_city,
    seller_state
FROM sellers;

-- ---------------------------------------------------------------------
-- dim_state: the 27 Brazilian states (26 states + the Federal District)
-- with full names and the 5 official macro-regions, for nicer labels and
-- a region-level slicer. Hard-coded because it is fixed reference data.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW dim_state AS
SELECT
    state_code,
    state_name,
    region
FROM (
    VALUES
        ROW('AC', 'Acre',                'North'),
        ROW('AL', 'Alagoas',             'Northeast'),
        ROW('AM', 'Amazonas',            'North'),
        ROW('AP', 'Amapá',               'North'),
        ROW('BA', 'Bahia',               'Northeast'),
        ROW('CE', 'Ceará',               'Northeast'),
        ROW('DF', 'Distrito Federal',    'Centre-West'),
        ROW('ES', 'Espírito Santo',      'Southeast'),
        ROW('GO', 'Goiás',               'Centre-West'),
        ROW('MA', 'Maranhão',            'Northeast'),
        ROW('MG', 'Minas Gerais',        'Southeast'),
        ROW('MS', 'Mato Grosso do Sul',  'Centre-West'),
        ROW('MT', 'Mato Grosso',         'Centre-West'),
        ROW('PA', 'Pará',                'North'),
        ROW('PB', 'Paraíba',             'Northeast'),
        ROW('PE', 'Pernambuco',          'Northeast'),
        ROW('PI', 'Piauí',               'Northeast'),
        ROW('PR', 'Paraná',              'South'),
        ROW('RJ', 'Rio de Janeiro',      'Southeast'),
        ROW('RN', 'Rio Grande do Norte', 'Northeast'),
        ROW('RO', 'Rondônia',            'North'),
        ROW('RR', 'Roraima',             'North'),
        ROW('RS', 'Rio Grande do Sul',   'South'),
        ROW('SC', 'Santa Catarina',      'South'),
        ROW('SE', 'Sergipe',             'Northeast'),
        ROW('SP', 'São Paulo',           'Southeast'),
        ROW('TO', 'Tocantins',           'North')
) AS states (state_code, state_name, region);

-- =====================================================================
-- Exports: one CSV per view, written to data/exports/powerbi/ by
-- scripts/export_results.py. (The script re-runs everything above
-- before each export; CREATE OR REPLACE makes that harmless.)
-- =====================================================================

-- export: fact_sales
SELECT * FROM fact_sales ORDER BY order_date, order_id, order_item_id;

-- export: fact_orders
SELECT * FROM fact_orders ORDER BY order_date, order_id;

-- export: dim_customer
SELECT * FROM dim_customer ORDER BY customer_unique_id;

-- export: dim_seller
SELECT * FROM dim_seller ORDER BY seller_id;

-- export: dim_state
SELECT * FROM dim_state ORDER BY state_code;
