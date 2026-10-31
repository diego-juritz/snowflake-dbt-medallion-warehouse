#!/usr/bin/env python3
"""Generate the deterministic synthetic e-commerce dataset used as dbt seeds.

All data is fictional. The generator uses a fixed random seed, integer-cent
arithmetic, and no wall-clock values, so every run produces byte-identical CSVs.

Usage:
    python scripts/generate_sample_data.py           # (re)write data/*.csv
    python scripts/generate_sample_data.py --check   # fail if data/*.csv differ
"""

from __future__ import annotations

import argparse
import csv
import io
import random
import sys
from datetime import date, timedelta
from pathlib import Path

RANDOM_SEED = 20250101
DATA_DIR = Path(__file__).resolve().parent.parent / "data"

# Simulated export metadata: the source system "exported" every file at this
# fixed instant. It is NOT the time the file was loaded into Snowflake.
EXTRACTED_AT = "2026-01-01T00:00:00Z"

TAX_RATE_BASIS_POINTS = 800  # 8.00 % tax on net merchandise value
ORPHAN_CUSTOMER_ID = "C999"  # intentionally missing from customers.csv
ORPHAN_ORDER_ID = "O0047"

FIRST_NAMES = [
    "Ava", "Liam", "Mia", "Noah", "Zoe", "Ethan", "Ivy", "Lucas", "Nora", "Owen",
    "Ruby", "Leo", "Isla", "Finn", "Maya", "Jude", "Elena", "Hugo", "Clara", "Theo",
    "Lena", "Felix", "Iris", "Oscar", "Sofia", "Milo", "Alma", "Rafael", "Ines", "Tomas",
]
LAST_NAMES = [
    "Reyes", "Novak", "Okafor", "Lindqvist", "Moreau", "Tanaka", "Silva", "Kowalski",
    "Haddad", "Fischer", "Rossi", "Nakamura", "Duarte", "Ibrahim", "Larsen", "Costa",
    "Petrov", "Mendes", "Varga", "O'Brien", "Schmidt", "Alves", "Kim", "Romero",
    "Weber", "Castro", "Jansen", "Ortega", "Sato", "Brennan",
]
COUNTRIES = ["US", "CA", "GB", "DE", "ES", "BR", "AR", "JP"]

PRODUCTS = [
    # product_id, name, raw category (inconsistent on purpose), price in cents, is_active
    ("P001", "Wireless Mouse", "Electronics", 2499, "true"),
    ("P002", "Mechanical Keyboard", "electronics", 8999, "true"),
    ("P003", "USB-C Hub", " ELECTRONICS ", 3999, "TRUE"),
    ("P004", "27in Monitor", "Electronics", 27900, "true"),
    ("P005", "Noise-Cancelling Headphones", "Electronics", 19900, "true"),
    ("P006", "Standing Desk", "Furniture", 44900, "true"),
    ("P007", "Ergonomic Chair", "furniture", 32900, "true"),
    ("P008", "Desk Lamp", "Home Office", 3450, "true"),
    ("P009", "Notebook Set", "Stationery", 1299, "true"),
    ("P010", "Gel Pens (12 pack)", "stationery", 899, "true"),
    ("P011", "Laptop Sleeve", "Accessories", 2999, "true"),
    ("P012", "Webcam HD", "Electronics", 6999, "false"),  # discontinued, still sold early in year
    ("P013", "Cable Organizer", "", 1499, "true"),  # missing category
    ("P014", "Monitor Arm", "Furniture", 11900, "True"),
    ("P015", "Coffee Mug", "Home Office", 1599, "true"),
]

ORDER_STATUS_VARIANTS = {
    "completed": ["completed", "Completed", "COMPLETED", "complete"],
    "pending": ["pending", "Pending", " pending"],
    "cancelled": ["cancelled", "Cancelled", "canceled"],
}

PAYMENT_METHOD_VARIANTS = ["credit_card", "Credit Card", "CREDIT_CARD", "paypal", "PayPal", "bank_transfer"]


def money(cents: int) -> str:
    return f"{cents // 100}.{cents % 100:02d}"


def generate_customers(rng: random.Random) -> list[dict]:
    customers = []
    for i in range(30):
        cid = f"C{i + 1:03d}"
        first, last = FIRST_NAMES[i], LAST_NAMES[i]
        signup = date(2024, 1, 1) + timedelta(days=rng.randint(0, 360))
        customers.append(
            {
                "customer_id": cid,
                "first_name": first,
                "last_name": last,
                "email": f"{first.lower()}.{last.lower().replace(chr(39), '')}@example.com",
                "phone": f"+1-555-{rng.randint(1000, 9999)}" if i % 4 else "",  # optional
                "country_code": COUNTRIES[i % len(COUNTRIES)] if i not in (8, 21) else "",
                "signup_date": signup.isoformat(),
                "updated_at": f"{signup.isoformat()} 09:00:00",
            }
        )

    # Messy formatting on otherwise unique records.
    customers[2]["first_name"] = "  mia"            # leading spaces + lower case
    customers[6]["last_name"] = "silva   "          # trailing spaces + lower case
    customers[10]["email"] = "RUBY.ROSSI@EXAMPLE.COM"
    customers[14]["country_code"] = "es"

    rows = list(customers)
    # Duplicate source records (CDC-style re-exports of the same business key).
    c5 = dict(customers[4])  # older version of C005 with dirty values
    c5.update(first_name=" ZOE ", email=" Zoe.Moreau@Example.com ", updated_at="2024-01-02 08:00:00")
    c5_new = dict(customers[4])
    c5_new.update(updated_at="2025-03-01 10:00:00", country_code="FR")  # customer moved
    rows[4] = c5
    rows.append(c5_new)

    # Exact timestamp tie on C012: the later _record_id wins (documented tie-breaker).
    c12_tie = dict(customers[11])
    c12_tie.update(phone="+1-555-0012")
    rows.append(c12_tie)

    # Three versions of C020; the middle one is the latest by updated_at.
    c20_v2 = dict(customers[19])
    c20_v2.update(email="theo.obrien@example.org", updated_at="2025-06-15 12:00:00")
    c20_v3 = dict(customers[19])
    c20_v3.update(email="theo.b@example.net", updated_at="2025-02-01 12:00:00")  # stale re-export
    rows.extend([c20_v2, c20_v3])
    return rows


def generate_orders(rng: random.Random):
    orders, items, payments = [], [], []
    item_seq, pay_seq = 1, 1
    start = date(2025, 1, 3)
    for n in range(1, 81):
        oid = f"O{n:04d}"
        cid = ORPHAN_CUSTOMER_ID if oid == ORPHAN_ORDER_ID else f"C{rng.randint(1, 30):03d}"
        order_date = start + timedelta(days=(n - 1) * 4 + rng.randint(0, 3))
        roll = rng.random()
        if roll < 0.12:
            status = "cancelled"
        elif roll < 0.20:
            status = "pending"
        else:
            status = "completed"
        if oid == ORPHAN_ORDER_ID:
            status = "completed"
        raw_status = rng.choice(ORDER_STATUS_VARIANTS[status])
        date_text = order_date.strftime("%Y/%m/%d") if n % 17 == 0 else order_date.isoformat()

        net_cents = 0
        for product in rng.sample(PRODUCTS, rng.randint(1, 4)):
            if product[0] == "P012" and order_date.month > 3:
                continue  # discontinued product no longer sold
            qty = rng.randint(1, 3)
            gross = qty * product[3]
            discount = gross // 10 if rng.random() < 0.15 else 0
            net_cents += gross - discount
            items.append(
                {
                    "order_item_id": f"OI{item_seq:05d}",
                    "order_id": oid,
                    "product_id": product[0],
                    "quantity": str(qty),
                    "unit_price": money(product[3]),
                    "discount_amount": money(discount),
                }
            )
            item_seq += 1
        if net_cents == 0:  # every order must have at least one line
            product = PRODUCTS[8]
            net_cents = product[3]
            items.append(
                {
                    "order_item_id": f"OI{item_seq:05d}",
                    "order_id": oid,
                    "product_id": product[0],
                    "quantity": "1",
                    "unit_price": money(product[3]),
                    "discount_amount": "0.00",
                }
            )
            item_seq += 1

        tax = (net_cents * TAX_RATE_BASIS_POINTS + 5000) // 10000  # round half up
        total = net_cents + tax
        orders.append(
            {
                "order_id": oid,
                "customer_id": cid,
                "order_date": date_text,
                "status": raw_status,
                "tax_amount": money(tax),
                "order_total": money(total),
            }
        )

        def pay(amount: int, pay_status: str, day_offset: int = 0, method: str | None = None):
            nonlocal pay_seq
            payments.append(
                {
                    "payment_id": f"PAY{pay_seq:05d}",
                    "order_id": oid,
                    "payment_method": method or rng.choice(PAYMENT_METHOD_VARIANTS),
                    "payment_status": pay_status,
                    "amount": money(amount),
                    "payment_date": (order_date + timedelta(days=day_offset)).isoformat(),
                }
            )
            pay_seq += 1

        scenario = rng.random()
        if status == "completed":
            if scenario < 0.12:
                pay(total, "failed")                       # declined first attempt
                pay(total, "success", 1)
            elif scenario < 0.24:
                gift = min(2500, total // 2)
                pay(gift, "success", method="gift_card")   # split tender
                pay(total - gift, "success")
            else:
                pay(total, "success")
        elif status == "pending":
            if scenario < 0.6:
                pay(total, "pending")
        else:  # cancelled
            if scenario < 0.35:
                pay(total, "success")
                pay(total, "refunded", 2)                  # paid, then fully refunded
            elif scenario < 0.6:
                pay(total, "failed")
    return orders, items, payments


def to_csv(rows: list[dict], with_metadata: bool, source_file: str) -> str:
    fields = list(rows[0].keys())
    if with_metadata:
        fields = ["_record_id", *fields, "_source_file", "_extracted_at"]
    buf = io.StringIO()
    writer = csv.DictWriter(buf, fieldnames=fields, lineterminator="\n")
    writer.writeheader()
    for idx, row in enumerate(rows, start=1):
        out = dict(row)
        if with_metadata:
            out.update(_record_id=str(idx), _source_file=source_file, _extracted_at=EXTRACTED_AT)
        writer.writerow(out)
    return buf.getvalue()


def build() -> dict[str, str]:
    rng = random.Random(RANDOM_SEED)
    customers = generate_customers(rng)
    products = [
        {"product_id": p[0], "product_name": p[1], "category": p[2], "unit_price": money(p[3]), "is_active": p[4]}
        for p in PRODUCTS
    ]
    orders, items, payments = generate_orders(rng)
    datasets = {"customers": customers, "products": products, "orders": orders,
                "order_items": items, "payments": payments}
    return {name: to_csv(rows, True, f"{name}.csv") for name, rows in datasets.items()}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="verify committed CSVs match the generator")
    args = parser.parse_args()

    outputs = build()
    if args.check:
        stale = [n for n, text in outputs.items()
                 if not (DATA_DIR / f"{n}.csv").exists() or (DATA_DIR / f"{n}.csv").read_text() != text]
        if stale:
            print(f"Out-of-date CSVs: {', '.join(stale)}. Run: python scripts/generate_sample_data.py")
            return 1
        print("All CSVs match the deterministic generator.")
        return 0

    DATA_DIR.mkdir(exist_ok=True)
    for name, text in outputs.items():
        (DATA_DIR / f"{name}.csv").write_text(text)
        print(f"wrote data/{name}.csv ({text.count(chr(10)) - 1} rows)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
