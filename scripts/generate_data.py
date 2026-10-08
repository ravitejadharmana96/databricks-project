"""Generate 1000-row related sample tables (departments, stores, customers, orders) as CSV."""
import csv
import random
from datetime import date, timedelta
from pathlib import Path

random.seed(42)
N = 1000
OUT = Path(__file__).resolve().parent.parent / "data" / "source" / "batch_1"
OUT.mkdir(parents=True, exist_ok=True)
LAST_ORDER_DATE = date(2026, 10, 1)  # no future-dated orders
INITIAL_DATE = "2024-12-31"  # business date of the initial load (before the first order)

FIRST = ["James", "Mary", "Raj", "Priya", "Wei", "Li", "Carlos", "Maria", "Ahmed", "Fatima", "John", "Emma",
         "Liam", "Olivia", "Noah", "Sophia", "Arjun", "Ananya", "Kenji", "Yuki", "Lucas", "Mia", "Omar", "Zara"]
LAST = ["Smith", "Johnson", "Patel", "Sharma", "Chen", "Wang", "Garcia", "Lopez", "Khan", "Ali", "Brown",
        "Davis", "Miller", "Wilson", "Kumar", "Singh", "Tanaka", "Sato", "Silva", "Costa", "Nguyen", "Kim"]
CITIES = [("New York", "NY", "East"), ("Boston", "MA", "East"), ("Atlanta", "GA", "South"), ("Miami", "FL", "South"),
          ("Dallas", "TX", "South"), ("Houston", "TX", "South"), ("Chicago", "IL", "Midwest"),
          ("Columbus", "OH", "Midwest"), ("Denver", "CO", "West"), ("Seattle", "WA", "West"),
          ("San Francisco", "CA", "West"), ("Los Angeles", "CA", "West"), ("Phoenix", "AZ", "West")]
CATEGORIES = ["Electronics", "Grocery", "Apparel", "Home & Garden", "Toys", "Sports", "Beauty", "Books",
              "Automotive", "Pharmacy", "Furniture", "Pet Supplies"]
SUFFIX = ["Core", "Premium", "Value", "Online", "Seasonal"]


def write(name, header, rows):
    with open(OUT / f"{name}.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)
    print(f"{name}.csv: {len(rows)} rows")


# departments (PK department_id)
departments = []
for i in range(1, N + 1):
    cat = CATEGORIES[(i - 1) % len(CATEGORIES)]
    departments.append([
        i, f"{cat} {SUFFIX[(i // len(CATEGORIES)) % len(SUFFIX)]} {i:04d}", cat,
        f"{random.choice(FIRST)} {random.choice(LAST)}",
        round(random.lognormvariate(11.5, 0.6), 2),
    ])
write("departments", ["department_id", "department_name", "category", "manager_name", "annual_budget"], departments)

# stores (PK store_id)
stores = []
for i in range(1, N + 1):
    city, state, region = random.choices(CITIES, weights=[10, 5, 7, 6, 6, 6, 8, 4, 5, 5, 7, 8, 4])[0]
    stores.append([
        i, f"{city} Store {i:04d}", city, state, region,
        f"{random.choice(FIRST)} {random.choice(LAST)}",
        random.randint(8, 120) * 500,
        (date(2005, 1, 1) + timedelta(days=random.randint(0, 6900))).isoformat(),
        INITIAL_DATE,
    ])
write("stores", ["store_id", "store_name", "city", "state", "region", "manager_name", "square_feet", "open_date",
                 "source_updated_date"], stores)

# customers (PK customer_id, FK preferred_store_id -> stores)
customers = []
for i in range(1, N + 1):
    fn, ln = random.choice(FIRST), random.choice(LAST)
    city, state, _ = random.choice(CITIES)
    customers.append([
        i, fn, ln, f"{fn.lower()}.{ln.lower()}{i}@example.com",
        f"+1-555-{random.randint(100, 999)}-{random.randint(1000, 9999)}",
        city, state,
        random.choices(["Regular", "Premium", "VIP"], weights=[70, 22, 8])[0],
        (date(2020, 1, 1) + timedelta(days=random.randint(0, 2100))).isoformat(),
        random.randint(1, N),
        INITIAL_DATE,
    ])
write("customers", ["customer_id", "first_name", "last_name", "email", "phone", "city", "state",
                    "segment", "signup_date", "preferred_store_id", "source_updated_date"], customers)

# orders (PK order_id, FKs -> customers, stores, departments)
# skew: ~20% of customers place ~60% of orders
heavy = random.sample(range(1, N + 1), N // 5)
orders = []
for i in range(1, N + 1):
    cust = random.choice(heavy) if random.random() < 0.6 else random.randint(1, N)
    qty = random.choices([1, 2, 3, 4, 5, 10], weights=[45, 25, 12, 8, 6, 4])[0]
    price = round(random.lognormvariate(3.3, 0.8), 2)
    orders.append([
        i, cust, random.randint(1, N), random.randint(1, N),
        min(date(2025, 1, 1) + timedelta(days=random.randint(0, 650)), LAST_ORDER_DATE).isoformat(),
        random.choices(["Completed", "Shipped", "Pending", "Cancelled", "Returned"], weights=[62, 14, 9, 9, 6])[0],
        qty, price, round(qty * price, 2),
        random.choices(["Credit Card", "Debit Card", "Cash", "Gift Card", "PayPal"], weights=[40, 25, 15, 5, 15])[0],
    ])
write("orders", ["order_id", "customer_id", "store_id", "department_id", "order_date", "status",
                 "quantity", "unit_price", "total_amount", "payment_method"], orders)
