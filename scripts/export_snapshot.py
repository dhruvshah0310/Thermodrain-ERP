#!/usr/bin/env python3
"""
Dumps the live erp.db into client/src/preview/snapshot.json — the embedded
dataset the client-side-only preview build (npm run build:preview) uses in
place of a real backend. Re-run this after re-importing/editing the Purchase
data so the preview reflects it.

Run with: python3 scripts/export_snapshot.py [--db path/to/erp.db]
"""
import argparse
import json
import sqlite3
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DB_PATH = REPO_ROOT / "server" / "data" / "erp.db"
OUTPUT_PATH = REPO_ROOT / "client" / "src" / "preview" / "snapshot.json"

TABLES = [
    "departments", "units", "accounts", "materials", "material_taxonomy",
    "purchase_indents", "purchase_indent_items",
    "sanction_indents", "sanction_indent_items",
    "rfqs", "rfq_items", "rfq_vendors",
    "purchase_quotations", "purchase_quotation_items",
    "purchase_orders", "purchase_order_items",
    "grns", "grn_items",
]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default=str(DEFAULT_DB_PATH))
    args = parser.parse_args()

    conn = sqlite3.connect(args.db)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    snapshot = {}
    for table in TABLES:
        cur.execute(f"SELECT * FROM {table}")
        rows = [dict(r) for r in cur.fetchall()]
        snapshot[table] = rows
        print(f"{table}: {len(rows)} rows")

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT_PATH, "w") as f:
        json.dump(snapshot, f, separators=(",", ":"))

    print(f"Wrote {OUTPUT_PATH} ({OUTPUT_PATH.stat().st_size / 1024:.0f} KB)")


if __name__ == "__main__":
    main()
