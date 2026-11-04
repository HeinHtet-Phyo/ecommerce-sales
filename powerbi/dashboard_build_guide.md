# Power BI dashboard: step-by-step build guide

A beginner-friendly guide to building the three-page dashboard in **Power BI Desktop (Windows)** from the CSV files in `data/exports/powerbi/`. You don't need MySQL on the Windows computer.

Every number in the suggested titles comes from the SQL results in `data/exports/` (see `docs/findings.md`). After building, check that each visual shows the same number. If one doesn't, a filter or relationship is wrong.

**You need:** Power BI Desktop (free, Microsoft Store), this repo copied to the Windows computer, `powerbi/dax_measures.md` and `powerbi/theme.json`.

---

## Part A: Set up the data model (do this once)

### A1. Load the CSVs

1. **Home → Get data → Text/CSV.** Open `data/exports/powerbi/fact_sales.csv`.
2. In the preview, click **Transform Data** (not Load) so you can check the data types.
3. Repeat for `fact_orders.csv`, `dim_customer.csv`, `dim_seller.csv` and `dim_state.csv`. (In Power Query: **New Source → Text/CSV**.)

### A2. Check the data types in Power Query

Click the icon to the left of each column name to change its type.

| Table | Column(s) | Type |
|---|---|---|
| fact_sales | `order_date` | Date |
| fact_sales | `price`, `freight_value` | Fixed decimal number |
| fact_sales | `order_item_id` | Whole number |
| fact_orders | `order_date` | Date |
| fact_orders | `order_revenue` | Fixed decimal number |
| fact_orders | `item_count`, `has_delivery_date`, `is_late`, `days_late`, `delivery_days`, `review_score` | Whole number |
| dim_customer | `delivered_orders` | Whole number |
| All tables | All IDs, state codes, `category`, `late_status`, `customer_type` | Text |

**Important:** blank cells in `is_late`, `days_late`, `delivery_days` and `review_score` must stay **blank (null)**. Don't replace them with 0, or the averages and late rates will be wrong.

Click **Close & Apply**.

### A3. Create the date table

**Modelling → New table**, then paste the `dim_date` DAX from `powerbi/dax_measures.md`, section 1. Then:
- **Table tools → Mark as date table**, and choose the `Date` column.
- Select `Month Name` and set **Sort by column** to `Month Number`. Select `Year-Month` and set **Sort by column** to `Year-Month Sort`.
- **File → Options → Current file → Data load:** untick **Auto date/time**.

### A4. Create the relationships (Model view)

Drag each column onto its match. Every relationship is **one-to-many, single direction**, from the dimension (the "1" side) to the fact (the "many" side).

| From (1 side) | To (many side) |
|---|---|
| `dim_date[Date]` | `fact_sales[order_date]` |
| `dim_date[Date]` | `fact_orders[order_date]` |
| `dim_state[state_code]` | `fact_sales[customer_state]` |
| `dim_state[state_code]` | `fact_orders[customer_state]` |
| `dim_seller[seller_id]` | `fact_sales[seller_id]` |
| `dim_customer[customer_unique_id]` | `fact_sales[customer_unique_id]` |
| `dim_customer[customer_unique_id]` | `fact_orders[customer_unique_id]` |

Delete any relationships Power BI created automatically that aren't in this table. Don't connect `fact_sales` directly to `fact_orders`.

**Why two fact tables?** Revenue belongs to each **item** (so it can be split by category and seller), but "late" and "review score" belong to the whole **order**. Putting review scores on item rows would count a 3-item order's review three times.

### A5. Add the measures

Create an empty table to hold the measures: **Home → Enter data**, name it `_Measures`, then **Load**. Select it, then **New measure**, and paste each measure from `powerbi/dax_measures.md`, section 3. Set each measure's format as described there.

### A6. Apply the theme

**View → Themes → Browse for themes** and choose `powerbi/theme.json`. The colours you'll use:

| Use | Colour |
|---|---|
| Main series (revenue, orders) | Navy `#1F3A5F` |
| Second series / on time | Teal `#2A9D8F` |
| **Late deliveries and bad changes only** | Red `#D1495B` |
| Good change | Green `#5B8E7D` |
| Unknown / no change | Light grey `#C3C8CD` |

### A7. Check the model before building pages

Put a **Card** on a blank page with **Total Revenue**. It must show **R$13,221,498** (all dates). Add cards for **Total Orders** (96,478), **Late Orders** (6,534) and **Avg Review Score** (4.16). If these match, the model is correct. Delete the test page.

---

## Part B: Layout rules for every page

- **Canvas:** 16:9 (default 1280 × 720).
- **Top band (about 90 px):** the page title as a question, on the left, and slicers on the right.
- **KPI row** directly under the title (page 1). **Charts** in a 2-column grid below it.
- Use **Format → Align** and **Distribute** so edges line up. Keep 16 px gaps between visuals.
- **Titles state the finding** (for example, "Late deliveries cut review scores by 2 points"), not just the field names.
- No 3D, no pie or donut charts with more than 2 slices, no gauges. Turn off gridlines you don't need. Show data labels instead of making people read axes.
- Use red **only** for late or bad values, so it always means "problem".
- Sort bar charts largest first, unless the axis is time.
- Page filter for trend charts: **`dim_date[Date]` between 1 Jan 2017 and 31 Aug 2018** (see `dax_measures.md`, section 4, for why).

---

## Page 1: Overview ("How is the business doing?")

**Page title (text box):** *How is the business doing?* Subtitle: *Delivered orders, Jan 2017 – Aug 2018. KPI cards compare Aug 2018 with Jul 2018.*

**Page-level filter:** `dim_date[Date]` from 01/01/2017 to 31/08/2018.

### Slicers (top right)
| Slicer | Field | Style |
|---|---|---|
| Date range | `dim_date[Date]` | "Between" (slider) |
| State | `dim_state[state_name]` | Dropdown, multi-select, "Select all" on |

### KPI cards (one row of 5)
Use the **Card (new)** visual, or a Card with a small text line under it for the change. On each card, add a **visual-level filter** of `dim_date[Year-Month]` = "2018-08".

| Card | Main value | Change line | Expected value |
|---|---|---|---|
| Revenue | `Total Revenue` | `Revenue MoM %` | R$838,577, −3.4% vs Jul |
| Orders | `Total Orders` | `Orders MoM %` | 6,351, +3.1% vs Jul |
| Average order value | `AOV` | `AOV MoM %` | R$132.04, −6.3% vs Jul |
| Avg review score | `Avg Review Score` | `Avg Review Change` | 4.31, −0.01 vs Jul |
| % late deliveries | `% Late Deliveries` | `% Late Change (pp)` | 6.2%, +2.8 pp vs Jul |

Colour the change lines with conditional formatting (**Format → Callout value / Font colour → fx → Rules**). For Revenue, Orders, AOV and Avg Review, use green if > 0 and red if < 0. For % Late it's the **opposite**: red if > 0, green if < 0.

### Monthly revenue line chart (main visual, full width)
| Setting | Value |
|---|---|
| Visual | Line chart |
| X-axis | `dim_date[Year-Month]` (type: categorical, sorted by Year-Month ascending) |
| Y-axis | `Total Revenue` |
| Secondary y-axis (optional) | `Total Orders` (grey line) |
| Data labels | Off. Turn on **markers**, and add a data label only on the Nov 2017 point (Format → Data labels → Series / customise) |
| Title | **Revenue grew from R$112k to a R$988k peak in Nov 2017, then levelled off in 2018** |

Optional: add the `Revenue MoM %` column chart below it in the same width, with negative bars red, to show the dips. Title: **Biggest dips: Dec 2017 (−26.5%), Jun 2017 (−13.8%), Jun 2018 (−12.4%)**.

---

## Page 2: Products & Regions ("Where does revenue come from?")

**Page title:** *Where does revenue come from?* Subtitle: *All delivered orders, Sep 2016 – Aug 2018.*

Remove the trend-window page filter on this page (or don't add it), so totals match the SQL results.

**Slicers:** Date range (`dim_date[Date]`), Region (`dim_state[region]`), Category (`fact_sales[category]`, dropdown).

### Top 10 categories (left, tall)
| Setting | Value |
|---|---|
| Visual | Clustered **bar** chart (horizontal) |
| Y-axis | `fact_sales[category]` |
| X-axis | `Total Revenue` |
| Filter | Visual-level filter on `category`: **Top N**, show top 10 by `Total Revenue` |
| Sort | Total Revenue, descending |
| Data labels | On, display units: thousands |
| Tooltip | Add `Total Orders` and `AOV` |
| Title | **Top 10 of 72 categories bring in 62% of revenue; health & beauty leads with R$1.23m** |

Optional tidy-up: in Power Query, replace `_` with a space in `category` (e.g. "health beauty").

### Revenue by state (top right)
| Setting | Value |
|---|---|
| Visual | Clustered bar chart (a filled map needs map visuals switched on in Options → Security; a bar chart is clearer anyway) |
| Y-axis | `dim_state[state_name]` |
| X-axis | `Total Revenue` |
| Sort | Total Revenue, descending. Show the top 10 with a Top N filter, or all 27 with a scroll bar |
| Data labels | On |
| Title | **São Paulo, Rio de Janeiro and Minas Gerais bring in 63% of revenue** |

### Top sellers table (bottom right)
| Setting | Value |
|---|---|
| Visual | Table |
| Columns | `dim_seller[seller_short_id]`, `dim_seller[seller_city]`, `dim_seller[seller_state]`, `Total Revenue`, `Total Orders` |
| Filter | Visual-level filter on `seller_short_id`: **Top N = 10** by `Total Revenue` |
| Sort | Total Revenue, descending |
| Conditional formatting | Data bars on Total Revenue (navy) |
| Title | **The top 10 of 2,970 sellers earn 13% of revenue** |

To match `sql/08` (top 3 sellers **per state**), select a single state in a `dim_seller[seller_state]` slicer and change Top N to 3.

---

## Page 3: Delivery & Customer Experience ("What hurts customer satisfaction?")

**Page title:** *What hurts customer satisfaction?* Subtitle: *Delivered orders with a delivery date. Late = delivered after the estimated day.*

**Slicers:** Date range, Region. (Don't add a category slicer here. Delivery measures come from `fact_orders`, which has no category column.)

### Average review: late vs on time (top left)
| Setting | Value |
|---|---|
| Visual | Clustered column chart |
| X-axis | `fact_orders[late_status]` |
| Y-axis | `Avg Review Score` |
| Filter | `late_status` is not "Unknown" |
| Colours | On time = teal `#2A9D8F`, Late = red `#D1495B` |
| Data labels | On, 2 decimals |
| Y-axis range | Start at 0, end at 5 (don't zoom in, which would exaggerate the gap) |
| Title | **Late deliveries cut review scores by 2 points (4.29 → 2.27)** |

### Review score distribution (top right)
| Setting | Value |
|---|---|
| Visual | **100% stacked bar** chart |
| Y-axis | `fact_orders[late_status]` (filter out "Unknown") |
| Legend | `fact_orders[review_score]` |
| X-axis | `Reviewed Orders` |
| Colours | 1 = red `#D1495B`, 2 = light red or grey, 3 = grey `#8A939B`, 4 = light teal `#9CC5C0`, 5 = teal `#2A9D8F` |
| Data labels | On (shows %) |
| Title | **54% of late orders get 1 star, against 7% of on-time orders** |

### % late by state (bottom left)
| Setting | Value |
|---|---|
| Visual | Clustered bar chart |
| Y-axis | `dim_state[state_name]` |
| X-axis | `% Late Deliveries` |
| Tooltip | `Orders With Delivery Date`, `Late Orders` |
| Sort | % Late Deliveries, descending |
| Colour | Red `#D1495B`. Optional: add an average line (Analytics pane → Average line) |
| Title | **Rio de Janeiro: 12.1% late, which is 23% of all late orders** |

Note: small states have few orders (Alagoas has 397), so their rates swing a lot. Mention this in the tooltip or subtitle.

### Repeat vs one-time customers (bottom right)
| Setting | Value |
|---|---|
| Visual | Clustered bar chart, or two **cards** side by side |
| Y-axis | `dim_customer[customer_type]` |
| X-axis | `Total Customers` and `Total Revenue` → right-click each, then **Show value as → Percent of grand total** |
| Colours | One-time = grey, Repeat = navy |
| Title | **Only 3% of customers buy again, and they bring in 5.5% of revenue** |

### Optional: monthly late rate (if space allows)
Line chart: X = `dim_date[Year-Month]`, Y = `% Late Deliveries`, colour red, with the trend-window filter (Jan 2017 – Aug 2018). Title: **Late rate spiked in busy months: 12.4% in Nov 2017 and 19.0% in Mar 2018**.

---

## Part C: Finish and check

1. **Check each title against the visual.** Every number in a title must match what the chart shows with no slicers selected. If you change a title, use `docs/findings.md` as the source.
2. **Check slicers:** pick "Rio de Janeiro" on page 3. % late should show 12.1%.
3. **Add alt text** to each visual (Format → General → Alt text) for accessibility.
4. **Save** as `powerbi/ecommerce_dashboard.pbix`. If the file is under 50 MB you can commit it. `.gitignore` already ignores backup and lock files.

## Screenshots in `images/`

The finished dashboard was exported with **File → Export → Export to PDF** ([ecommerce_dashboard.pdf](ecommerce_dashboard.pdf)), and each page saved as a PNG:

| File | Page |
|---|---|
| [`images/overview.png`](../images/overview.png) | Page 1: How is the business doing? (top of the README) |
| [`images/products_regions.png`](../images/products_regions.png) | Page 2: Where does revenue come from? |
| [`images/delivery_reviews.png`](../images/delivery_reviews.png) | Page 3: What hurts customer satisfaction? |

---|---|
| `images/dashboard_overview.png` | Page 1, full page (this goes at the top of the README) |
| `images/dashboard_products_regions.png` | Page 2, full page |
| `images/dashboard_delivery_customers.png` | Page 3, full page |
| `images/late_vs_ontime_reviews.png` | Close-up of the late vs on-time review chart (the key finding) |
| `images/data_model.png` | Model view showing the star schema relationships |

---

## Alternative: connect Power BI directly to MySQL

Instead of loading CSVs, Power BI can read the views straight from MySQL:

1. Install **MySQL Connector/NET** on the Windows computer. Power BI needs it to talk to MySQL.
2. **Get data → MySQL database.** Server: the MySQL host (for example `localhost` if MySQL runs on the same Windows computer). Database: `olist`.
3. Sign in with a MySQL user (use a read-only user, not root), then tick the views `fact_sales`, `fact_orders`, `dim_customer`, `dim_seller` and `dim_state`.
4. Pick **Import** (copies the data, fast) rather than DirectQuery (queries MySQL live on every click).

**Trade-off:** a direct connection lets you click **Refresh** after re-running the SQL, with no re-exporting. But the Windows computer needs MySQL installed (run `sql/00`, `01` and `09` there), or network access to the Mac's MySQL, which is set to accept local connections only by default. For a portfolio piece, the CSVs are simpler and let anyone reproduce the dashboard.
