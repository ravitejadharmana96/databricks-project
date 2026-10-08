"""Create batch_2: a later snapshot of batch_1 with realistic changes.

Same keys and row counts. Changes exercise the silver layer:
  customers / stores  -> SCD Type 2 (history kept)   - source_updated_date = business date of the change
  departments / orders -> SCD Type 1 (overwrite)
"""
import csv
import random
from datetime import date, timedelta
from pathlib import Path

random.seed(7)
ROOT = Path(__file__).resolve().parent.parent / "data" / "source"
SRC, OUT = ROOT / "batch_1", ROOT / "batch_2"
OUT.mkdir(parents=True, exist_ok=True)

CITIES = [("New York", "NY"), ("Boston", "MA"), ("Atlanta", "GA"), ("Miami", "FL"), ("Dallas", "TX"),
          ("Houston", "TX"), ("Chicago", "IL"), ("Columbus", "OH"), ("Denver", "CO"), ("Seattle", "WA"),
          ("San Francisco", "CA"), ("Los Angeles", "CA"), ("Phoenix", "AZ")]
FIRST = ["James", "Mary", "Raj", "Priya", "Wei", "Li", "Carlos", "Maria", "Ahmed", "Fatima", "John", "Emma"]
LAST = ["Smith", "Johnson", "Patel", "Sharma", "Chen", "Wang", "Garcia", "Lopez", "Khan", "Ali", "Brown", "Davis"]
NEXT_SEGMENT = {"Regular": "Premium", "Premium": "VIP", "VIP": "VIP"}
NEXT_STATUS = {"Pending": ["Shipped", "Completed", "Cancelled"], "Shipped": ["Completed", "Returned"]}


def change_date():
    """Business date of a change - spread over the order history so point-in-time joins are visible."""
    return (date(2025, 6, 1) + timedelta(days=random.randint(0, 420))).isoformat()


def read(name):
    with open(SRC / f"{name}.csv", newline="") as f:
        r = csv.DictReader(f)
        return r.fieldnames, list(r)


def write(name, header, rows):
    with open(OUT / f"{name}.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=header)
        w.writeheader()
        w.writerows(rows)


# customers (SCD-2): segment upgrade, relocation, preferred store change
header, rows = read("customers")
n = {"segment": 0, "city": 0, "store": 0}
for r in rows:
    hit = False
    if random.random() < 0.12:
        r["segment"] = NEXT_SEGMENT[r["segment"]]
        n["segment"] += 1
        hit = True
    if random.random() < 0.08:
        r["city"], r["state"] = random.choice(CITIES)
        n["city"] += 1
        hit = True
    if random.random() < 0.05:
        r["preferred_store_id"] = str(random.randint(1, len(rows)))
        n["store"] += 1
        hit = True
    if hit:
        r["source_updated_date"] = change_date()
write("customers", header, rows)
print("customers changes:", n)

# stores (SCD-2): new manager, expansion
header, rows = read("stores")
n = {"manager": 0, "sqft": 0}
for r in rows:
    hit = False
    if random.random() < 0.06:
        r["manager_name"] = f"{random.choice(FIRST)} {random.choice(LAST)}"
        n["manager"] += 1
        hit = True
    if random.random() < 0.03:
        r["square_feet"] = str(int(r["square_feet"]) + 5000)
        n["sqft"] += 1
        hit = True
    if hit:
        r["source_updated_date"] = change_date()
write("stores", header, rows)
print("stores changes:", n)

# departments (SCD-1): new budget / manager (overwritten in silver)
header, rows = read("departments")
n = 0
for r in rows:
    if random.random() < 0.10:
        r["annual_budget"] = f"{float(r['annual_budget']) * random.uniform(0.8, 1.3):.2f}"
        if random.random() < 0.5:
            r["manager_name"] = f"{random.choice(FIRST)} {random.choice(LAST)}"
        n += 1
write("departments", header, rows)
print("departments changes:", n)

# orders (SCD-1): open orders progress through the lifecycle
header, rows = read("orders")
n = 0
for r in rows:
    if r["status"] in NEXT_STATUS and random.random() < 0.25:
        r["status"] = random.choice(NEXT_STATUS[r["status"]])
        n += 1
write("orders", header, rows)
print("orders status changes:", n)
