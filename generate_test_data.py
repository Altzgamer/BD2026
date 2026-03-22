#!/usr/bin/env python3
"""
generate_test_data.py — скрипт генерации тестовых данных для БД "Пивной импортёр"

Требования:
    pip install psycopg2-binary faker

Использование:
    python generate_test_data.py [опции]

Опции:
    --host      хост PostgreSQL (по умолчанию: localhost)
    --port      порт           (по умолчанию: 5432)
    --db        имя базы       (по умолчанию: beer_import_db)
    --user      пользователь   (по умолчанию: postgres)
    --password  пароль         (по умолчанию: пустой)
    --breweries количество пивоварен (по умолчанию: 20)
    --beers     количество видов пива (по умолчанию: 100)
    --warehouses количество складов (по умолчанию: 10)
    --venues    количество заведений (по умолчанию: 30)
    --pc        количество договоров закупок (по умолчанию: 20)
    --dc        количество договоров поставок (по умолчанию: 30)
    --clean     очистить тестовые данные (оставить seed)
"""

import argparse
import random
import sys
from datetime import date, timedelta
from decimal import Decimal

try:
    import psycopg2
    import psycopg2.extras
    from faker import Faker
except ImportError as e:
    print(f"Ошибка: {e}\nУстановите зависимости: pip install psycopg2-binary faker")
    sys.exit(1)

# Faker для русских/международных данных
fake_ru = Faker("ru_RU")
fake_en = Faker("en_US")

SEED_COUNTRIES = 7    # количество стран из seed.sql
SEED_STYLES    = 8    # количество стилей из seed.sql
SEED_POSITIONS = 4    # количество должностей
SEED_EMPLOYEES = 4    # сотрудники из seed.sql (id 1..4)
SEED_BREWERIES = 5
SEED_BEERS     = 5
SEED_WAREHOUSES = 3
SEED_VENUES    = 3
SEED_CONTRACTS_P = 1  # purchase contracts
SEED_CONTRACTS_D = 1  # delivery contracts

EXCHANGE_RATES = [85.0, 88.5, 90.0, 91.2, 93.0, 89.0]

BEER_NAMES = [
    "Golden Ale", "Dark Lager", "Winter Porter", "Amber Weiss",
    "Pale Rider", "Black Castle Stout", "Hoppy IPA", "Vintage Pilsner",
    "Crystal Wheat", "Midnight Porter", "Baltic Gold", "Triple Hop",
    "Red Sunset", "Belgian Tripel", "Smoky Rauchbier", "Vienna Malt",
    "Bavarian Dunkel", "Summer Session", "Monk's Reserve", "Cherry Kriek",
]

COLORS = ["Светлое", "Тёмное", "Янтарное", "Медное", "Чёрное", "Рыжее"]
CONTAINERS = ["Стекло", "Банка", "Кег 30L", "Кег 50L", "ПЭТ"]
VENUE_TYPES = ["bar", "pub", "brasserie", "club", "shop"]
PURCHASE_TYPES = ["initiative", "order", "stock_balance"]


def parse_args():
    p = argparse.ArgumentParser(description="Генератор тестовых данных для beer_import")
    p.add_argument("--host",       default="localhost")
    p.add_argument("--port",       type=int, default=5432)
    p.add_argument("--db",         default="beer_import_db")
    p.add_argument("--user",       default="postgres")
    p.add_argument("--password",   default="")
    p.add_argument("--breweries",  type=int, default=20)
    p.add_argument("--beers",      type=int, default=100)
    p.add_argument("--warehouses", type=int, default=10)
    p.add_argument("--venues",     type=int, default=30)
    p.add_argument("--pc",         type=int, default=20,  help="Договоров закупок")
    p.add_argument("--dc",         type=int, default=30,  help="Договоров поставок")
    p.add_argument("--clean",      action="store_true",   help="Только очистка тестовых данных")
    return p.parse_args()


def get_connection(args):
    return psycopg2.connect(
        host=args.host, port=args.port,
        dbname=args.db, user=args.user,
        password=args.password,
        options="-c search_path=beer_import"
    )


def clean_test_data(cur):
    """Удаляет данные с id > seed-порогов (оставляет seed-данные)."""
    print("Очистка тестовых данных...")
    # Порядок важен: сначала дочерние таблицы
    tables_with_thresholds = [
        ("transfer_document_item", "document_id",   2),
        ("transfer_document",      "id",             2),
        ("incoming_payment_item",  "payment_id",     1),
        ("incoming_payment",       "id",             1),
        ("delivery_plan_item",     "id",             2),
        ("delivery_plan",          "id",             1),
        ("delivery_contract_item", "contract_id",    1),
        ("delivery_contract",      "id",             1),
        ("invoice_item",           "invoice_id",     1),
        ("invoice",                "id",             1),
        ("outgoing_payment",       "id",             2),
        ("payment_plan_item",      "id",             2),
        ("purchase_contract_item", "contract_id",    1),
        ("purchase_contract",      "id",             1),
        ("warehouse_stock",        "warehouse_id",   SEED_WAREHOUSES),
        ("warehouse",              "id",             SEED_WAREHOUSES),
        ("beer",                   "id",             SEED_BEERS),
        ("brewery",                "id",             SEED_BREWERIES),
        ("venue",                  "id",             SEED_VENUES),
        ("address",                "id",             11),
        ("employee",               "id",             SEED_EMPLOYEES),
    ]
    for table, col, seed_max in tables_with_thresholds:
        cur.execute(f"DELETE FROM beer_import.{table} WHERE {col} > %s", (seed_max,))
        print(f"  {table}: удалено {cur.rowcount} строк")


def rnd_date(start_year=2023, end_year=2025) -> date:
    start = date(start_year, 1, 1)
    end   = date(end_year, 12, 31)
    return start + timedelta(days=random.randint(0, (end - start).days))


def rnd_price(lo=1.5, hi=8.0) -> Decimal:
    return Decimal(f"{random.uniform(lo, hi):.2f}")


def rnd_rate() -> Decimal:
    return Decimal(f"{random.choice(EXCHANGE_RATES):.4f}")


# ---------------------------------------------------------------

def insert_addresses(cur, n) -> list[int]:
    rows = []
    for _ in range(n):
        city = fake_ru.city()
        street = fake_ru.street_address()
        lat = round(random.uniform(50.0, 70.0), 6)
        lon = round(random.uniform(30.0, 80.0), 6)
        cur.execute(
            "INSERT INTO address(city, street, latitude, longitude) VALUES(%s,%s,%s,%s) RETURNING id",
            (city, street, lat, lon)
        )
        rows.append(cur.fetchone()[0])
    return rows


def insert_breweries(cur, n, country_ids, address_ids) -> list[int]:
    ids = []
    for i in range(n):
        name = f"{fake_en.last_name()} Brewery {random.randint(1, 999)}"
        cur.execute(
            """INSERT INTO brewery(name, country_id, address_id, founded_year)
               VALUES(%s,%s,%s,%s) RETURNING id""",
            (name,
             random.choice(country_ids),
             random.choice(address_ids),
             random.randint(1800, 2010))
        )
        ids.append(cur.fetchone()[0])
    return ids


def insert_beers(cur, n, brewery_ids, style_ids) -> list[int]:
    ids = []
    used_names = set()
    for _ in range(n):
        base_name = random.choice(BEER_NAMES)
        suffix = random.randint(100, 999)
        name = f"{base_name} {suffix}"
        while name in used_names:
            suffix = random.randint(100, 9999)
            name = f"{base_name} {suffix}"
        used_names.add(name)

        price_usd = rnd_price(1.5, 8.0)
        rate      = rnd_rate()
        price_rub = (price_usd * rate).quantize(Decimal("0.01"))
        wholesale = (price_rub * Decimal("1.3")).quantize(Decimal("0.01"))
        retail    = (wholesale * Decimal("1.15")).quantize(Decimal("0.01"))

        cur.execute(
            """INSERT INTO beer
                   (brewery_id, style_id, name, alcohol_pct, color, density,
                    drinkability, rating, volume_l, container,
                    last_price_usd, last_price_rub, wholesale_price_rub,
                    retail_price_rub, description)
               VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
               RETURNING id""",
            (random.choice(brewery_ids),
             random.choice(style_ids),
             name,
             round(random.uniform(3.0, 12.0), 1),
             random.choice(COLORS),
             round(random.uniform(9.0, 20.0), 3),
             round(random.uniform(4.0, 9.5), 1),
             round(random.uniform(5.0, 9.5), 1),
             round(random.choice([0.33, 0.375, 0.5, 0.75, 1.0]), 3),
             random.choice(CONTAINERS),
             price_usd, price_rub, wholesale, retail,
             fake_en.sentence(nb_words=10))
        )
        ids.append(cur.fetchone()[0])
    return ids


def insert_warehouses(cur, n, address_ids) -> list[int]:
    ids = []
    for i in range(n):
        city_code = fake_ru.city()[:3].upper()
        code = f"WH-{city_code}-{random.randint(10, 99):02d}"
        cur.execute(
            """INSERT INTO warehouse(code, address_id, capacity, phone, manager_name)
               VALUES(%s,%s,%s,%s,%s) RETURNING id""",
            (code,
             random.choice(address_ids),
             round(random.uniform(5000, 100000), 0),
             fake_ru.phone_number(),
             fake_ru.name())
        )
        ids.append(cur.fetchone()[0])
    return ids


def insert_venues(cur, n, address_ids) -> list[int]:
    ids = []
    for _ in range(n):
        cur.execute(
            """INSERT INTO venue(name, address_id, phone, type, status)
               VALUES(%s,%s,%s,%s,%s) RETURNING id""",
            (fake_ru.company(),
             random.choice(address_ids),
             fake_ru.phone_number(),
             random.choice(VENUE_TYPES),
             "active")
        )
        ids.append(cur.fetchone()[0])
    return ids


def insert_purchase_contracts(cur, n, brewery_ids, beer_ids, purchase_mgr_id, accountant_id,
                               warehouse_ids) -> int:
    created = 0
    for _ in range(n):
        rate         = rnd_rate()
        contract_date = rnd_date(2023, 2025)

        # Выбрать 2–4 случайных вида пива
        items_beer = random.sample(beer_ids, k=min(random.randint(2, 4), len(beer_ids)))
        items = [(b, random.randint(100, 2000), rnd_price(1.5, 7.0)) for b in items_beer]
        total = sum(qty * price for _, qty, price in items)

        cur.execute(
            """INSERT INTO purchase_contract
               (brewery_id, manager_id, contract_date, total_amount_usd, exchange_rate)
               VALUES(%s,%s,%s,%s,%s) RETURNING id""",
            (random.choice(brewery_ids), purchase_mgr_id, contract_date, total, rate)
        )
        pc_id = cur.fetchone()[0]

        # Строки договора
        for beer_id, qty, price in items:
            cur.execute(
                "INSERT INTO purchase_contract_item(contract_id, beer_id, quantity, price_usd) VALUES(%s,%s,%s,%s)",
                (pc_id, beer_id, qty, price)
            )
            # Обновляем последнюю цену в каталоге
            price_rub = (price * rate).quantize(Decimal("0.01"))
            wholesale  = (price_rub * Decimal("1.3")).quantize(Decimal("0.01"))
            cur.execute(
                "UPDATE beer SET last_price_usd=%s, last_price_rub=%s, wholesale_price_rub=%s WHERE id=%s",
                (price, price_rub, wholesale, beer_id)
            )

        # План оплат: 2 платежа (50/50)
        half = (total / 2).quantize(Decimal("0.01"))
        for i, due_offset in enumerate([30, 60]):
            due_date = contract_date + timedelta(days=due_offset)
            cur.execute(
                "INSERT INTO payment_plan_item(contract_id, due_date, amount_usd) VALUES(%s,%s,%s) RETURNING id",
                (pc_id, due_date, half)
            )
            ppi_id = cur.fetchone()[0]

            # Платёж
            pay_date     = due_date - timedelta(days=random.randint(1, 3))
            p_type       = random.choice(PURCHASE_TYPES)
            cur.execute(
                """INSERT INTO outgoing_payment
                   (payment_plan_item_id, accountant_id, payment_date, amount_usd, exchange_rate, purchase_type)
                   VALUES(%s,%s,%s,%s,%s,%s)""",
                (ppi_id, accountant_id, pay_date, half, rate, p_type)
            )

        cur.execute("UPDATE purchase_contract SET is_paid=TRUE WHERE id=%s", (pc_id,))

        # Накладная
        warehouse_id  = random.choice(warehouse_ids)
        inv_date      = contract_date + timedelta(days=random.randint(45, 90))
        total_rub     = (total * rate).quantize(Decimal("0.01"))
        cur.execute(
            """INSERT INTO invoice(contract_id, warehouse_id, invoice_date, total_usd, total_rub)
               VALUES(%s,%s,%s,%s,%s) RETURNING id""",
            (pc_id, warehouse_id, inv_date, total, total_rub)
        )
        inv_id = cur.fetchone()[0]

        for beer_id, qty, price in items:
            price_rub = (price * rate).quantize(Decimal("0.01"))
            cur.execute(
                "INSERT INTO invoice_item(invoice_id, beer_id, quantity, price_usd, price_rub) VALUES(%s,%s,%s,%s,%s)",
                (inv_id, beer_id, qty, price, price_rub)
            )
            # Обновляем остатки на складе
            cur.execute(
                """INSERT INTO warehouse_stock(warehouse_id, beer_id, quantity)
                   VALUES(%s,%s,%s)
                   ON CONFLICT(warehouse_id, beer_id) DO UPDATE
                   SET quantity = warehouse_stock.quantity + EXCLUDED.quantity""",
                (warehouse_id, beer_id, qty)
            )

        cur.execute("UPDATE purchase_contract SET is_completed=TRUE WHERE id=%s", (pc_id,))
        created += 1
    return created


def insert_delivery_contracts(cur, n, venue_ids, beer_ids, sales_mgr_id, accountant_id,
                               warehouse_ids) -> int:
    created = 0
    for _ in range(n):
        venue_id     = random.choice(venue_ids)
        start_date   = rnd_date(2024, 2025)
        end_date     = start_date + timedelta(days=random.randint(30, 180))

        cur.execute(
            """INSERT INTO delivery_contract(venue_id, manager_id, start_date, end_date)
               VALUES(%s,%s,%s,%s) RETURNING id""",
            (venue_id, sales_mgr_id, start_date, end_date)
        )
        dc_id = cur.fetchone()[0]

        # Выбрать 2–3 вида пива
        items_beer = random.sample(beer_ids, k=min(random.randint(2, 3), len(beer_ids)))
        total_rub  = Decimal("0")
        items = []
        for beer_id in items_beer:
            cur.execute("SELECT wholesale_price_rub FROM beer WHERE id=%s", (beer_id,))
            row = cur.fetchone()
            price = row[0] if row and row[0] else Decimal("300.00")
            qty   = random.randint(50, 500)
            cur.execute(
                "INSERT INTO delivery_contract_item(contract_id, beer_id, quantity, price_rub) VALUES(%s,%s,%s,%s)",
                (dc_id, beer_id, qty, price)
            )
            items.append((beer_id, qty, price))
            total_rub += qty * price

        # План поставок
        cur.execute(
            "INSERT INTO delivery_plan(contract_id) VALUES(%s) RETURNING id",
            (dc_id,)
        )
        plan_id = cur.fetchone()[0]

        plan_item_ids = []
        for beer_id, qty, price in items:
            plan_date = start_date + timedelta(days=random.randint(5, 20))
            cur.execute(
                "INSERT INTO delivery_plan_item(plan_id, beer_id, quantity, planned_date) VALUES(%s,%s,%s,%s) RETURNING id",
                (plan_id, beer_id, qty, plan_date)
            )
            plan_item_ids.append(cur.fetchone()[0])

        # Входящий платёж (100% предоплата)
        pay_date = start_date - timedelta(days=random.randint(1, 7))
        cur.execute(
            """INSERT INTO incoming_payment(contract_id, accountant_id, account_num, amount, payment_date)
               VALUES(%s,%s,%s,%s,%s) RETURNING id""",
            (dc_id, accountant_id, f"40702810{random.randint(10**12, 10**13 - 1):013d}",
             total_rub, pay_date)
        )
        ip_id = cur.fetchone()[0]

        # Привязка платежа ко всем строкам плана
        for pi_id in plan_item_ids:
            cur.execute(
                "INSERT INTO incoming_payment_item(payment_id, plan_item_id) VALUES(%s,%s)",
                (ip_id, pi_id)
            )
        cur.execute("UPDATE delivery_contract SET is_paid=TRUE WHERE id=%s", (dc_id,))

        # Документы передачи
        warehouse_id = random.choice(warehouse_ids)
        for i, (pi_id, (beer_id, qty, price)) in enumerate(zip(plan_item_ids, items)):
            t_date = start_date + timedelta(days=random.randint(10, 30))
            cur.execute(
                """INSERT INTO transfer_document
                   (contract_id, plan_item_id, warehouse_id, sales_manager_id, transfer_date)
                   VALUES(%s,%s,%s,%s,%s) RETURNING id""",
                (dc_id, pi_id, warehouse_id, sales_mgr_id, t_date)
            )
            td_id = cur.fetchone()[0]
            cur.execute(
                "INSERT INTO transfer_document_item(document_id, beer_id, quantity, actual_price) VALUES(%s,%s,%s,%s)",
                (td_id, beer_id, qty, price)
            )
            # Уменьшаем остаток на складе
            cur.execute(
                """UPDATE warehouse_stock SET quantity = GREATEST(0, quantity - %s)
                   WHERE warehouse_id=%s AND beer_id=%s""",
                (qty, warehouse_id, beer_id)
            )
            cur.execute("UPDATE delivery_plan_item SET is_completed=TRUE WHERE id=%s", (pi_id,))

        cur.execute("UPDATE delivery_plan    SET is_completed=TRUE WHERE id=%s", (plan_id,))
        cur.execute("UPDATE delivery_contract SET is_completed=TRUE WHERE id=%s", (dc_id,))
        created += 1
    return created


# ---------------------------------------------------------------

def main():
    args = parse_args()

    print(f"Подключение к {args.user}@{args.host}:{args.port}/{args.db}...")
    try:
        conn = get_connection(args)
    except Exception as e:
        print(f"Ошибка подключения: {e}")
        sys.exit(1)

    conn.autocommit = False
    cur = conn.cursor()
    cur.execute("SET search_path TO beer_import")

    try:
        # Текущие seed-данные
        cur.execute("SELECT id FROM country")
        country_ids = [r[0] for r in cur.fetchall()]
        cur.execute("SELECT id FROM beer_style")
        style_ids = [r[0] for r in cur.fetchall()]
        cur.execute("SELECT id FROM employee WHERE passport_number='4510 234567'")
        row = cur.fetchone()
        purchase_mgr_id = row[0] if row else 2
        cur.execute("SELECT id FROM employee WHERE passport_number='4510 345678'")
        row = cur.fetchone()
        sales_mgr_id = row[0] if row else 3
        cur.execute("SELECT id FROM employee WHERE passport_number='4510 456789'")
        row = cur.fetchone()
        accountant_id = row[0] if row else 4

        if args.clean:
            clean_test_data(cur)
            conn.commit()
            print("Очистка завершена.")
            return

        clean_test_data(cur)
        print()

        # 1. Адреса
        print(f"Вставка адресов...")
        addr_ids = insert_addresses(cur, args.breweries + args.warehouses + args.venues + 5)
        conn.commit()

        # 2. Пивоварни
        print(f"Вставка пивоварен ({args.breweries})...")
        brewery_ids = insert_breweries(cur, args.breweries, country_ids, addr_ids[:args.breweries])
        conn.commit()

        # 3. Пиво
        print(f"Вставка пива ({args.beers})...")
        all_brewery_ids = list(range(1, SEED_BREWERIES + 1)) + brewery_ids
        beer_ids = insert_beers(cur, args.beers, all_brewery_ids, style_ids)
        conn.commit()

        # 4. Склады
        print(f"Вставка складов ({args.warehouses})...")
        wh_ids = insert_warehouses(cur, args.warehouses, addr_ids)
        conn.commit()
        all_wh_ids = list(range(1, SEED_WAREHOUSES + 1)) + wh_ids

        # 5. Заведения
        print(f"Вставка заведений ({args.venues})...")
        venue_ids = insert_venues(cur, args.venues, addr_ids)
        conn.commit()
        all_venue_ids = list(range(1, SEED_VENUES + 1)) + venue_ids

        # 6. Договоры закупок
        print(f"Вставка договоров закупок ({args.pc})...")
        all_beer_ids = list(range(1, SEED_BEERS + 1)) + beer_ids
        n = insert_purchase_contracts(
            cur, args.pc, all_brewery_ids, all_beer_ids,
            purchase_mgr_id, accountant_id, all_wh_ids
        )
        conn.commit()
        print(f"  Создано договоров закупок: {n}")

        # 7. Договоры поставок
        print(f"Вставка договоров поставок ({args.dc})...")
        n = insert_delivery_contracts(
            cur, args.dc, all_venue_ids, all_beer_ids,
            sales_mgr_id, accountant_id, all_wh_ids
        )
        conn.commit()
        print(f"  Создано договоров поставок: {n}")

        # Итог
        print()
        print("=" * 50)
        print("Статистика после генерации:")
        for tbl in [
            "address", "brewery", "beer", "warehouse", "venue",
            "purchase_contract", "invoice", "delivery_contract",
            "incoming_payment", "transfer_document"
        ]:
            cur.execute(f"SELECT COUNT(*) FROM beer_import.{tbl}")
            cnt = cur.fetchone()[0]
            print(f"  {tbl:<30} {cnt:>6} строк")

    except Exception as e:
        conn.rollback()
        print(f"\nОШИБКА: {e}")
        import traceback; traceback.print_exc()
        sys.exit(1)
    finally:
        cur.close()
        conn.close()

    print("\nГенерация завершена успешно!")


if __name__ == "__main__":
    main()
