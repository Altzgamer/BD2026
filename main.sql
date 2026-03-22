SET client_encoding = 'UTF8';
CREATE SCHEMA IF NOT EXISTS beer_import;
SET search_path TO beer_import;

CREATE TYPE purchase_type_enum AS ENUM (
    'initiative',   -- закупка по собственной инициативе
    'order',        -- закупка по заказу
    'stock_balance' -- в случае заполнения подходящего склада
);

CREATE TYPE venue_type_enum AS ENUM (
    'bar',
    'pub',
    'brasserie',
    'club',
    'shop'
);

-- E17 Страна
CREATE TABLE country (
    id   SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE
);

-- E16 Справочник адресов
CREATE TABLE address (
    id        SERIAL PRIMARY KEY,
    city      VARCHAR(200) NOT NULL,
    street    VARCHAR(300),
    latitude  NUMERIC(9,6),
    longitude NUMERIC(9,6)
);

-- E15 Сорт пива
CREATE TABLE beer_style (
    id   SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE
);

-- E13 Должность
CREATE TABLE position_dir (
    id   SERIAL PRIMARY KEY,
    code VARCHAR(50)  NOT NULL UNIQUE,
    name VARCHAR(200) NOT NULL UNIQUE
);

-- E12 Сотрудник
CREATE TABLE employee (
    id              SERIAL PRIMARY KEY,
    position_id     INTEGER      NOT NULL,
    full_name       VARCHAR(300) NOT NULL,
    phone           VARCHAR(30),
    passport_number VARCHAR(50)  UNIQUE,
    hire_date       DATE         NOT NULL DEFAULT CURRENT_DATE, -- а как увольнять?
    dismiss_date    DATE,
    is_active       BOOLEAN      NOT NULL DEFAULT TRUE,

    CONSTRAINT chk_dismiss_after_hire 
        CHECK (dismiss_date IS NULL OR dismiss_date >= hire_date),

    CONSTRAINT fk_employee_position 
        FOREIGN KEY (position_id) 
        REFERENCES position_dir(id)
);

-- E2 Пивоварня
CREATE TABLE brewery (
    id           SERIAL PRIMARY KEY,
    name         VARCHAR(300) NOT NULL,
    country_id   INTEGER      NOT NULL,
    address_id   INTEGER,
    founded_year INTEGER      CHECK (founded_year <= EXTRACT(YEAR FROM CURRENT_DATE)),

    CONSTRAINT fk_brewery_country 
        FOREIGN KEY (country_id) 
        REFERENCES country(id),

    CONSTRAINT fk_brewery_address 
        FOREIGN KEY (address_id) 
        REFERENCES address(id)
);

-- E1 Пиво
CREATE TABLE beer (
    id                    SERIAL PRIMARY KEY,
    brewery_id            INTEGER      NOT NULL,
    style_id              INTEGER      NOT NULL,
    name                  VARCHAR(300) NOT NULL,
    alcohol_pct           NUMERIC(4,1) NOT NULL CHECK (alcohol_pct >= 0 AND alcohol_pct <= 100),
    color                 VARCHAR(50),
    density               NUMERIC(6,3),
    drinkability          NUMERIC(3,1) CHECK (drinkability >= 0 AND drinkability <= 10),
    rating                NUMERIC(3,1) CHECK (rating >= 0 AND rating <= 10),
    volume_l              NUMERIC(5,3) CHECK (volume_l > 0),
    container             VARCHAR(100),
    last_price_usd        NUMERIC(12,2) CHECK (last_price_usd >= 0),
    last_price_rub        NUMERIC(14,2) CHECK (last_price_rub >= 0),
    wholesale_price_rub   NUMERIC(14,2) CHECK (wholesale_price_rub >= 0),
    retail_price_rub      NUMERIC(14,2) CHECK (retail_price_rub >= 0),
    description           TEXT,

    CONSTRAINT fk_beer_brewery 
        FOREIGN KEY (brewery_id) 
        REFERENCES brewery(id),

    CONSTRAINT fk_beer_style 
        FOREIGN KEY (style_id) 
        REFERENCES beer_style(id)
);

-- E7 Склад
CREATE TABLE warehouse (
    id           SERIAL PRIMARY KEY,
    code         VARCHAR(50)  NOT NULL UNIQUE,
    address_id   INTEGER,
    capacity     NUMERIC(12,2) NOT NULL CHECK (capacity > 0),
    phone        VARCHAR(30),
    manager_name VARCHAR(300),
    contact_info TEXT,

    CONSTRAINT fk_warehouse_address 
        FOREIGN KEY (address_id) 
        REFERENCES address(id)
);

-- E7_1 Остатки пива на складе
CREATE TABLE warehouse_stock (
    warehouse_id INTEGER NOT NULL,
    beer_id      INTEGER NOT NULL,
    quantity     NUMERIC(12,3) NOT NULL DEFAULT 0 CHECK (quantity >= 0),

    PRIMARY KEY (warehouse_id, beer_id),

    CONSTRAINT fk_warehouse_stock_warehouse 
        FOREIGN KEY (warehouse_id) 
        REFERENCES warehouse(id),

    CONSTRAINT fk_warehouse_stock_beer 
        FOREIGN KEY (beer_id) 
        REFERENCES beer(id)
);

-- E8 Заведение
CREATE TABLE venue (
    id     SERIAL PRIMARY KEY,
    name   VARCHAR(300) NOT NULL,
    address_id INTEGER,
    phone  VARCHAR(30),
    type   venue_type_enum,
    status VARCHAR(50),

    CONSTRAINT fk_venue_address 
        FOREIGN KEY (address_id) 
        REFERENCES address(id)
);

-- E3 Договор о закупках
CREATE TABLE purchase_contract (
    id               SERIAL PRIMARY KEY,
    brewery_id       INTEGER NOT NULL,
    manager_id       INTEGER NOT NULL,
    contract_date    DATE NOT NULL DEFAULT CURRENT_DATE,
    total_amount_usd NUMERIC(14,2) NOT NULL CHECK (total_amount_usd > 0),
    exchange_rate    NUMERIC(10,4) NOT NULL CHECK (exchange_rate > 0),
    is_paid          BOOLEAN NOT NULL DEFAULT FALSE,
    is_completed     BOOLEAN NOT NULL DEFAULT FALSE,

    CONSTRAINT fk_purchase_contract_brewery 
        FOREIGN KEY (brewery_id) 
        REFERENCES brewery(id),

    CONSTRAINT fk_purchase_contract_manager 
        FOREIGN KEY (manager_id) 
        REFERENCES employee(id)
);

-- E3_1 Позиции договора закупки
CREATE TABLE purchase_contract_item (
    contract_id INTEGER NOT NULL,
    beer_id     INTEGER NOT NULL,
    quantity    NUMERIC(12,3) NOT NULL CHECK (quantity > 0),
    price_usd   NUMERIC(12,2) NOT NULL CHECK (price_usd > 0),

    PRIMARY KEY (contract_id, beer_id),

    CONSTRAINT fk_pci_contract 
        FOREIGN KEY (contract_id) 
        REFERENCES purchase_contract(id) ON DELETE CASCADE,

    CONSTRAINT fk_pci_beer 
        FOREIGN KEY (beer_id) 
        REFERENCES beer(id)
);

-- E4 Пункт плана оплат закупки
CREATE TABLE payment_plan_item (
    id          SERIAL PRIMARY KEY,
    contract_id INTEGER NOT NULL,
    due_date    DATE NOT NULL,
    amount_usd  NUMERIC(12,2) NOT NULL CHECK (amount_usd > 0),

    CONSTRAINT fk_ppi_contract 
        FOREIGN KEY (contract_id) 
        REFERENCES purchase_contract(id) ON DELETE CASCADE
);

-- E5 Исходящий платёж
CREATE TABLE outgoing_payment (
    id                   SERIAL PRIMARY KEY,
    payment_plan_item_id INTEGER NOT NULL,
    accountant_id        INTEGER NOT NULL,
    payment_date         DATE NOT NULL,
    amount_usd           NUMERIC(12,2) NOT NULL CHECK (amount_usd > 0),
    exchange_rate        NUMERIC(10,4) NOT NULL CHECK (exchange_rate > 0),
    purchase_type        purchase_type_enum NOT NULL,

    CONSTRAINT fk_op_payment_plan_item 
        FOREIGN KEY (payment_plan_item_id) 
        REFERENCES payment_plan_item(id),

    CONSTRAINT fk_op_accountant 
        FOREIGN KEY (accountant_id) 
        REFERENCES employee(id)
);

-- E6 Накладная
CREATE TABLE invoice (
    id          SERIAL PRIMARY KEY,
    contract_id INTEGER NOT NULL,
    warehouse_id INTEGER NOT NULL,
    invoice_date DATE NOT NULL DEFAULT CURRENT_DATE,
    total_usd   NUMERIC(14,2) CHECK (total_usd >= 0),
    total_rub   NUMERIC(16,2) CHECK (total_rub >= 0),

    CONSTRAINT fk_invoice_contract 
        FOREIGN KEY (contract_id) 
        REFERENCES purchase_contract(id),

    CONSTRAINT fk_invoice_warehouse 
        FOREIGN KEY (warehouse_id) 
        REFERENCES warehouse(id)
);

-- E6_1 Позиция накладной
CREATE TABLE invoice_item (
    invoice_id INTEGER NOT NULL,
    beer_id    INTEGER NOT NULL,
    quantity   NUMERIC(12,3) NOT NULL CHECK (quantity > 0),
    price_usd  NUMERIC(12,2) NOT NULL CHECK (price_usd >= 0),
    price_rub  NUMERIC(14,2) NOT NULL CHECK (price_rub >= 0),

    PRIMARY KEY (invoice_id, beer_id),

    CONSTRAINT fk_ii_invoice 
        FOREIGN KEY (invoice_id) 
        REFERENCES invoice(id) ON DELETE CASCADE,

    CONSTRAINT fk_ii_beer 
        FOREIGN KEY (beer_id) 
        REFERENCES beer(id)
);

-- E9 Договор поставок
CREATE TABLE delivery_contract (
    id           SERIAL PRIMARY KEY,
    venue_id     INTEGER NOT NULL,
    manager_id   INTEGER NOT NULL,
    start_date   DATE NOT NULL,
    end_date     DATE,
    is_paid      BOOLEAN NOT NULL DEFAULT FALSE,
    is_completed BOOLEAN NOT NULL DEFAULT FALSE,

    CONSTRAINT chk_dc_dates 
        CHECK (end_date IS NULL OR end_date >= start_date),

    CONSTRAINT fk_delivery_contract_venue 
        FOREIGN KEY (venue_id) 
        REFERENCES venue(id),

    CONSTRAINT fk_delivery_contract_manager 
        FOREIGN KEY (manager_id) 
        REFERENCES employee(id)
);

-- E9_1 Позиции договора поставок
CREATE TABLE delivery_contract_item (
    contract_id INTEGER NOT NULL,
    beer_id     INTEGER NOT NULL,
    quantity    NUMERIC(12,3) NOT NULL CHECK (quantity > 0),
    price_rub   NUMERIC(14,2) NOT NULL CHECK (price_rub > 0),

    PRIMARY KEY (contract_id, beer_id),

    CONSTRAINT fk_dci_contract 
        FOREIGN KEY (contract_id) 
        REFERENCES delivery_contract(id) ON DELETE CASCADE,

    CONSTRAINT fk_dci_beer 
        FOREIGN KEY (beer_id) 
        REFERENCES beer(id)
);

-- E10 Заголовок плана поставок
CREATE TABLE delivery_plan (
    id          SERIAL PRIMARY KEY,
    contract_id INTEGER NOT NULL,
    is_completed BOOLEAN NOT NULL DEFAULT FALSE,

    CONSTRAINT fk_delivery_plan_contract 
        FOREIGN KEY (contract_id) 
        REFERENCES delivery_contract(id) ON DELETE CASCADE
);

-- E10_1 Пункт плана поставок
CREATE TABLE delivery_plan_item (
    id           SERIAL PRIMARY KEY,
    plan_id      INTEGER NOT NULL,
    beer_id      INTEGER NOT NULL,
    quantity     NUMERIC(12,3) NOT NULL CHECK (quantity > 0),
    planned_date DATE,
    is_completed BOOLEAN NOT NULL DEFAULT FALSE,

    CONSTRAINT fk_dpi_plan 
        FOREIGN KEY (plan_id) 
        REFERENCES delivery_plan(id) ON DELETE CASCADE,

    CONSTRAINT fk_dpi_beer 
        FOREIGN KEY (beer_id) 
        REFERENCES beer(id)
);

-- E11 Входящий платёж
CREATE TABLE incoming_payment (
    id            SERIAL PRIMARY KEY,
    contract_id   INTEGER NOT NULL,
    accountant_id INTEGER NOT NULL,
    account_num   VARCHAR(100),
    amount        NUMERIC(14,2) NOT NULL CHECK (amount > 0),
    payment_date  DATE NOT NULL DEFAULT CURRENT_DATE,

    CONSTRAINT fk_incoming_payment_contract 
        FOREIGN KEY (contract_id) 
        REFERENCES delivery_contract(id),

    CONSTRAINT fk_incoming_payment_accountant 
        FOREIGN KEY (accountant_id) 
        REFERENCES employee(id)
);

-- E11_1 Пункт входящего платежа
CREATE TABLE incoming_payment_item (
    payment_id   INTEGER NOT NULL,
    plan_item_id INTEGER NOT NULL,

    PRIMARY KEY (payment_id, plan_item_id),

    CONSTRAINT fk_ipi_payment 
        FOREIGN KEY (payment_id) 
        REFERENCES incoming_payment(id) ON DELETE CASCADE,

    CONSTRAINT fk_ipi_plan_item 
        FOREIGN KEY (plan_item_id) 
        REFERENCES delivery_plan_item(id)
);

-- E14 Документ передачи
CREATE TABLE transfer_document (
    id               SERIAL PRIMARY KEY,
    contract_id      INTEGER NOT NULL,
    plan_item_id     INTEGER NOT NULL,
    warehouse_id     INTEGER NOT NULL,
    sales_manager_id INTEGER NOT NULL,
    transfer_date    DATE NOT NULL DEFAULT CURRENT_DATE,

    CONSTRAINT fk_td_contract 
        FOREIGN KEY (contract_id) 
        REFERENCES delivery_contract(id),

    CONSTRAINT fk_td_plan_item 
        FOREIGN KEY (plan_item_id) 
        REFERENCES delivery_plan_item(id),

    CONSTRAINT fk_td_warehouse 
        FOREIGN KEY (warehouse_id) 
        REFERENCES warehouse(id),

    CONSTRAINT fk_td_sales_manager 
        FOREIGN KEY (sales_manager_id) 
        REFERENCES employee(id)
);

-- E14_1 Позиции документа передачи
CREATE TABLE transfer_document_item (
    document_id  INTEGER NOT NULL,
    beer_id      INTEGER NOT NULL,
    quantity     NUMERIC(12,3) NOT NULL CHECK (quantity > 0),
    actual_price NUMERIC(14,2) NOT NULL CHECK (actual_price >= 0),

    PRIMARY KEY (document_id, beer_id),

    CONSTRAINT fk_tdi_document 
        FOREIGN KEY (document_id) 
        REFERENCES transfer_document(id) ON DELETE CASCADE,

    CONSTRAINT fk_tdi_beer 
        FOREIGN KEY (beer_id) 
        REFERENCES beer(id)
);
