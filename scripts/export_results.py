"""
export_results.py - run the queries in a SQL file and save each result as a CSV.

Why: the mysql command-line client prints results as tab-separated text,
and a single SQL file can hold several queries. This script splits the file
on marker comments, runs each query with the mysql client, and writes one
CSV per query to data/exports/.

How to mark a query for export (in the .sql file):

    -- export: 06a_late_vs_ontime_reviews
    SELECT ...;

Everything before the first marker (e.g. `USE olist;`) is treated as a
preamble and run before every query. A query with no marker before it is
not exported.

Usage (from the project root; password comes from ~/.my.cnf):
    python3 scripts/export_results.py sql/03_monthly_revenue.sql
    python3 scripts/export_results.py sql/09_powerbi_views.sql data/exports/powerbi
"""

import csv
import re
import subprocess
import sys
from pathlib import Path

MARKER = re.compile(r"^--\s*export:\s*([A-Za-z0-9_]+)\s*$", re.MULTILINE)


def run_query(sql: str) -> list[list[str]]:
    """Run SQL through the mysql client and return rows (header first)."""
    result = subprocess.run(
        ["mysql", "--batch", "--default-character-set=utf8mb4", "olist"],
        input=sql,
        capture_output=True,
        text=True,
        check=True,
    )
    lines = result.stdout.splitlines()
    # --batch output is tab-separated; MySQL prints NULL as the text "NULL".
    return [["" if value == "NULL" else value for value in line.split("\t")] for line in lines]


def main() -> None:
    sql_path = Path(sys.argv[1])
    out_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("data/exports")
    out_dir.mkdir(parents=True, exist_ok=True)

    text = sql_path.read_text(encoding="utf-8")
    parts = MARKER.split(text)  # [preamble, name1, sql1, name2, sql2, ...]
    preamble = parts[0]

    for name, query in zip(parts[1::2], parts[2::2]):
        rows = run_query(preamble + "\n" + query)
        out_file = out_dir / f"{name}.csv"
        with out_file.open("w", newline="", encoding="utf-8") as fh:
            csv.writer(fh).writerows(rows)
        print(f"{out_file}: {max(len(rows) - 1, 0)} rows")


if __name__ == "__main__":
    main()
