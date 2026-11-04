# Data dictionary: Olist e-commerce database

This document describes the `olist` MySQL database **as built by `sql/00_create_schema.sql` (tables) and `sql/01_load_data.sql` (data load)**. The raw tables are not modified after loading; all cleaning rules are applied inside the analysis queries (see `docs/cleaning_log.md`).

- Source: Olist Brazilian e-commerce public dataset, 9 CSV files, one table each.
- Orders placed: 4 September 2016 to 17 October 2018.
- Money: Brazilian reais (R$), stored as `DECIMAL(10,2)`.
- IDs: 32-character hex strings, stored as `VARCHAR(32)`.
- Row counts below come from `SELECT COUNT(*)` run against the loaded database.

## Contents

1. [Tables at a glance](#tables-at-a-glance)
2. [Relationship diagram](#relationship-diagram)
3. [How to join](#how-to-join)
4. [Table details](#table-details)
5. [Business definitions](#business-definitions)

---

## Tables at a glance

| Table | One row means | Rows | Primary key |
|---|---|---:|---|
| `orders` | One order (the order header) | 99,441 | `order_id` |
| `customers` | One customer account used for one order | 99,441 | `customer_id` |
| `order_items` | One item line within an order | 112,650 | `(order_id, order_item_id)` |
| `order_payments` | One payment towards an order | 103,886 | `(order_id, payment_sequential)` |
| `order_reviews` | One review linked to one order | 99,224 | `(review_id, order_id)` |
| `products` | One product | 32,951 | `product_id` |
| `sellers` | One seller | 3,095 | `seller_id` |
| `product_category_name_translation` | One Portuguese category name and its English name | 71 | `product_category_name` |
| `geolocation` | One latitude/longitude point for a zip-code prefix | 1,000,163 | `geolocation_id` (surrogate) |

---

## Relationship diagram

`1` = one row, `*` = many rows. `orders` sits at the centre.

```
                              +-------------+
                              |  customers  |
                              +-------------+
                                     | 1   customer_id
                                     |
                                     | 1   (each customer_id is used for exactly one order)
+----------------+  *      1  +-------------+  1      *  +------------------+
| order_payments |------------|   orders    |------------|  order_reviews   |
+----------------+  order_id  +-------------+  order_id  +------------------+
                                     | 1
                                     | order_id
                                     | *
                              +-------------+
                              | order_items |
                              +-------------+
                           * /               \ *
                 product_id /                 \ seller_id
                         1 /                   \ 1
                 +-------------+           +-------------+
                 |  products   |           |   sellers   |
                 +-------------+           +-------------+
                        | *                       :
  product_category_name |                         : seller_zip_code_prefix
                        | 0..1                    :
   +-----------------------------------+    +-------------+
   | product_category_name_translation |    | geolocation | (not used in the analysis)
   +-----------------------------------+    +-------------+
                                                  :
                       customers also link here via customer_zip_code_prefix
```

Dotted lines (`:`) are loose links: `geolocation` has many rows per zip prefix, so joining to it multiplies rows.

---

## How to join

| From table | To table | Join columns | Relationship | Notes |
|---|---|---|---|---|
| `orders` | `customers` | `orders.customer_id = customers.customer_id` | 1:1 | Every order has its own `customer_id`. To count real people, use `customers.customer_unique_id` after the join. |
| `orders` | `order_items` | `order_id` | 1:many | Up to 21 items in one order. 775 orders have no items (none are delivered). Use `COUNT(DISTINCT o.order_id)` when counting orders after this join. |
| `orders` | `order_payments` | `order_id` | 1:many | An order can be paid in several parts (e.g. voucher plus card). Don't join payments and items in the same query without aggregating first, or rows multiply. |
| `orders` | `order_reviews` | `order_id` | 1:many | Usually one review, but 547 orders have more than one. Keep the latest review only (see business definitions). 768 orders have no review. |
| `order_items` | `products` | `product_id` | many:1 | Every item has a matching product. |
| `order_items` | `sellers` | `seller_id` | many:1 | Every item has a matching seller. One order can include items from several sellers. |
| `products` | `product_category_name_translation` | `product_category_name` | many:1 (optional) | Use a `LEFT JOIN`: 610 products have a blank category and 13 have a category missing from the translation table. Show these as `'unknown'`. |
| `customers` | `geolocation` | `customer_zip_code_prefix = geolocation_zip_code_prefix` | many:many | Many rows per prefix. Not used in this analysis. |
| `sellers` | `geolocation` | `seller_zip_code_prefix = geolocation_zip_code_prefix` | many:many | As above. Not used in this analysis. |

---

## Table details

### `orders`

**Grain:** one row = one order placed on the Olist marketplace.
**Rows:** 99,441 · **Primary key:** `order_id` · **Joins on:** `order_id` (to items, payments, reviews), `customer_id` (to customers)

| Column | Type | Meaning |
|---|---|---|
| `order_id` | VARCHAR(32) | Unique ID of the order. |
| `customer_id` | VARCHAR(32) | Customer account used for this order (links to `customers`). |
| `order_status` | VARCHAR(20) | Current status: `delivered`, `shipped`, `canceled`, `unavailable`, `invoiced`, `processing`, `created`, `approved`. |
| `order_purchase_timestamp` | DATETIME | When the customer placed the order. Used to assign an order to a month. |
| `order_approved_at` | DATETIME, nullable | When payment was approved. |
| `order_delivered_carrier_date` | DATETIME, nullable | When the seller handed the parcel to the carrier. |
| `order_delivered_customer_date` | DATETIME, nullable | When the customer received the order. |
| `order_estimated_delivery_date` | DATETIME, nullable | Delivery date promised to the customer at purchase. |

**Gotchas**
- 96,478 orders are `delivered`; only these count towards revenue.
- Blank dates were loaded as `NULL` (e.g. a cancelled order has no delivery date). 8 delivered orders have no customer delivery date.
- `order_estimated_delivery_date` always has a time of 00:00:00, so lateness is judged on calendar dates, not timestamps.
- Order status values use American spelling (`canceled`), as in the source data.

### `customers`

**Grain:** one row = one customer account used for **one** order. The same person gets a new `customer_id` each time they order.
**Rows:** 99,441 (96,096 distinct `customer_unique_id`) · **Primary key:** `customer_id` · **Joins on:** `customer_id` (to orders)

| Column | Type | Meaning |
|---|---|---|
| `customer_id` | VARCHAR(32) | Per-order customer key. Links to `orders.customer_id`. |
| `customer_unique_id` | VARCHAR(32) | The real person. Use this to count customers and repeat buyers. |
| `customer_zip_code_prefix` | CHAR(5) | First five digits of the customer's postcode. |
| `customer_city` | VARCHAR(64) | Customer's city (lower case, Portuguese). |
| `customer_state` | CHAR(2) | Brazilian state code, e.g. `SP` (São Paulo), `RJ` (Rio de Janeiro). |

**Gotchas**
- **`customer_id` vs `customer_unique_id`:** counting `customer_id` would make every customer look like a one-time buyer. Always count `customer_unique_id`.
- Zip prefixes are stored as text so leading zeros are kept (e.g. `01310`, not `1310`). 23,995 customer rows have a prefix starting with `0`.

### `order_items`

**Grain:** one row = one item line within an order. If a customer buys two of the same product, that is two rows.
**Rows:** 112,650 · **Primary key:** `(order_id, order_item_id)` · **Joins on:** `order_id` (to orders), `product_id` (to products), `seller_id` (to sellers)

| Column | Type | Meaning |
|---|---|---|
| `order_id` | VARCHAR(32) | The order this item belongs to. |
| `order_item_id` | SMALLINT | Item number within the order: 1, 2, 3 ... (maximum 21). |
| `product_id` | VARCHAR(32) | The product sold. |
| `seller_id` | VARCHAR(32) | The seller who sold it. |
| `shipping_limit_date` | DATETIME | Deadline for the seller to hand the item to the carrier. |
| `price` | DECIMAL(10,2) | Item price in R$, **excluding freight**. This is the revenue column. |
| `freight_value` | DECIMAL(10,2) | Shipping cost for this item in R$. |

**Gotchas**
- `price` excludes freight. Revenue in this project = `SUM(price)`; freight is reported separately if at all.
- `AVG(price)` is the average **item** price, not the average order value.
- 383 items have zero freight (free shipping); these are genuine and kept.

### `order_payments`

**Grain:** one row = one payment towards an order. An order split across a voucher and a credit card has two rows.
**Rows:** 103,886 · **Primary key:** `(order_id, payment_sequential)` · **Joins on:** `order_id` (to orders)

| Column | Type | Meaning |
|---|---|---|
| `order_id` | VARCHAR(32) | The order being paid for. |
| `payment_sequential` | SMALLINT | Payment number within the order: 1, 2, 3 ... |
| `payment_type` | VARCHAR(20) | `credit_card`, `boleto` (Brazilian bank slip), `voucher`, `debit_card`, `not_defined`. |
| `payment_installments` | SMALLINT | Number of monthly instalments chosen. |
| `payment_value` | DECIMAL(10,2) | Amount of this payment in R$ (includes freight). |

**Gotchas**
- Payment totals include freight, so they won't match revenue (`SUM(order_items.price)`). Revenue is never taken from this table.
- 1 delivered order has no payment record; it is kept because revenue comes from `order_items`.

### `order_reviews`

**Grain:** one row = one customer review linked to one order.
**Rows:** 99,224 (covering 98,673 distinct orders) · **Primary key:** `(review_id, order_id)` · **Joins on:** `order_id` (to orders)

| Column | Type | Meaning |
|---|---|---|
| `review_id` | VARCHAR(32) | ID of the review. **Not unique on its own.** |
| `order_id` | VARCHAR(32) | The order being reviewed. |
| `review_score` | TINYINT | Satisfaction score from 1 (worst) to 5 (best). |
| `review_creation_date` | DATETIME | When the review survey was sent to the customer. |
| `review_answer_timestamp` | DATETIME | When the customer answered. Used to pick the latest review. |

Other columns: `review_comment_title` (VARCHAR(100)) and `review_comment_message` (TEXT) hold optional free-text comments in Portuguese; both are often `NULL` and are not used in the analysis.

**Gotchas**
- `review_id` repeats across different orders (814 duplicate rows): one review was attached to several orders bought together. That is why the key is `(review_id, order_id)`.
- 547 orders have more than one review (202 with different scores). Use the latest review per order.
- 768 orders have no review; they are left out of review averages only.

### `products`

**Grain:** one row = one product listed on the marketplace.
**Rows:** 32,951 · **Primary key:** `product_id` · **Joins on:** `product_id` (to order_items), `product_category_name` (to translation)

| Column | Type | Meaning |
|---|---|---|
| `product_id` | VARCHAR(32) | Unique ID of the product. |
| `product_category_name` | VARCHAR(64), nullable | Product category **in Portuguese**, e.g. `beleza_saude`. |
| `product_weight_g` | INT, nullable | Weight in grams. |

Other columns describe the listing and parcel size and are not used in the analysis: `product_name_length` and `product_description_length` (number of characters in the name and description), `product_photos_qty` (number of photos), and `product_length_cm`, `product_height_cm`, `product_width_cm` (package dimensions). All are SMALLINT and nullable.

**Gotchas**
- Category names are in Portuguese; join to `product_category_name_translation` for English.
- 610 products have a blank category, and 13 products use a category missing from the translation table (`portateis_cozinha_e_preparadores_de_alimentos`, `pc_gamer`). All of these are shown as `'unknown'`.
- The raw CSV misspells "length" as "lenght" (`product_name_lenght`, `product_description_lenght`). The columns were renamed to the correct spelling when the table was built.

### `sellers`

**Grain:** one row = one seller (a merchant selling through Olist).
**Rows:** 3,095 · **Primary key:** `seller_id` · **Joins on:** `seller_id` (to order_items)

| Column | Type | Meaning |
|---|---|---|
| `seller_id` | VARCHAR(32) | Unique ID of the seller. |
| `seller_zip_code_prefix` | CHAR(5) | First five digits of the seller's postcode (text, to keep leading zeros). |
| `seller_city` | VARCHAR(64) | Seller's city. |
| `seller_state` | CHAR(2) | Brazilian state code. |

**Gotchas**
- Sellers link to orders only through `order_items`, not directly to `orders`.
- One seller city in the raw file contained a hidden carriage return; this was fixed at load time (`ESCAPED BY ''`).

### `product_category_name_translation`

**Grain:** one row = one Portuguese category name and its English translation.
**Rows:** 71 · **Primary key:** `product_category_name` · **Joins on:** `product_category_name` (to products)

| Column | Type | Meaning |
|---|---|---|
| `product_category_name` | VARCHAR(64) | Category name in Portuguese (matches `products`). |
| `product_category_name_english` | VARCHAR(64) | Category name in English, e.g. `health_beauty`. |

**Gotchas**
- `products` uses 73 distinct category names, but this table has 71, so always use a `LEFT JOIN` and `COALESCE(..., 'unknown')`.

### `geolocation`

**Grain:** one row = one latitude/longitude point recorded for a zip-code prefix. There are many rows per prefix.
**Rows:** 1,000,163 (19,015 distinct zip prefixes) · **Primary key:** `geolocation_id` (an auto-increment number added on load, as there is no natural key) · **Joins on:** zip prefix (to customers or sellers)

| Column | Type | Meaning |
|---|---|---|
| `geolocation_id` | INT UNSIGNED | Surrogate row number added on load. |
| `geolocation_zip_code_prefix` | CHAR(5) | First five digits of a postcode. |
| `geolocation_lat` | DECIMAL(11,8) | Latitude (rounded to 8 decimal places on load). |
| `geolocation_lng` | DECIMAL(11,8) | Longitude (rounded to 8 decimal places on load). |
| `geolocation_city` | VARCHAR(64) | City. |
| `geolocation_state` | CHAR(2) | Brazilian state code. |

**Gotchas**
- **Not used in the analysis.** State-level analysis uses `customers.customer_state` and `sellers.seller_state` instead.
- Joining on zip prefix multiplies rows (many points per prefix). Aggregate to one point per prefix first if you ever need it.

---

## Business definitions

These are used consistently in every query, export and dashboard.

| Term | Definition |
|---|---|
| **Revenue** | `SUM(order_items.price)` for orders with `order_status = 'delivered'`. Freight is excluded. In Brazilian reais (R$). |
| **Orders** | `COUNT(DISTINCT o.order_id)` of delivered orders. |
| **AOV** (average order value) | Revenue ÷ number of delivered orders, i.e. `SUM(price) / COUNT(DISTINCT order_id)`. Not `AVG(price)`, which is the average item price. |
| **Late delivery** | `DATE(order_delivered_customer_date) > DATE(order_estimated_delivery_date)`. Calendar dates, so arriving on the promised day counts as on time. The base for % late is delivered orders with a delivery date (96,470); the 8 without one are left out of late metrics only. **Days late** = `DATEDIFF(order_delivered_customer_date, order_estimated_delivery_date)`. |
| **Customer** | `customers.customer_unique_id` (not `customer_id`, which is new for every order). |
| **Review score per order** | The latest review only: the row with the highest `review_answer_timestamp` per order, picked with `ROW_NUMBER()`. Orders with no review are left out of review averages only. |
| **Category (English)** | `COALESCE(t.product_category_name_english, 'unknown')` via `LEFT JOIN` from `products` to the translation table. Covers blank categories and untranslated ones. |
| **Month** | Month of `order_purchase_timestamp`, formatted as `DATE_FORMAT(..., '%Y-%m')`. |
| **Trend window** | Monthly time series use **January 2017 to August 2018** only (20 full months). All other analyses (category, state, delivery, customers, sellers) use all delivered orders. |

**Reconciliation totals** (see `docs/cleaning_log.md`): delivered orders 96,478; revenue R$13,221,498.11; delivered orders with a delivery date 96,470; late orders 6,534; unique customers 96,096.
