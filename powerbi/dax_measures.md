# DAX measures – Olist sales dashboard

This file holds every DAX formula used in the Power BI report, with a plain-English explanation of each one.
The business definitions match the SQL analysis (see `docs/cleaning_log.md`), so the dashboard numbers tie back to the SQL results.

**Tables in the model** (loaded from `data/exports/powerbi/`):

| Table | One row per | Used for |
|---|---|---|
| `fact_sales` | order item (delivered orders only) | Revenue, orders, AOV, customers, category and seller analysis |
| `fact_orders` | delivered order | Late deliveries, delivery days, review scores |
| `dim_customer` | customer (`customer_unique_id`) | All-time customer type (One-time / Repeat) |
| `dim_seller` | seller | Seller name, city, state |
| `dim_state` | Brazilian state | State name and region |
| `dim_date` | calendar day | Created in Power BI with DAX (section 1) |

**Relationships** (all one-to-many, single direction, from the dimension to the fact):

- `dim_date[Date]` → `fact_sales[order_date]` and `fact_orders[order_date]`
- `dim_state[state_code]` → `fact_sales[customer_state]` and `fact_orders[customer_state]`
- `dim_seller[seller_id]` → `fact_sales[seller_id]`
- `dim_customer[customer_unique_id]` → `fact_sales[customer_unique_id]` and `fact_orders[customer_unique_id]`

> **Important limit of this model:** `fact_orders` has no product or seller columns, so measures built on it (late deliveries, reviews) **do not respond to category or seller slicers**. They do respond to date, state and customer filters. Put category and seller slicers only on pages that use `fact_sales` measures, or say so on the page.

---

## 1. Date table (`dim_date`)

### Why a date table is needed

- **Time intelligence needs it.** Functions such as `DATEADD` ("same period last month") only work properly on a column that has **every day, with no gaps**. `fact_sales[order_date]` only contains days on which someone ordered, so it has gaps.
- **One calendar for both fact tables.** `dim_date` filters `fact_sales` and `fact_orders` at the same time, so a single month slicer controls the whole page.
- **Clean labels.** Year, month name and Year-Month live in one place instead of being repeated in each fact table.

### DAX (Modelling → New table)

```dax
dim_date =
ADDCOLUMNS (
    CALENDAR ( DATE ( 2016, 9, 1 ), DATE ( 2018, 10, 31 ) ),
    "Year", YEAR ( [Date] ),
    "Month Number", MONTH ( [Date] ),
    "Month Name", FORMAT ( [Date], "mmm" ),
    "Year-Month", FORMAT ( [Date], "yyyy-mm" ),
    "Year-Month Sort", YEAR ( [Date] ) * 100 + MONTH ( [Date] ),
    "Quarter", "Q" & QUARTER ( [Date] )
)
```

Line by line:

- `CALENDAR ( start, end )` makes a one-column table called `Date` with every day from 1 Sep 2016 to 31 Oct 2018. These are the first and last months in the Olist data, rounded out to whole months.
- `ADDCOLUMNS` adds extra columns to that table, each calculated from `[Date]`:
  - `Year` – e.g. 2017.
  - `Month Number` – 1 to 12. Used only to sort the month name.
  - `Month Name` – short name, e.g. "Jan".
  - `Year-Month` – text label such as "2017-01", the same format as the SQL month column.
  - `Year-Month Sort` – a number such as 201701, used to sort Year-Month in time order.
  - `Quarter` – "Q1" to "Q4".

*Alternative:* `CALENDARAUTO()` instead of `CALENDAR(...)` builds the date range automatically from every date column in the model. It works, but it always covers whole calendar years (so 1 Jan 2016 to 31 Dec 2018 here) and will stretch if a stray date appears in any table. The fixed `CALENDAR` range is easier to explain and control.

### Set-up steps after creating the table

1. **Mark as date table:** select `dim_date` → Table tools → *Mark as date table* → choose the `Date` column. This tells Power BI to use this table for time intelligence. It also makes `DATEADD` ignore other filters on the date table (such as a Year-Month filter on a card), which the "last month" measures rely on.
2. **Sort columns:** select `Month Name` → Column tools → *Sort by column* → `Month Number`. Do the same for `Year-Month` → sort by `Year-Month Sort`. Without this, months appear alphabetically (Apr, Aug, Dec ...).
3. **Check data types:** `dim_date[Date]`, `fact_sales[order_date]` and `fact_orders[order_date]` must all be type **Date** (not Date/Time and not Text). If one side has a time part or is text, the relationship will not match rows.
4. **Create the relationships** listed at the top of this file (Model view, drag `dim_date[Date]` onto each `order_date`).
5. Turn off *Auto date/time* (File → Options → Current file → Data load), because we now have our own date table.

---

## 2. Organising the measures

**Measure table (optional tip).** Home → *Enter data* → create an empty table called `_Measures` and load it. Create every measure in this table, then delete its one empty column. Power BI moves the table to the top of the Fields list, so all measures are in one place.

**Display folders** (select a measure → Model view → Properties → *Display folder*):

| Folder | Measures |
|---|---|
| `Sales` | Total Revenue, Total Orders, AOV |
| `Customers` | Total Customers, Repeat Customers, Repeat Customer % |
| `Delivery` | Orders With Delivery Date, Late Orders, % Late Deliveries |
| `Reviews` | Avg Review Score, Avg Review - Late, Avg Review - On Time, Review Gap, Reviewed Orders |
| `vs Last Month` | every "Last Month" and "MoM" / "Change" measure |

---

## 3. Measures

### Sales

#### Total Revenue

```dax
Total Revenue =
SUM ( fact_sales[price] )
```

Adds up the item price of every delivered order item in the current filter. Freight is **not** included (it is a separate column), which matches the project's revenue definition.
**Format:** custom `"R$"#,##0` (or Currency, Portuguese (Brazil)).

#### Total Orders

```dax
Total Orders =
DISTINCTCOUNT ( fact_sales[order_id] )
```

Counts the different order IDs. `fact_sales` has one row per item, so an order with three items appears three times; `DISTINCTCOUNT` counts it once. Because it uses `fact_sales`, it responds to category and seller filters ("orders that contained this category").
**Format:** whole number, `#,##0`.

#### AOV (average order value)

```dax
AOV =
DIVIDE ( [Total Revenue], [Total Orders] )
```

Revenue divided by the number of orders – the average amount spent per order. `DIVIDE` returns blank instead of an error if there are no orders in the filter.
**Format:** `"R$"#,##0.00`.

### Customers

#### Total Customers

```dax
Total Customers =
DISTINCTCOUNT ( fact_sales[customer_unique_id] )
```

Counts the different people who placed a delivered order in the current filter. It uses `customer_unique_id` because `customer_id` is a new ID for every order (see `docs/cleaning_log.md`).
**Format:** `#,##0`.

#### Repeat Customers

```dax
Repeat Customers =
COUNTROWS (
    FILTER (
        VALUES ( fact_sales[customer_unique_id] ),
        CALCULATE ( DISTINCTCOUNT ( fact_sales[order_id] ) ) > 1
    )
)
```

Counts customers who placed **more than one** order inside the current filter (for example, the selected date range). Step by step:

1. `VALUES ( fact_sales[customer_unique_id] )` – makes a list of every customer who appears in the current filter (one row per customer).
2. `FILTER ( list, condition )` – goes through that list one customer at a time and keeps only those where the condition is true.
3. `CALCULATE ( DISTINCTCOUNT ( fact_sales[order_id] ) )` – for the customer currently being checked, counts their different orders. `CALCULATE` is what makes the count use "this customer only" (it turns the current row into a filter – called *context transition*). Any page filters, such as the date range, still apply.
4. `> 1` – keep the customer if they have two or more orders.
5. `COUNTROWS` – counts how many customers are left in the list.

**Format:** `#,##0`.

#### Repeat Customer %

```dax
Repeat Customer % =
DIVIDE ( [Repeat Customers], [Total Customers] )
```

The share of customers in the current filter who ordered more than once in that same filter.
**Format:** Percentage, 1 decimal place (`0.0%`).

> **Dynamic measure vs `dim_customer[customer_type]`.** The two answer slightly different questions:
> - **Repeat Customer %** (this measure) counts repeat buying **inside the selected period**. If you select only March 2018, a customer who ordered once in March and once in June counts as one-time, because June is outside the filter.
> - **`dim_customer[customer_type]`** is a fixed, **all-time** label worked out in SQL from the customer's whole history. Use it as a slicer or legend ("show me repeat customers"), not to measure repeat rate for a period.
>
> With no filters applied, both give the same customer split.

### Delivery

These measures use `fact_orders` (one row per order), because lateness is a property of an order, not of an item.

#### Orders With Delivery Date

```dax
Orders With Delivery Date =
CALCULATE (
    COUNTROWS ( fact_orders ),
    fact_orders[has_delivery_date] = 1
)
```

Counts delivered orders that have a customer delivery date. This is the base for % late: the few delivered orders with no delivery date are left out because we cannot tell whether they were late.
**Format:** `#,##0`.

#### Late Orders

```dax
Late Orders =
CALCULATE (
    COUNTROWS ( fact_orders ),
    fact_orders[is_late] = 1
)
```

Counts orders delivered after the estimated date (`is_late = 1`). "Late" compares calendar dates, so an order delivered on the promised day is on time (rule set in SQL, see the cleaning log).
**Format:** `#,##0`.

#### % Late Deliveries

```dax
% Late Deliveries =
DIVIDE ( [Late Orders], [Orders With Delivery Date] )
```

Late orders as a share of orders that have a delivery date. Calculated fresh from two counts, so it is correct at any level (month, state, region).
**Format:** Percentage, 1 decimal place (`0.0%`). Use the "bad" colour `#D1495B` for this measure.

### Reviews

#### Avg Review Score

```dax
Avg Review Score =
AVERAGE ( fact_orders[review_score] )
```

The average of the latest review score (1–5) per order. `AVERAGE` **ignores blank values**, so orders with no review are left out automatically – they are not counted as zero. This matches the SQL rule.
**Format:** decimal, 2 decimal places (`0.00`).

#### Avg Review - Late

```dax
Avg Review - Late =
CALCULATE (
    [Avg Review Score],
    fact_orders[late_status] = "Late"
)
```

The average review score for late orders only. `CALCULATE` runs the existing measure with an extra filter `late_status = "Late"`.
**Format:** `0.00`.

#### Avg Review - On Time

```dax
Avg Review - On Time =
CALCULATE (
    [Avg Review Score],
    fact_orders[late_status] = "On time"
)
```

The same calculation for orders that arrived on or before the estimated date. Orders with `late_status = "Unknown"` (no delivery date) are in neither group.
**Format:** `0.00`.

#### Review Gap

```dax
Review Gap =
[Avg Review - On Time] - [Avg Review - Late]
```

How many review points higher on-time orders score than late orders. A bigger gap means late delivery hurts customer satisfaction more.
**Format:** `0.00` (label it "points" on the visual).

#### Reviewed Orders

```dax
Reviewed Orders =
COUNT ( fact_orders[review_score] )
```

Counts orders that have a review. `COUNT` skips blanks, so orders with no review are not counted. It is used in the review-score distribution chart: put `review_score` in the legend and this measure in the values of a 100% stacked bar, and Power BI shows each score's share within each group.
**Format:** `#,##0`.

---

### "vs previous month" measures (for the KPI cards)

The KPI cards show this month's value and the change from the previous month. Every card uses the **same two-step pattern**, explained once here.

**Step 1 – "Last Month" measure.** Re-run the existing measure with the dates moved back one month:

```dax
CALCULATE ( [Some Measure], DATEADD ( dim_date[Date], -1, MONTH ) )
```

- `DATEADD ( dim_date[Date], -1, MONTH )` takes the dates currently selected (e.g. every day in August 2018) and shifts them back one month (every day in July 2018).
- `CALCULATE` runs the measure with those shifted dates instead of the current ones.
- This only works because `dim_date` has every day and is marked as the date table (section 1).

**Step 2 – "Change" measure.**

- For **counts and money** (revenue, orders, AOV) show the **percentage change**: `DIVIDE ( this month − last month, last month )`. `DIVIDE` returns blank instead of an error when last month is zero or blank.
- For **scores and rates** (average review, % late) show the **simple difference** (this month − last month). For a percentage this is a change in *percentage points*; a "percentage change of a percentage" confuses readers.

#### Revenue Last Month

```dax
Revenue Last Month =
CALCULATE (
    [Total Revenue],
    DATEADD ( dim_date[Date], -1, MONTH )
)
```

Revenue for the month before the one selected. **Format:** `"R$"#,##0`.

#### Revenue MoM %

```dax
Revenue MoM % =
DIVIDE (
    [Total Revenue] - [Revenue Last Month],
    [Revenue Last Month]
)
```

Month-on-month change in revenue, as a percentage of last month. **Format:** `+0.0%;-0.0%;0.0%` (shows a plus or minus sign).

#### Orders Last Month

```dax
Orders Last Month =
CALCULATE (
    [Total Orders],
    DATEADD ( dim_date[Date], -1, MONTH )
)
```

**Format:** `#,##0`.

#### Orders MoM %

```dax
Orders MoM % =
DIVIDE (
    [Total Orders] - [Orders Last Month],
    [Orders Last Month]
)
```

**Format:** `+0.0%;-0.0%;0.0%`.

#### AOV Last Month

```dax
AOV Last Month =
CALCULATE (
    [AOV],
    DATEADD ( dim_date[Date], -1, MONTH )
)
```

**Format:** `"R$"#,##0.00`.

#### AOV MoM %

```dax
AOV MoM % =
DIVIDE (
    [AOV] - [AOV Last Month],
    [AOV Last Month]
)
```

**Format:** `+0.0%;-0.0%;0.0%`.

#### Avg Review Last Month

```dax
Avg Review Last Month =
CALCULATE (
    [Avg Review Score],
    DATEADD ( dim_date[Date], -1, MONTH )
)
```

**Format:** `0.00`.

#### Avg Review Change

```dax
Avg Review Change =
[Avg Review Score] - [Avg Review Last Month]
```

Change in the average score, in review points (e.g. +0.10 means one tenth of a star higher). **Format:** `+0.00;-0.00;0.00`.

#### % Late Last Month

```dax
% Late Last Month =
CALCULATE (
    [% Late Deliveries],
    DATEADD ( dim_date[Date], -1, MONTH )
)
```

**Format:** `0.0%`.

#### % Late Change (pp)

```dax
% Late Change (pp) =
[% Late Deliveries] - [% Late Last Month]
```

Change in the late rate in **percentage points** (e.g. a move from 8% to 6% is −2 pp). Here a **fall is good**, so colour a rise with the "bad" colour and a fall with the "good" colour (the opposite of revenue). **Format:** `+0.0%;-0.0%;0.0%` (Power BI shows the pp change with a % sign; label it "pp" on the card).

---

## 4. Which months the overview page shows

- **KPI cards: latest full month (August 2018) vs the previous month (July 2018).** Add a visual-level filter on each KPI card: `dim_date[Year-Month]` = "2018-08". The "Last Month" measures then pick up July 2018 automatically.
- **Trend charts: January 2017 to August 2018 only.** Add a page-level filter on `dim_date[Year-Month]` (or a date range on `dim_date[Date]`, 1 Jan 2017 to 31 Aug 2018).

**Why:** the months outside this window are not real trading months. 2016 is the platform's launch period (very few orders and no orders at all in November 2016), and September–October 2018 come after the data snapshot and have no delivered orders. Plotting them would show false spikes and crashes, and comparing against them in a KPI card would give meaningless percentage changes. August 2018 is the last complete month. The SQL monthly trend uses the same window – see `docs/cleaning_log.md`. Totals by category, state, seller and customer still use all delivered orders.

---

## 5. Common mistakes (and how this model avoids them)

| Mistake | Why it is wrong | What we do instead |
|---|---|---|
| `AVERAGE ( fact_sales[price] )` for AOV | That is the average **item** price. An order with three items is split into three small values. | `AOV = DIVIDE ( [Total Revenue], [Total Orders] )` |
| `COUNTROWS ( fact_sales )` or `COUNT ( order_id )` for orders | `fact_sales` has one row per item, so multi-item orders are counted several times. | `DISTINCTCOUNT ( fact_sales[order_id] )` |
| Counting customers with `customer_id` | Olist gives a new `customer_id` for every order, so every customer looks like a one-time buyer. | `customer_unique_id` everywhere |
| Summing or averaging a pre-calculated percentage column | Adding up monthly or state percentages gives a meaningless number; averaging them ignores that some groups are much bigger. | Measures that divide two totals (`% Late Deliveries`, `Repeat Customer %`), so the rate is recalculated correctly at every level |
| Not marking the date table / no date table | `DATEADD` gives wrong or blank results, and a Year-Month filter on a card can stop "last month" from working. | `dim_date` built with `CALENDAR`, marked as date table |
| Month names sorted A–Z | Charts show Apr, Aug, Dec ... instead of Jan, Feb, Mar ... | Sort `Month Name` by `Month Number` and `Year-Month` by `Year-Month Sort` |
| Using `/` instead of `DIVIDE` | A month with zero orders gives an error or infinity. | `DIVIDE`, which returns blank |
| Including freight in revenue | Freight is a delivery charge, not product sales; the SQL excludes it. | `SUM ( fact_sales[price] )` only |
| Treating blank review scores as 0 | Would drag the average down for orders that were simply never reviewed. | `AVERAGE` skips blanks; do not replace blanks with 0 in Power Query |
| Expecting late/review measures to react to a category slicer | `fact_orders` has no category or seller column, so those slicers do not reach it. | Keep category and seller slicers on sales pages only |

---

## 6. Report colours (`powerbi/theme.json`)

Import with View → Themes → *Browse for themes*. Font throughout is **Segoe UI** (Power BI's default, clear on screen). Text sizes: KPI card values 28 pt, visual titles 14 pt, headers 12 pt, labels 10 pt. Visual borders and shadows are off by default.

| Colour | Hex | Use it for |
|---|---|---|
| Deep navy (primary) | `#1F3A5F` | Main series (revenue, orders), KPI values, table header accent, first data colour |
| Teal (secondary) | `#2A9D8F` | Second series, e.g. on-time orders or a comparison line |
| Mid grey (neutral) | `#8A939B` | Supporting or "everything else" series, gridline-level detail |
| Steel blue | `#4F7CAC` | Extra category colour (4th data colour) |
| Light teal | `#9CC5C0` | Extra category colour (5th data colour) |
| Muted green ("good") | `#5B8E7D` | Positive change (revenue up, % late down) |
| Red ("bad" accent) | `#D1495B` | Late deliveries and negative change only – use sparingly so it stands out |
| Light grey ("neutral") | `#C3C8CD` | No change / unknown values (e.g. `late_status = "Unknown"`) |
| Dark grey (text) | `#333F48` | All text (foreground) |
| White | `#FFFFFF` | Page and visual background |
| Pale blue → navy | `#DCE6F0` → `#1F3A5F` | Colour scale for maps or heat-map tables (low → high) |
