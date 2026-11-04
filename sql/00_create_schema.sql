-- =====================================================================
-- 00_create_schema.sql
-- Purpose : Create the `olist` database and one table per Olist CSV file.
-- Business question: none directly - this is the foundation every
--                    analysis query depends on.
-- Run     : mysql < sql/00_create_schema.sql
-- Notes   :
--   * IDs are 32-character hex strings, so they are stored as VARCHAR(32).
--   * Money is DECIMAL(10,2) (exact), never FLOAT (rounding errors).
--   * Timestamps are DATETIME and may be NULL (e.g. an order not yet delivered).
--   * Indexes are added on every join column so queries stay fast.
--   * Re-running this file drops and rebuilds everything from scratch.
-- =====================================================================

DROP DATABASE IF EXISTS olist;
CREATE DATABASE olist
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_ai_ci;

USE olist;

-- One row = one customer account used for ONE order.
-- customer_unique_id identifies the real person across orders.
CREATE TABLE customers (
    customer_id              VARCHAR(32)  NOT NULL,
    customer_unique_id       VARCHAR(32)  NOT NULL,
    customer_zip_code_prefix CHAR(5)      NOT NULL,  -- kept as text to preserve leading zeros
    customer_city            VARCHAR(64)  NOT NULL,
    customer_state           CHAR(2)      NOT NULL,
    PRIMARY KEY (customer_id),
    INDEX idx_customers_unique_id (customer_unique_id),
    INDEX idx_customers_state (customer_state)
);

-- One row = one zip-code prefix / lat-long point. Many rows per prefix,
-- so there is no natural key; a surrogate auto-increment id is used.
CREATE TABLE geolocation (
    geolocation_id              INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    geolocation_zip_code_prefix CHAR(5)       NOT NULL,
    geolocation_lat             DECIMAL(11,8) NOT NULL,  -- 8 decimals = ~1 mm precision
    geolocation_lng             DECIMAL(11,8) NOT NULL,
    geolocation_city            VARCHAR(64)   NOT NULL,
    geolocation_state           CHAR(2)       NOT NULL,
    PRIMARY KEY (geolocation_id),
    INDEX idx_geolocation_zip (geolocation_zip_code_prefix)
);

-- One row = one order (the order header).
CREATE TABLE orders (
    order_id                      VARCHAR(32) NOT NULL,
    customer_id                   VARCHAR(32) NOT NULL,
    order_status                  VARCHAR(20) NOT NULL,
    order_purchase_timestamp      DATETIME    NOT NULL,
    order_approved_at             DATETIME    NULL,
    order_delivered_carrier_date  DATETIME    NULL,
    order_delivered_customer_date DATETIME    NULL,
    order_estimated_delivery_date DATETIME    NULL,
    PRIMARY KEY (order_id),
    INDEX idx_orders_customer_id (customer_id),
    INDEX idx_orders_status (order_status),
    INDEX idx_orders_purchase_ts (order_purchase_timestamp)
);

-- One row = one item line within an order (an order can have several).
CREATE TABLE order_items (
    order_id            VARCHAR(32)   NOT NULL,
    order_item_id       SMALLINT      NOT NULL,  -- 1, 2, 3 ... within the order
    product_id          VARCHAR(32)   NOT NULL,
    seller_id           VARCHAR(32)   NOT NULL,
    shipping_limit_date DATETIME      NOT NULL,
    price               DECIMAL(10,2) NOT NULL,
    freight_value       DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (order_id, order_item_id),
    INDEX idx_order_items_product_id (product_id),
    INDEX idx_order_items_seller_id (seller_id)
);

-- One row = one payment for an order (an order can be split across
-- several payments, e.g. a voucher plus a credit card).
CREATE TABLE order_payments (
    order_id             VARCHAR(32)   NOT NULL,
    payment_sequential   SMALLINT      NOT NULL,
    payment_type         VARCHAR(20)   NOT NULL,
    payment_installments SMALLINT      NOT NULL,
    payment_value        DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (order_id, payment_sequential)
);

-- One row = one review linked to one order.
-- review_id is NOT unique on its own in the raw file (the same review_id
-- appears against several orders), so the key is (review_id, order_id).
CREATE TABLE order_reviews (
    review_id               VARCHAR(32)  NOT NULL,
    order_id                VARCHAR(32)  NOT NULL,
    review_score            TINYINT      NOT NULL,
    review_comment_title    VARCHAR(100) NULL,
    review_comment_message  TEXT         NULL,
    review_creation_date    DATETIME     NOT NULL,
    review_answer_timestamp DATETIME     NOT NULL,
    PRIMARY KEY (review_id, order_id),
    INDEX idx_order_reviews_order_id (order_id)
);

-- One row = one product. Category is in Portuguese (see translation table).
-- Note: the raw column names misspell "length" as "lenght"; fixed here.
CREATE TABLE products (
    product_id                 VARCHAR(32) NOT NULL,
    product_category_name      VARCHAR(64) NULL,
    product_name_length        SMALLINT    NULL,
    product_description_length SMALLINT    NULL,
    product_photos_qty         SMALLINT    NULL,
    product_weight_g           INT         NULL,
    product_length_cm          SMALLINT    NULL,
    product_height_cm          SMALLINT    NULL,
    product_width_cm           SMALLINT    NULL,
    PRIMARY KEY (product_id),
    INDEX idx_products_category (product_category_name)
);

-- One row = one seller.
CREATE TABLE sellers (
    seller_id              VARCHAR(32) NOT NULL,
    seller_zip_code_prefix CHAR(5)     NOT NULL,
    seller_city            VARCHAR(64) NOT NULL,
    seller_state           CHAR(2)     NOT NULL,
    PRIMARY KEY (seller_id),
    INDEX idx_sellers_state (seller_state)
);

-- One row = one Portuguese category name and its English translation.
CREATE TABLE product_category_name_translation (
    product_category_name         VARCHAR(64) NOT NULL,
    product_category_name_english VARCHAR(64) NOT NULL,
    PRIMARY KEY (product_category_name)
);
