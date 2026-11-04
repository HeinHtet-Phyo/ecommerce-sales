-- =====================================================================
-- 01_load_data.sql
-- Purpose : Load the 9 Olist CSV files from data/raw/ into the olist tables.
-- Business question: none directly - gets the raw data into MySQL.
-- Run     : from the project root folder (paths below are relative to it):
--             cd "~/Data Analyst Projects/ecommerce-sales"
--             mysql --local-infile=1 < sql/01_load_data.sql
-- Notes   :
--   * LOAD DATA LOCAL INFILE reads the file from YOUR machine (the client).
--     It must be switched on in two places: on the server (SET GLOBAL below)
--     and on the client (--local-infile=1, or local-infile=1 in ~/.my.cnf).
--   * Paths are relative to the folder you run mysql from, so the space in
--     "Data Analyst Projects" never has to appear in this file.
--   * Columns that can be blank are read into a @variable first, then
--     NULLIF(@variable, '') turns an empty string into a real NULL.
--     Without this, MySQL would store a blank date as 0000-00-00 or fail.
--   * Text values in the CSVs are wrapped in double quotes, and some
--     review comments contain line breaks inside the quotes, so every
--     load uses OPTIONALLY ENCLOSED BY '"'.
--   * The reviews and translation files use Windows line endings (\r\n);
--     the rest use Unix line endings (\n).
--   * ESCAPED BY '' switches off MySQL's default backslash escaping.
--     These CSVs never use backslash escapes, but a few reviews (and one
--     seller city) contain a literal backslash. Without this, a review
--     ending in :\" was read as an escaped quote and two rows merged into
--     one, and "\r" in a seller city became an invisible carriage return.
-- =====================================================================

-- Allow the server to accept LOCAL file loads (off by default for security).
SET GLOBAL local_infile = 1;

USE olist;

-- Empty every table first so this file can be re-run safely.
TRUNCATE TABLE customers;
TRUNCATE TABLE geolocation;
TRUNCATE TABLE orders;
TRUNCATE TABLE order_items;
TRUNCATE TABLE order_payments;
TRUNCATE TABLE order_reviews;
TRUNCATE TABLE products;
TRUNCATE TABLE sellers;
TRUNCATE TABLE product_category_name_translation;

-- ---------------------------------------------------------------------
-- customers
-- ---------------------------------------------------------------------
LOAD DATA LOCAL INFILE 'data/raw/olist_customers_dataset.csv'
INTO TABLE customers
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(customer_id, customer_unique_id, customer_zip_code_prefix, customer_city, customer_state);

-- ---------------------------------------------------------------------
-- geolocation (geolocation_id is filled automatically). Some coordinates
-- have 15+ decimal places; they are rounded to 8 (about 1 mm), which is
-- far more precision than any analysis here needs.
-- ---------------------------------------------------------------------
LOAD DATA LOCAL INFILE 'data/raw/olist_geolocation_dataset.csv'
INTO TABLE geolocation
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(geolocation_zip_code_prefix, @lat, @lng, geolocation_city, geolocation_state)
SET
    geolocation_lat = ROUND(@lat, 8),
    geolocation_lng = ROUND(@lng, 8);

-- ---------------------------------------------------------------------
-- orders: the four date columns after the purchase date can be blank
-- (e.g. a cancelled order is never delivered), so they go via @variables.
-- ---------------------------------------------------------------------
LOAD DATA LOCAL INFILE 'data/raw/olist_orders_dataset.csv'
INTO TABLE orders
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(order_id, customer_id, order_status, order_purchase_timestamp,
 @approved_at, @delivered_carrier, @delivered_customer, @estimated_delivery)
SET
    order_approved_at             = NULLIF(@approved_at, ''),
    order_delivered_carrier_date  = NULLIF(@delivered_carrier, ''),
    order_delivered_customer_date = NULLIF(@delivered_customer, ''),
    order_estimated_delivery_date = NULLIF(@estimated_delivery, '');

-- ---------------------------------------------------------------------
-- order_items
-- ---------------------------------------------------------------------
LOAD DATA LOCAL INFILE 'data/raw/olist_order_items_dataset.csv'
INTO TABLE order_items
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(order_id, order_item_id, product_id, seller_id, shipping_limit_date, price, freight_value);

-- ---------------------------------------------------------------------
-- order_payments
-- ---------------------------------------------------------------------
LOAD DATA LOCAL INFILE 'data/raw/olist_order_payments_dataset.csv'
INTO TABLE order_payments
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(order_id, payment_sequential, payment_type, payment_installments, payment_value);

-- ---------------------------------------------------------------------
-- order_reviews: Windows line endings; most reviews have no title or
-- comment, so blank text becomes NULL.
-- ---------------------------------------------------------------------
LOAD DATA LOCAL INFILE 'data/raw/olist_order_reviews_dataset.csv'
INTO TABLE order_reviews
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(review_id, order_id, review_score, @comment_title, @comment_message,
 review_creation_date, review_answer_timestamp)
SET
    review_comment_title   = NULLIF(@comment_title, ''),
    review_comment_message = NULLIF(@comment_message, '');

-- ---------------------------------------------------------------------
-- products: 610 products have no category and no measurements, so every
-- column except the id goes via a @variable and NULLIF.
-- ---------------------------------------------------------------------
LOAD DATA LOCAL INFILE 'data/raw/olist_products_dataset.csv'
INTO TABLE products
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(product_id, @category, @name_len, @desc_len, @photos,
 @weight, @length, @height, @width)
SET
    product_category_name      = NULLIF(@category, ''),
    product_name_length        = NULLIF(@name_len, ''),
    product_description_length = NULLIF(@desc_len, ''),
    product_photos_qty         = NULLIF(@photos, ''),
    product_weight_g           = NULLIF(@weight, ''),
    product_length_cm          = NULLIF(@length, ''),
    product_height_cm          = NULLIF(@height, ''),
    product_width_cm           = NULLIF(@width, '');

-- ---------------------------------------------------------------------
-- sellers
-- ---------------------------------------------------------------------
LOAD DATA LOCAL INFILE 'data/raw/olist_sellers_dataset.csv'
INTO TABLE sellers
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(seller_id, seller_zip_code_prefix, seller_city, seller_state);

-- ---------------------------------------------------------------------
-- product_category_name_translation: Windows line endings. The header
-- line starts with an invisible byte-order mark (BOM); IGNORE 1 LINES
-- skips the header, so the BOM never reaches the table.
-- ---------------------------------------------------------------------
LOAD DATA LOCAL INFILE 'data/raw/product_category_name_translation.csv'
INTO TABLE product_category_name_translation
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(product_category_name, product_category_name_english);

-- ---------------------------------------------------------------------
-- Row-count check. Expected values are the number of records in each CSV
-- (excluding the header), counted with a CSV parser because some review
-- comments span several lines and would inflate a simple line count.
-- ---------------------------------------------------------------------
SELECT 'customers' AS table_name, COUNT(*) AS rows_loaded, 99441 AS rows_expected FROM customers
UNION ALL SELECT 'geolocation', COUNT(*), 1000163 FROM geolocation
UNION ALL SELECT 'orders', COUNT(*), 99441 FROM orders
UNION ALL SELECT 'order_items', COUNT(*), 112650 FROM order_items
UNION ALL SELECT 'order_payments', COUNT(*), 103886 FROM order_payments
UNION ALL SELECT 'order_reviews', COUNT(*), 99224 FROM order_reviews
UNION ALL SELECT 'products', COUNT(*), 32951 FROM products
UNION ALL SELECT 'sellers', COUNT(*), 3095 FROM sellers
UNION ALL SELECT 'product_category_name_translation', COUNT(*), 71 FROM product_category_name_translation;
