# Interview notes

Private prep notes for talking about this project. Every number is from `docs/findings.md` (real query results).

---

## 2-minute project explanation (STAR)

**Situation.** I wanted a portfolio project that shows the core analyst job: taking messy business data, answering real questions with SQL, and turning the answers into recommendations. I used Olist's public dataset, about 100,000 real orders from a Brazilian online marketplace, spread across 9 related tables.

**Task.** I set four business questions. How is revenue trending, and where are the dips? Which categories and states drive revenue? Do late deliveries hurt review scores, and by how much? And how many customers come back?

**Action.**
- **Loading.** I designed the MySQL schema, loaded the CSVs from the command line and checked row counts against every file. That check caught a problem: a backslash in one review was merging two rows.
- **Quality checks.** I ran 13 checks and wrote every decision into a cleaning log. For example, I counted only delivered orders as revenue, kept the latest review when an order had two, and used `customer_unique_id` instead of `customer_id`, which changes on every order.
- **Analysis.** I wrote one SQL file per question, using CTEs and window functions like `LAG` and `RANK`. Every result reconciles to the same total: R$13.2 million across 96,478 orders.
- **Dashboard.** I exported star-schema views into Power BI, set up the relationships and a date table, wrote 24 DAX measures, and built a three-page dashboard: one page per business question, with chart titles that state the finding and a recommendation on each page. I checked every KPI card against the SQL totals before building the charts.

**Result.**
- Late deliveries are the biggest driver of bad reviews: late orders average **2.27 stars against 4.29** for on-time orders.
- Only **3% of customers** ever placed a second order.
- Three states bring in **63% of revenue**, and growth had stalled after the November 2017 peak.

**Business impact.** I made three recommendations, each with a metric to track:
- Fix delivery in Rio de Janeiro, which has 23% of all late orders from only 13% of orders (late rate 12.1% vs 4.5% in São Paulo), and plan capacity for busy periods.
- Launch a second-order programme for customers whose first order arrived on time. Each extra 1% of customers buying again is worth about R$128k.
- Recruit sellers outside the South-East to cut dependence on a few states and sellers.

---

## Each SQL file in one sentence, and its trickiest part

| File | What it does | Trickiest part |
|---|---|---|
| `00_create_schema.sql` | Creates the database and 9 tables with data types, primary keys and indexes on join columns. | `review_id` isn't unique (one review can cover several orders), so the key had to be `(review_id, order_id)`. Zip codes are text so leading zeros aren't lost. |
| `01_load_data.sql` | Loads the 9 CSVs with `LOAD DATA LOCAL INFILE` and checks row counts. | Blank dates had to become `NULL` (via `NULLIF(@var, '')`). A review ending in `\"` merged two rows until I added `ESCAPED BY ''`. Two files used Windows line endings. |
| `02_data_quality_checks.sql` | Runs 13 read-only checks and prints counts for every data issue. | Deciding the *rules*, not writing the SQL. The best example is "late": the estimated date is always midnight, so comparing timestamps would wrongly flag 1,292 same-day deliveries as late. |
| `03_monthly_revenue.sql` | Revenue, orders and AOV per month, with month-on-month % growth. | `LAG()` to compare each month with the previous one. Choosing the Jan 2017–Aug 2018 window, because the edge months are nearly empty. |
| `04_top_categories.sql` | Top 10 categories by revenue, with each one's share of total revenue. | The % share must be calculated across **all** categories *before* cutting to the top 10, otherwise the top 10 would always add up to 100%. |
| `05_revenue_by_state.sql` | Revenue, orders, AOV and % late for each customer state. | Revenue is per item but "late" is per order, so I rolled items up to one row per order first. Otherwise a 3-item late order would count as 3 late orders. |
| `06_late_delivery_impact.sql` | % late overall, average review for late vs on-time, score distribution, and score by days late. | Keeping only the latest review per order with `ROW_NUMBER()`, and using `PARTITION BY` so each group's percentages add up to 100. |
| `07_repeat_customers.sql` | Splits customers into one-time and repeat, with their share of customers and revenue. | Using `customer_unique_id`. With `customer_id` the repeat rate would come out as exactly 0%. |
| `08_top_sellers_by_state.sql` | Top 3 sellers per state by revenue. | `RANK() OVER (PARTITION BY seller_state ...)` restarts the ranking in each state. I chose `RANK` so tied sellers share a place. |
| `09_powerbi_views.sql` | Builds the star-schema views for Power BI and exports them to CSV. | Needing **two** fact tables (items for revenue, orders for delivery and reviews) so review averages aren't double-counted. |

---

## Likely questions and short answers

**Why `customer_unique_id` and not `customer_id`?**
In this dataset `customer_id` is created fresh for every order, so one person who orders three times has three `customer_id`s. If I'd counted by `customer_id`, I'd have found 96,478 "customers" and 0 repeat buyers. `customer_unique_id` is the real person, which gives 93,358 customers, of whom 2,801 bought again. I checked this before trusting the repeat-customer number.

**How did you handle duplicate reviews?**
547 orders had more than one review, and 202 of those had different scores, so the choice mattered. I kept the **latest** review per order, because that's the customer's final opinion. I used `ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY review_answer_timestamp DESC)` and kept row 1. I first checked that no order had two reviews with the same timestamp, so there were no ties.

**Why exclude freight from revenue?**
Freight is a delivery charge passed on to carriers, not product sales. Including it would make expensive-to-ship categories and remote states look more valuable than they are. Keeping it out means revenue measures what customers paid for products. Freight is still in the data (R$2.2m on delivered orders) if someone needs it.

**`RANK()` vs `DENSE_RANK()` vs `ROW_NUMBER()`?**
For scores of 100, 90, 90, 80:
- `ROW_NUMBER` gives 1, 2, 3, 4. Every row gets a unique number, and ties are broken arbitrarily.
- `RANK` gives 1, 2, 2, 4. Ties share a place, and the next number is skipped.
- `DENSE_RANK` gives 1, 2, 2, 3. Ties share a place, with no gap.

I used `RANK` for top sellers so that two sellers tied for third would both appear. I used `ROW_NUMBER` for reviews because I needed exactly one review per order.

**Why only delivered orders?**
Only a delivered order is a completed sale. Shipped or processing orders can still be cancelled. Delivered orders are 97% of all orders, so not much is left out.

**How did you define "late", and why?**
Delivered on a later calendar day than the estimated date. The estimated date never has a time (always midnight), so comparing full timestamps would call an order delivered at 2pm on the promised day "late". That would have added 1,292 orders that were actually on time.

**How would you explain the late-delivery finding to a non-technical manager?**
"When an order arrives late, customers rate us about 2 stars lower: roughly 2 out of 5 instead of 4 out of 5. More than half of late orders get the worst possible rating. Even being one to three days late costs us a full star. About 1 in 15 orders is late, and Rio de Janeiro alone accounts for almost a quarter of them, so that's where to start."

**Does late delivery *cause* low reviews?**
The data shows a strong association, and the steady pattern makes it believable: the later the order, the lower the score, until it levels off at about two weeks. But it isn't proof, because other things (product quality, the seller) could also play a part. To prove cause I'd run a test, for example improving delivery estimates for one group of orders and comparing review scores.

**What would you do with more data?**
- Add costs to analyse profit, not just revenue.
- Use the geolocation table to test whether seller-to-customer distance explains late deliveries.
- Build monthly cohorts (repeat rate by first-order month) to see if retention is improving.
- Analyse the review text for the most common complaints.

**Why Brazilian data?**
It's real company data with 9 related tables (orders, items, customers, sellers, products, payments, reviews), which is ideal for showing SQL joins and data modelling. Most public datasets are a single flat file. My other projects use UK data, and the methods (definitions, checks, SQL patterns, dashboard design) transfer directly.

**What was the hardest part?**
Data quality, not the analysis. For example, the load "worked" but was one review short. Tracking that down found a backslash that was silently merging two rows. That's why I compare row counts after every load, and why every analysis reconciles back to the same R$13,221,498.11 total.

**Why a star schema for Power BI?**
Dimensions (date, state, seller, customer) each sit in one small table and filter the fact tables in one direction. Slicers behave predictably, DAX stays simple and the model is fast. I needed two fact tables because revenue is per item, but delivery and reviews are per order.

**Why did you build a separate date table?**
Time-intelligence functions like `DATEADD` (for "revenue last month") need a continuous date column marked as a date table. It also lets one date slicer filter both fact tables.

---

## Dashboard questions

**Walk me through your dashboard.**
Three pages, one per business question. Page 1 answers "how is the business doing?" with five KPI cards, the monthly revenue trend and a month-on-month chart that shows the dips in red. Page 2 shows where revenue comes from: categories, states and top sellers. Page 3 shows what hurts satisfaction: reviews for late vs on-time orders, late orders by state, and how few customers come back. Every chart title states the finding, and each page ends with a recommendation.

**São Paulo has more late orders than Rio. Why focus on Rio?**
Because São Paulo is also much bigger. Rio has 23% of late orders from only 13% of orders, so its late *rate* is 12.1%, almost three times São Paulo's 4.5%. Comparing rates, not just totals, shows where the real problem is.

**Why did you leave January 2017 out of the month-on-month chart?**
January 2017 is compared with December 2016, which had almost no orders, so the percentage growth is huge and meaningless. Including it squashed every other bar flat, so I excluded it and kept the chart honest.

**Why does the review chart's axis start at 0?**
If the axis started at 2, the gap between 2.27 and 4.29 would look far bigger than it is. Starting at 0 shows the true difference, which is still large.

**Why the trend window Jan 2017 – Aug 2018?**
2016 was the launch period with very few orders, and Sep–Oct 2018 come after the data snapshot. Plotting them would show fake spikes and crashes. Totals by category, state and seller still use all delivered orders.

**How did you check the dashboard was correct?**
Before building any charts I put test cards for revenue, orders, late orders and average review on a blank page and checked they matched the SQL results exactly (R$13,221,498.11, 96,478, 6,534 and 4.16).

**Why Top N filters instead of showing everything?**
There are 72 categories, 27 states and almost 3,000 sellers. Showing the top 10 keeps each chart readable and still covers most of the revenue (62% for categories, 13% for sellers).

---

## CV bullet options (pick one)

1. Analysed 96k e-commerce orders across 9 related MySQL tables using CTEs and window functions. Found that late deliveries cut review scores from 4.29 to 2.27 and that only 3% of customers reorder, and recommended delivery and retention fixes.
2. Built an end-to-end SQL and Power BI sales analysis (R$13.2m revenue): designed the schema, ran 13 data-quality checks, and built a 3-page dashboard showing that 3 states drive 63% of revenue while Rio de Janeiro has 23% of late orders from only 13% of orders.
3. Turned raw marketplace data into a star-schema Power BI model with 24 DAX measures and a 3-page dashboard, and identified a 2-point review drop for late orders and a 3% repeat-purchase rate as the top two business priorities.
