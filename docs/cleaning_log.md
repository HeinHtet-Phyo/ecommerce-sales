# Cleaning log

Every data-quality issue found in `sql/02_data_quality_checks.sql` and the decision taken. All row counts below come from running that file against the loaded data.

The raw tables are **not modified**. Each rule is applied inside the analysis queries (03–08) and the Power BI views (09), so the original data stays intact and every rule is visible in the SQL.

## Loading issues (fixed in `sql/01_load_data.sql`)

| Issue | Rows affected | Decision | Reason |
|---|---|---|---|
| Blank date fields in `orders` (e.g. a cancelled order has no delivery date) | Varies by column (see check 2) | Load blanks as `NULL` using `NULLIF(@col, '')` | A blank is "unknown", not a date. Without this MySQL would store `0000-00-00` or reject the row. |
| A review comment ends in a backslash (`:\"`), which MySQL reads as an escaped quote | 1 review (2 rows merged into 1) | `ESCAPED BY ''` on every load | The CSVs never use backslash escapes. After the fix, reviews load 99,224 of 99,224 rows. |
| A seller city contains `\r` (`rio de janeiro \rio de janeiro`) | 1 seller | Same fix: `ESCAPED BY ''` | Otherwise `\r` would become a hidden carriage-return character. |
| Reviews and translation files use Windows line endings (`\r\n`); translation file starts with a byte-order mark | 2 files | `LINES TERMINATED BY '\r\n'` for those files; header skipped with `IGNORE 1 LINES` | Stops a stray `\r` being stored at the end of the last column. |
| Geolocation coordinates have 15+ decimal places | 1,000,163 rows | Rounded to 8 decimal places | 8 decimals is about 1 mm. More precision is meaningless. |

## Data-quality decisions

| Issue | Rows affected | Decision | Reason |
|---|---|---|---|
| Orders not in `delivered` status (shipped 1,107; canceled 625; unavailable 609; invoiced 314; processing 301; created 5; approved 2) | 2,963 orders (2.98%) | **Revenue counts `delivered` orders only** (96,478 orders) | Only a delivered order is a completed sale. Shipped or processing orders may still be cancelled. |
| Delivered orders with no customer delivery date | 8 orders | Keep in revenue; **exclude from late-delivery metrics** | We know the sale happened but can't tell whether it was late. |
| Delivered orders with no approval date (14) or carrier date (2) | 16 orders | Keep | These columns aren't used in any metric. |
| Non-delivered orders that have a delivery date | 6 orders | No action | Excluded anyway by the `delivered` filter. |
| Orders with no order items (unavailable 603, canceled 164, created 5, invoiced 2, shipped 1) | 775 orders | No action | None are delivered, so they're already outside revenue. |
| Delivered order with no payment record | 1 order | Keep | Revenue comes from `order_items.price`, not payments, so this order still has a valid price. |
| `customer_id` is a new ID for every order; the real person is `customer_unique_id` | 99,441 customer IDs vs 96,096 unique people (3,345 extra) | **A customer = `customer_unique_id`** | Counting `customer_id` would make every customer look like a one-time buyer. |
| Orders with more than one review | 547 orders (1,098 review rows); 202 of them have different scores | **Keep the latest review per order** (highest `review_answer_timestamp`, using `ROW_NUMBER()`) | The latest review is the customer's final opinion. There are no ties on the timestamp (check 7d), so the choice is clean. |
| `review_id` repeats across different orders | 814 duplicate rows | Keep; key is `(review_id, order_id)` | One review was attached to several orders bought together. Each order still has one score. |
| Orders with no review | 768 orders | Exclude from review-score averages only | We can't invent a score. |
| Products with a blank category | 610 products | Show as `'unknown'` | Keeps their revenue in totals while making the gap visible. |
| Categories missing from the translation table (`portateis_cozinha_e_preparadores_de_alimentos` 10 products, `pc_gamer` 3) | 13 products | Show as `'unknown'` | Follows the project rule. Together with blank categories, 'unknown' holds R$175,967.21 of revenue (1.3%). |
| Items with free freight | 383 items | Keep | Free shipping is a real business offer. Freight is excluded from revenue anyway. |
| A seller's state doesn't match its city (`seller_state = 'PA'` but `seller_city = 'marechal candido rondon'`, a town in Paraná) | 1 seller (PA's only seller) | Keep as recorded | We can't verify which field is wrong. It only affects PA in the top-sellers table (`sql/08`). |
| Zero/negative prices, negative freight, delivery before purchase, orphan rows | 0 rows | No action | Checked and none found. |
| **"Late" definition:** the estimated delivery date never has a time (always 00:00:00) | 1,292 orders delivered *on* the estimated day | **Late = `DATE(delivered) > DATE(estimated)`**, which gives 6,534 late orders | Comparing full timestamps would flag an order delivered at 2pm on the promised day as late (7,826 orders). Arriving on the promised day is on time. |
| Sparse months at the start and end: Sep 2016 (4 orders), Oct 2016 (324), Nov 2016 (0), Dec 2016 (1), Sep 2018 (16, none delivered), Oct 2018 (4, none delivered) | 349 orders | **Monthly trend charts use Jan 2017 – Aug 2018** (20 full months). Totals by category, state, etc. use all delivered orders. | 2016 is the platform's launch period with a missing month (Nov), and Sep–Oct 2018 are after the data snapshot with no deliveries. Plotting them would show fake spikes and crashes. Delivered revenue outside the window is only R$40,470.98 (0.3%). |

## Reconciliation totals

All analysis should reconcile to these figures (check 13):

| Metric | Value |
|---|---|
| Delivered orders | 96,478 |
| Revenue (sum of item price, delivered orders, excl. freight) | R$13,221,498.11 |
| Freight on delivered orders (excluded from revenue) | R$2,198,275.64 |
| Delivered orders with a delivery date (base for % late) | 96,470 |
| Late orders (calendar-date rule) | 6,534 |

All money is in Brazilian reais (R$ / BRL).
