# Findings

Every number here comes from a query in `sql/` that was run against the `olist` database. The query results are saved in `data/exports/`. Money is in Brazilian reais (R$).

## Business definitions (used in every query and the dashboard)

| Term | Definition |
|---|---|
| **Revenue** | Sum of `order_items.price` for orders with status `delivered`. **Freight is excluded.** |
| **Orders** | Count of distinct delivered orders. |
| **Average order value (AOV)** | Revenue ÷ number of delivered orders. |
| **Late delivery** | Delivered on a later **calendar day** than the estimated delivery date: `DATE(order_delivered_customer_date) > DATE(order_estimated_delivery_date)`. Base: delivered orders with a delivery date (96,470). |
| **Customer** | `customer_unique_id`, the real person. (`customer_id` is new for every order, so it can't identify repeat buyers.) |
| **Review score** | The **latest** review per order. Orders with no review are left out of review averages. |
| **Category** | English name from the translation table; blank or untranslated becomes `unknown`. |
| **Trend window** | Monthly trends use Jan 2017 – Aug 2018 (20 full months). Everything else uses all delivered orders. |

**Totals everything reconciles to:** 96,478 delivered orders · R$13,221,498.11 revenue · 93,358 customers with a delivered order · 6,534 late orders out of 96,470.

---

## Results by question

### 1. Monthly revenue trend (`sql/03_monthly_revenue.sql`)

- Monthly revenue grew from R$111,798 (Jan 2017) to a peak of **R$987,765 in Nov 2017**, then levelled off at R$826k–R$978k a month through 2018. Jan–Jun 2018 revenue (R$5.51m) was **182% higher** than Jan–Jun 2017 (R$1.96m).
- The biggest dips were **Dec 2017 (−26.5%)**, after the November peak, Jun 2017 (−13.8%), Jun 2018 (−12.4%) and Feb 2018 (−10.6%). AOV stayed between R$124 and R$149 every month, so revenue moves with the **number of orders**, not basket size. Growth has stalled: no month since May 2018 (R$977.5k) has beaten Nov 2017.

### 2a. Top categories (`sql/04_top_categories.sql`)

- Revenue is spread widely. No category passes 10%, and the **top 10 of 72 categories make up 62.4%** (R$8.25m). Health & beauty leads with R$1.23m (9.3%), followed by watches & gifts with R$1.17m (8.8%).
- Watches & gifts earns almost as much as health & beauty from far fewer orders (5,495 vs 8,647), because its average item price is the highest in the top 10 (R$199). Bed, bath & table is the opposite: the most orders (9,272) but cheaper items (R$93).

### 2b. Revenue by customer state (`sql/05_revenue_by_state.sql`)

- **São Paulo, Rio de Janeiro and Minas Gerais bring in 63.4% of revenue** (R$8.38m). São Paulo alone is 38.3%.
- **Rio de Janeiro is the delivery problem among big markets.** 12.11% of its orders arrive late, against 4.49% in São Paulo, and its 1,495 late orders are **23% of all late deliveries**. The worst rates are in smaller north-eastern states: Alagoas 21.4%, Maranhão 17.4%.

### 2c. Top sellers by state (`sql/08_top_sellers_by_state.sql`)

- **Sellers based in São Paulo earn 64.4% of all revenue** (R$8.51m from 1,769 sellers), and that revenue is spread out: SP's top 3 sellers hold only 7.2% of it.
- Outside the South-East, single sellers carry whole states. One Bahia seller has 78.4% of Bahia seller revenue, and the top 3 in Rio de Janeiro hold 38.3%. Across the platform, the top 10% of sellers (297 of 2,970) earn 67.1% of revenue.

### 3. Late deliveries and review scores (`sql/06_late_delivery_impact.sql`)

- **6.77% of delivered orders arrive late** (6,534 of 96,470), by an average of 10.6 days.
- **Late orders average 2.27 stars against 4.29 for on-time orders, a 2.02-point drop.** The share of 1-star reviews rises from 6.6% to 53.8%, and 5-star falls from 62.3% to 16.5%. Even 1–3 days late lowers the average to 3.29. By 4–7 days late, most reviews are 1-star (58.6%). Scores bottom out around 8–14 days late (1.67) and then level off.

### 4. Repeat customers (`sql/07_repeat_customers.sql`)

- **Only 3.0% of customers (2,801 of 93,358) placed more than one delivered order**, and they brought in 5.5% of revenue (R$728k).
- Repeat customers are worth about twice as much each (R$260 vs R$138). They order more often but spend slightly less per order (AOV R$123 vs R$138). The business depends almost entirely on new customers, so retention is a large untapped opportunity.

### Extra check: late rate by month (`fact_orders` view in `sql/09_powerbi_views.sql`)

- The late rate jumps in busy periods: **12.4% for Nov 2017 orders** (the peak sales month), **14.1% in Feb 2018 and 19.0% in Mar 2018**, compared with 1–7% in most other months. Orders still in transit when the data was captured stay low every month (43–133), so the low recent rates are not caused by missing late orders.

---

## Key findings

**1. Late deliveries cost about 2 review points.**
6.77% of delivered orders arrive late (6,534 of 96,470). Late orders average **2.27 stars against 4.29** for on-time orders, and 53.8% of them get a 1-star review (6.6% when on time). Even 1–3 days late lowers the average to 3.29.
*So what:* delivery is the clearest lever on customer satisfaction that the data shows. Low review scores hurt seller ratings and make customers less likely to come back, which matters given finding 2.

**2. Almost nobody comes back.**
Only **3.0% of customers (2,801 of 93,358) placed a second delivered order**, and they bring in just 5.5% of revenue. A repeat customer is worth R$260 against R$138 for a one-time buyer.
*So what:* growth depends almost entirely on finding new customers, which is usually the most expensive way to grow. Retention is a large, untapped opportunity.

**3. Revenue is concentrated, and growth has stalled.**
São Paulo, Rio de Janeiro and Minas Gerais bring in **63.4% of revenue**. After growing from R$112k (Jan 2017) to a R$988k peak (Nov 2017), monthly revenue levelled off at R$826k–R$978k through 2018. No month has beaten the Nov 2017 peak, and AOV stayed between R$124 and R$149, so revenue only grows when the number of orders grows.
*So what:* without new demand (new regions or more repeat orders), revenue is likely to stay flat.

## Recommendations

**1. Fix late deliveries where they cluster: Rio de Janeiro and busy periods.**
Rio de Janeiro has 12.1% of orders late (against 4.5% in São Paulo) and accounts for 23% of all late orders. Late rates also jumped to 12.4% in Nov 2017 and 19.0% in Mar 2018. Review carrier performance on routes into Rio de Janeiro, set more realistic delivery estimates there, and add carrier capacity before known peaks such as Black Friday. When an order is going to be late, tell the customer before the estimated date: the score drop starts at just 1–3 days late.
*Measure it by:* % late deliveries and average review score for Rio de Janeiro, tracked monthly on the dashboard.

**2. Launch a second-order programme.**
Send a time-limited offer after a customer's first order is delivered **on time** (the moment their review is most likely positive), aimed at the top categories. For scale: if 1% more customers (about 934 people) placed one extra order at today's AOV of R$137.04, that would be about R$128k of extra revenue, before any growth.
*Measure it by:* Repeat Customer %, starting from the current 3.0%. Test it on a small group of customers against a control group before rolling it out.

**3. Reduce dependence on a few states and sellers.**
Sellers outside the South-East are thin on the ground. In Bahia, one seller holds 78.4% of the state's seller revenue, and the Northeast region has the highest late rate (12.7%) while bringing in 11.3% of revenue. Recruit more sellers in the Northeast and test whether local sellers deliver faster there. That would support growth outside the three big states and lower the risk of losing one key seller.
*Measure it by:* revenue share outside SP/RJ/MG, and % late by region.

## Limitations

- **Old, Brazilian data.** Orders run from Sep 2016 to Oct 2018 in one country, so the patterns may not hold for today or for the UK market. The method (SQL logic, definitions, dashboard) transfers; the numbers don't.
- **No cost data, so no profit.** Revenue excludes freight, but there are no product costs, margins or marketing spend, so we can't say which categories or states are most *profitable*.
- **Reviews show association, not cause.** Late orders score much lower, but other factors (product quality, seller service) may also play a part. A controlled test would be needed to prove cause. 99.3% of delivered orders have a review, but reviews only capture customers who chose to answer the survey.
- **"Late" means late against Olist's own estimate.** States with long estimates (e.g. Amazonas, 26 days on average) can look "on time" while still being slow.
- **The edges of the data are incomplete.** 2016 and Sep–Oct 2018 are excluded from trend charts (see `cleaning_log.md`). Aug 2018 is the last full month.
- **Customer matching depends on Olist's `customer_unique_id`.** If one person used different details, they may be counted as two customers, which would make the repeat rate look slightly lower than it really is.
