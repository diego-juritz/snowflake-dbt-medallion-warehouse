#!/usr/bin/env python3
"""Static checks on the seed CSVs that run without Snowflake (used in CI).

Verifies headers, primary-key uniqueness, referential integrity, and that the
order header totals reconcile with the line items. The single intentional
orphan order (documented in docs/data_dictionary.md) is expected and asserted.
"""

from __future__ import annotations

import csv
import sys
from decimal import Decimal
from pathlib import Path

DATA_DIR = Path(__file__).resolve().parent.parent / "data"
META = ["_record_id", "_source_file", "_extracted_at"]
EXPECTED_HEADERS = {
    "customers": ["customer_id", "first_name", "last_name", "email", "phone",
                  "country_code", "signup_date", "updated_at"],
    "products": ["product_id", "product_name", "category", "unit_price", "is_active"],
    "orders": ["order_id", "customer_id", "order_date", "status", "tax_amount", "order_total"],
    "order_items": ["order_item_id", "order_id", "product_id", "quantity", "unit_price", "discount_amount"],
    "payments": ["payment_id", "order_id", "payment_method", "payment_status", "amount", "payment_date"],
}
EXPECTED_ORPHAN_ORDERS = {"O0047"}


def load(name: str) -> list[dict]:
    with (DATA_DIR / f"{name}.csv").open(newline="") as fh:
        reader = csv.DictReader(fh)
        expected = [META[0], *EXPECTED_HEADERS[name], *META[1:]]
        if reader.fieldnames != expected:
            raise AssertionError(f"{name}.csv header {reader.fieldnames} != {expected}")
        return list(reader)


def main() -> int:
    errors: list[str] = []
    data = {name: load(name) for name in EXPECTED_HEADERS}

    for name, key in [("products", "product_id"), ("orders", "order_id"),
                      ("order_items", "order_item_id"), ("payments", "payment_id")]:
        keys = [r[key] for r in data[name]]
        if len(keys) != len(set(keys)):
            errors.append(f"{name}.{key} is not unique")
    for name, rows in data.items():
        ids = [r["_record_id"] for r in rows]
        if len(ids) != len(set(ids)):
            errors.append(f"{name}._record_id is not unique")

    customer_ids = {r["customer_id"] for r in data["customers"]}
    orphans = {r["order_id"] for r in data["orders"] if r["customer_id"] not in customer_ids}
    if orphans != EXPECTED_ORPHAN_ORDERS:
        errors.append(f"orphan orders {sorted(orphans)} != expected {sorted(EXPECTED_ORPHAN_ORDERS)}")

    order_ids = {r["order_id"] for r in data["orders"]}
    product_ids = {r["product_id"] for r in data["products"]}
    for r in data["order_items"]:
        if r["order_id"] not in order_ids or r["product_id"] not in product_ids:
            errors.append(f"order item {r['order_item_id']} has a dangling reference")
    for r in data["payments"]:
        if r["order_id"] not in order_ids:
            errors.append(f"payment {r['payment_id']} references unknown order")

    net_by_order: dict[str, Decimal] = {}
    for r in data["order_items"]:
        line = Decimal(r["quantity"]) * Decimal(r["unit_price"]) - Decimal(r["discount_amount"])
        net_by_order[r["order_id"]] = net_by_order.get(r["order_id"], Decimal(0)) + line
    for r in data["orders"]:
        expected = net_by_order.get(r["order_id"], Decimal(0)) + Decimal(r["tax_amount"])
        if expected != Decimal(r["order_total"]):
            errors.append(f"order {r['order_id']} total {r['order_total']} != items + tax {expected}")

    if errors:
        print("Sample data validation FAILED:\n  " + "\n  ".join(errors))
        return 1
    counts = ", ".join(f"{n}={len(rows)}" for n, rows in data.items())
    print(f"Sample data validation passed ({counts}; expected orphan orders: {sorted(orphans)}).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
