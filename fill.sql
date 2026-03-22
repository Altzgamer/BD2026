\set ON_ERROR_STOP on
SET client_encoding = 'UTF8';
SET search_path TO beer_import;

INSERT INTO country (name) VALUES
    ('Германия'),
    ('Бельгия'),
    ('Ирландия'),
    ('Чехия'),
    ('Великобритания'),
    ('США'),
    ('Нидерланды');


INSERT INTO beer_style (name) VALUES
    ('Лагер'),
    ('Эль'),
    ('Портер'),
    ('Стаут'),
    ('Пшеничный'),
    ('IPA'),
    ('Бельгийский эль'),
    ('Пилснер');


INSERT INTO position_dir (code, name) VALUES
    ('director',          'Руководитель'),
    ('purchase_manager',  'Менеджер по закупкам'),
    ('sales_manager',     'Менеджер по продажам'),
    ('accountant',        'Бухгалтер');


INSERT INTO employee (position_id, full_name, phone, passport_number, hire_date) VALUES
    ((SELECT id FROM position_dir WHERE code='director'),         'Иванов Алексей Петрович',     '+7-495-100-01-01', '4510 123456', '2018-03-01'),
    ((SELECT id FROM position_dir WHERE code='purchase_manager'), 'Смирнова Ольга Николаевна',   '+7-495-100-01-02', '4510 234567', '2019-06-15'),
    ((SELECT id FROM position_dir WHERE code='sales_manager'),    'Козлов Дмитрий Сергеевич',    '+7-495-100-01-03', '4510 345678', '2020-01-10'),
    ((SELECT id FROM position_dir WHERE code='accountant'),       'Новикова Ирина Владимировна',  '+7-495-100-01-04', '4510 456789', '2019-02-20');


INSERT INTO address (city, street, latitude, longitude) VALUES
    ('Мюнхен',      'Nymphenburger Str. 4',   48.135125, 11.581981),   -- 1 адрес пивоварни
    ('Брюссель',    'Rue du Lombard 17',       50.850346, 4.351722),    -- 2
    ('Дублин',      'James St, Dublin 8',      53.341808, -6.287016),   -- 3
    ('Прага',       'Smíchov, Na Příkopě 22',  50.082397, 14.420000),   -- 4
    ('Лондон',      'Chiswick Lane South',     51.490940, -0.261160),   -- 5
    ('Москва',      'ул. Складочная, 1',       55.803000, 37.548000),   -- 6 (склад 1)
    ('Санкт-Петербург', 'пр. Обуховской обороны, 74', 59.900000, 30.437000), -- 7 (склад 2)
    ('Екатеринбург','ул. Восточная, 56',       56.838011, 60.597474),   -- 8 (склад 3)
    ('Москва',      'Ленинградский просп., 12',55.790000, 37.540000),   -- 9 (заведение 1)
    ('Москва',      'ул. Пятницкая, 27',       55.730000, 37.622000),   -- 10 (заведение 2)
    ('Санкт-Петербург', 'Невский проспект, 45', 59.934280, 30.318740);  -- 11 (заведение 3)

INSERT INTO brewery (name, country_id, address_id, founded_year) VALUES
    ('Paulaner Brauerei',
     (SELECT id FROM country WHERE name='Германия'), 1, 1634),
    ('Brasserie Cantillon',
     (SELECT id FROM country WHERE name='Бельгия'),  2, 1900),
    ('Guinness Brewery',
     (SELECT id FROM country WHERE name='Ирландия'), 3, 1759),
    ('Pilsner Urquell',
     (SELECT id FROM country WHERE name='Чехия'),    4, 1842),
    ('Fuller, Smith & Turner',
     (SELECT id FROM country WHERE name='Великобритания'), 5, 1845);

INSERT INTO beer
    (brewery_id, style_id, name, alcohol_pct, color, density, drinkability, rating,
     volume_l, container, last_price_usd, last_price_rub, wholesale_price_rub, retail_price_rub, description)
VALUES
    
    (1, 5, 'Paulaner Weißbier', 5.5, 'Светлое', 12.5, 8.5, 8.2,
     0.5, 'Стекло', 2.10, 189.00, 245.70, 280.00,
     'Классическое баварское пшеничное пиво'),
    
    (2, 7, 'Cantillon Gueuze', 5.0, 'Янтарное', 12.0, 6.0, 9.0,
     0.375, 'Стекло', 5.50, 495.00, 643.50, 750.00,
     'Традиционный бельгийский кислый эль самопроизвольного брожения'),
    
    (3, 4, 'Guinness Draught', 4.2, 'Тёмное', 10.8, 9.0, 8.8,
     0.5, 'Банка', 2.80, 252.00, 327.60, 380.00,
     'Знаменитый ирландский стаут с кремовой пеной'),
    
    (4, 8, 'Pilsner Urquell', 4.4, 'Светлое', 11.0, 8.0, 8.6,
     0.5, 'Стекло', 2.20, 198.00, 257.40, 300.00,
     'Оригинальный чешский пилснер, созданный в 1842 году'),
    
    (5, 2, 'Fuller''s London Pride', 4.7, 'Медное', 11.5, 7.5, 8.4,
     0.5, 'Стекло', 2.50, 225.00, 292.50, 340.00,
     'Классический английский биттер');

INSERT INTO warehouse (code, address_id, capacity, phone, manager_name) VALUES
    ('WH-MSK-01', 6, 50000.0, '+7-495-200-01-01', 'Петров А.В.'),
    ('WH-SPB-01', 7, 30000.0, '+7-812-200-01-02', 'Ефимова Т.К.'),
    ('WH-EKB-01', 8, 20000.0, '+7-343-200-01-03', 'Захаров В.Н.');


INSERT INTO warehouse_stock (warehouse_id, beer_id, quantity) VALUES
    (1, 1, 500),  (1, 2, 200),  (1, 3, 1000), (1, 4, 300), (1, 5, 400),
    (2, 1, 200),  (2, 3, 500),  (2, 4, 150),
    (3, 2, 100),  (3, 5, 250);


INSERT INTO venue (name, address_id, phone, type, status) VALUES
    ('The Hopyard Bar',   9,  '+7-495-300-01-01', 'bar',   'active'),
    ('Брассерия Пивной двор', 10, '+7-495-300-01-02', 'brasserie', 'active'),
    ('Невский Паб',      11, '+7-812-300-01-03', 'pub',   'active');

INSERT INTO purchase_contract
    (brewery_id, manager_id, contract_date, total_amount_usd, exchange_rate, is_paid, is_completed)
VALUES
    ((SELECT id FROM brewery WHERE name='Paulaner Brauerei'),
     (SELECT id FROM employee WHERE passport_number='4510 234567'),
     '2025-12-01', 5250.00, 90.00, FALSE, FALSE);

INSERT INTO purchase_contract_item (contract_id, beer_id, quantity, price_usd)
VALUES
    (1, 1, 1000, 2.10),
    (1, 4,  500, 2.20);  

INSERT INTO payment_plan_item (contract_id, due_date, amount_usd) VALUES
    (1, '2025-12-15', 2625.00),  -- 50%
    (1, '2026-01-15', 2625.00);  -- 50%

INSERT INTO outgoing_payment
    (payment_plan_item_id, accountant_id, payment_date, amount_usd, exchange_rate, purchase_type)
VALUES
    (1,
     (SELECT id FROM employee WHERE passport_number='4510 456789'),
     '2025-12-14', 2625.00, 90.00, 'initiative');

INSERT INTO outgoing_payment
    (payment_plan_item_id, accountant_id, payment_date, amount_usd, exchange_rate, purchase_type)
VALUES
    (2,
     (SELECT id FROM employee WHERE passport_number='4510 456789'),
     '2026-01-14', 2625.00, 90.00, 'initiative');

UPDATE purchase_contract SET is_paid = TRUE WHERE id = 1;

INSERT INTO invoice (contract_id, warehouse_id, invoice_date, total_usd, total_rub)
VALUES (1, 1, '2026-01-20', 5250.00, 472500.00);

INSERT INTO invoice_item (invoice_id, beer_id, quantity, price_usd, price_rub) VALUES
    (1, 1, 1000, 2.10, 189.00),
    (1, 4,  500, 2.20, 198.00);

UPDATE purchase_contract SET is_completed = TRUE WHERE id = 1;

INSERT INTO delivery_contract
    (venue_id, manager_id, start_date, end_date, is_paid, is_completed)
VALUES
    ((SELECT id FROM venue WHERE name='The Hopyard Bar'),
     (SELECT id FROM employee WHERE passport_number='4510 345678'),
     '2026-02-01', '2026-02-28', FALSE, FALSE);

INSERT INTO delivery_contract_item (contract_id, beer_id, quantity, price_rub) VALUES
    (1, 1, 200, 245.70),  
    (1, 3, 300, 327.60);  

INSERT INTO delivery_plan (contract_id, is_completed) VALUES (1, FALSE);

INSERT INTO delivery_plan_item (plan_id, beer_id, quantity, planned_date, is_completed) VALUES
    (1, 1, 200, '2026-02-10', FALSE),
    (1, 3, 300, '2026-02-15', FALSE);

INSERT INTO incoming_payment
    (contract_id, accountant_id, account_num, amount, payment_date)
VALUES
    (1,
     (SELECT id FROM employee WHERE passport_number='4510 456789'),
     'АО Банк 40702810001234567890',
     147420.00,
     '2026-02-05');

INSERT INTO incoming_payment_item (payment_id, plan_item_id) VALUES
    (1, 1),
    (1, 2);

UPDATE delivery_contract SET is_paid = TRUE WHERE id = 1;

INSERT INTO transfer_document
    (contract_id, plan_item_id, warehouse_id, sales_manager_id, transfer_date)
VALUES
    (1, 1, 1,
     (SELECT id FROM employee WHERE passport_number='4510 345678'),
     '2026-02-10');

INSERT INTO transfer_document_item (document_id, beer_id, quantity, actual_price) VALUES
    (1, 1, 200, 245.70);

UPDATE delivery_plan_item SET is_completed = TRUE WHERE id = 1;

INSERT INTO transfer_document
    (contract_id, plan_item_id, warehouse_id, sales_manager_id, transfer_date)
VALUES
    (1, 2, 1,
     (SELECT id FROM employee WHERE passport_number='4510 345678'),
     '2026-02-15');

INSERT INTO transfer_document_item (document_id, beer_id, quantity, actual_price) VALUES
    (2, 3, 300, 327.60);

UPDATE delivery_plan_item SET is_completed = TRUE WHERE id = 2;
UPDATE delivery_plan    SET is_completed = TRUE WHERE id = 1;
UPDATE delivery_contract SET is_completed = TRUE WHERE id = 1;