#!/usr/bin/env python3
"""Independent reference implementation of the headline business metrics.

Computes the same numbers as analyses/business_questions.sql directly from the
raw CSVs in plain Python (Decimal arithmetic, no SQL, no dbt). Comparing the two
outputs checks the dbt models against a second, independent implementation of
the documented business rules. It does not prove either one is "correct" in an
absolute sense, only that both agree on the written definitions.
"""

from __future__ import annotations

import csv
from collections import defaultdict
from datetime import datetime
from decimal import Decimal
from pathlib import Path

DATA_DIR = Path(__file__).resolve().parent.parent / "data"
STATUS_MAP = {"completed": "completed", "complete": "completed", "pending": "pending",
              "cancelled": "cancelled", "canceled": "cancelled"}


def read(name: str) -> list[dict]:
    with (DATA_DIR / f"{name}.csv").open(newline="") as fh:
        return list(csv.DictReader(fh))


def parse_date(text: str):
    for fmt in ("%Y-%m-%d", "%Y/%m/%d"):
        try:
            return datetime.strptime(text.strip(), fmt).date()
        except ValueError:
            pass
    return None


def main() -> None:
    orders = {o["order_id"]: {**o, "status": STATUS_MAP[o["status"].strip().lower()],
                              "date": parse_date(o["order_date"])} for o in read("orders")}
    products = {p["product_id"]: p for p in read("products")}
    lines = read("order_items")

    completed = {oid for oid, o in orders.items() if o["status"] == "completed"}
    gross, disc, net, cnt = defaultdict(Decimal), defaultdict(Decimal), defaultdict(Decimal), defaultdict(set)
    product_net, customer_net = defaultdict(Decimal), defaultdict(Decimal)
    for li in lines:
        if li["order_id"] not in completed:
            continue
        o = orders[li["order_id"]]
        g = Decimal(li["quantity"]) * Decimal(li["unit_price"])
        d = Decimal(li["discount_amount"])
        month = o["date"].strftime("%Y-%m")
        gross[month] += g
        disc[month] += d
        net[month] += g - d
        cnt[month].add(li["order_id"])
        product_net[li["product_id"]] += g - d
        customer_net[o["customer_id"]] += g - d

    print("Q1 monthly sales (completed orders)")
    for m in sorted(net):
        print(f"  {m}: orders={len(cnt[m])} gross={gross[m]} discounts={disc[m]} net={net[m]}")

    print("Q2 top 5 products by net sales")
    for pid, v in sorted(product_net.items(), key=lambda kv: (-kv[1], kv[0]))[:5]:
        print(f"  {pid} {products[pid]['product_name']}: {v}")

    print("Q3 top 5 customers by net sales (raw customer_id)")
    for cid, v in sorted(customer_net.items(), key=lambda kv: (-kv[1], kv[0]))[:5]:
        print(f"  {cid}: {v}")

    total_net = sum(net.values())
    print(f"Q4 completed_orders={len(completed)} net_sales={total_net} "
          f"aov={(total_net / len(completed)).quantize(Decimal('0.01'))}")

    by_status = defaultdict(lambda: [0, Decimal(0)])
    for o in orders.values():
        by_status[o["status"]][0] += 1
        by_status[o["status"]][1] += Decimal(o["order_total"])
    print("Q5 orders by status (count, order value incl. tax)")
    for s in sorted(by_status):
        print(f"  {s}: {by_status[s][0]} {by_status[s][1]}")


if __name__ == "__main__":
    main()
