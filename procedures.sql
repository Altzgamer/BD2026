SET client_encoding = 'UTF8';
SET search_path TO beer_import;
\setenv PAGER ''

DROP TYPE IF EXISTS zapis CASCADE;
CREATE TYPE zapis AS (  
    beer_id INTEGER,
    price_usd NUMERIC,
    quantity NUMERIC
);

\echo '--- 1 ---'
CREATE OR REPLACE PROCEDURE proc1(
    IN p_contract_id INT,
    IN p_warehouse_id INT,
    IN p_items zapis[]
)
LANGUAGE plpgsql

AS $$
DECLARE
    v_item          zapis;
    v_ordered_qty   NUMERIC;
    v_contract_price NUMERIC;
    v_received_qty  NUMERIC;
    v_exchange_rate NUMERIC;
    v_invoice_id    INT;
    v_total_usd     NUMERIC := 0;
    v_total_rub     NUMERIC := 0;
    v_item_rub      NUMERIC;
    v_beer_name     VARCHAR;
BEGIN
    
    SELECT exchange_rate INTO v_exchange_rate -- курс из договора закупки
    FROM purchase_contract
    WHERE id = p_contract_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Dogovor % ne nayden', p_contract_id;
    END IF;

    -- Создаем накладную
    INSERT INTO invoice (contract_id, warehouse_id, invoice_date, total_usd, total_rub)
    VALUES (p_contract_id, p_warehouse_id, CURRENT_DATE, 0, 0)
    RETURNING id INTO v_invoice_id;

    -- Создаем invoive item
    FOREACH v_item IN ARRAY p_items
    LOOP
        -- Проверка наличия товара в договоре
        SELECT quantity, price_usd INTO v_ordered_qty, v_contract_price
        FROM purchase_contract_item
        WHERE contract_id = p_contract_id AND beer_id = v_item.beer_id;
        
        IF NOT FOUND THEN
            SELECT name INTO v_beer_name FROM beer WHERE id = v_item.beer_id;
            RAISE EXCEPTION 'Pivo % (id %) ne vxodit v dogovor %', COALESCE(v_beer_name, 'Unknown'), v_item.beer_id, p_contract_id;
        END IF;

        -- Проверка цены
        IF v_item.price_usd != v_contract_price THEN
            RAISE EXCEPTION 'Price dlya id % nekorrektno: nyzno %, polucheno %', 
                v_item.beer_id, v_contract_price, v_item.price_usd;
        END IF;

        -- Проверка лимита 
        SELECT COALESCE(SUM(ii.quantity), 0) INTO v_received_qty
        FROM invoice_item ii
        JOIN invoice i ON i.id = ii.invoice_id
        WHERE i.contract_id = p_contract_id AND ii.beer_id = v_item.beer_id;

        IF v_received_qty + v_item.quantity > v_ordered_qty THEN
            RAISE EXCEPTION 'Previshenie kolichestva dlya tovara id %: zakazano %, uzhe polucheno %, popitka dobavit %',    
                                                            v_item.beer_id, v_ordered_qty, v_received_qty, v_item.quantity;
        END IF;

        v_item_rub := ROUND(v_item.price_usd * v_exchange_rate, 2);

        INSERT INTO invoice_item (invoice_id, beer_id, quantity, price_usd, price_rub)
        VALUES (v_invoice_id, v_item.beer_id, v_item.quantity, v_item.price_usd, v_item_rub);

        v_total_usd := v_total_usd + (v_item.quantity * v_item.price_usd);
        v_total_rub := v_total_rub + (v_item.quantity * v_item_rub);
    END LOOP;

    UPDATE invoice 
    SET total_usd = v_total_usd, total_rub = v_total_rub
    WHERE id = v_invoice_id;

    RAISE NOTICE 'Nakladnaya sozdana. Summa: % $, % rub', v_total_usd, v_total_rub;
END;
$$;


\echo '--- 2 ---'
CREATE OR REPLACE PROCEDURE proc2(
    IN p_contract_id INT,
    IN p_plan_items_count INT,
    IN p_interval_days INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_start_date DATE;
    v_plan_id INT;
    v_item RECORD;
    v_base_qty NUMERIC;
    v_last_qty NUMERIC;
    v_i INT;
    v_planned_date DATE;
BEGIN
    IF p_plan_items_count <= 0 THEN
        RAISE EXCEPTION 'Kolichestvo punktov plana <= 0';
    END IF;

    SELECT start_date INTO v_start_date
    FROM delivery_contract
    WHERE id = p_contract_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Dogovor postavki % ne nayden', p_contract_id;
    END IF;

    IF EXISTS (SELECT 1 FROM delivery_plan WHERE contract_id = p_contract_id) THEN
        RAISE EXCEPTION 'Plan dlya dogovora % yze est', p_contract_id;
    END IF;

    INSERT INTO delivery_plan (contract_id, is_completed)
    VALUES (p_contract_id, FALSE)
    RETURNING id INTO v_plan_id;

    FOR v_item IN (SELECT beer_id, quantity FROM delivery_contract_item WHERE contract_id = p_contract_id) 
    LOOP

        v_base_qty := TRUNC(v_item.quantity / p_plan_items_count);
        
        IF v_base_qty <= 0 AND p_plan_items_count > 1 THEN
            RAISE EXCEPTION 'Kolichestvo tovara id % nevernoe', v_item.beer_id;
        END IF;

        v_last_qty := v_item.quantity - (v_base_qty * (p_plan_items_count - 1));

        FOR v_i IN 1..p_plan_items_count LOOP
            v_planned_date := v_start_date + (v_i * p_interval_days);

            IF v_i = p_plan_items_count THEN
                INSERT INTO delivery_plan_item (plan_id, beer_id, quantity, planned_date, is_completed)
                VALUES (v_plan_id, v_item.beer_id, v_last_qty, v_planned_date, FALSE);
            ELSE
                INSERT INTO delivery_plan_item (plan_id, beer_id, quantity, planned_date, is_completed)
                VALUES (v_plan_id, v_item.beer_id, v_base_qty, v_planned_date, FALSE);
            END IF;
        END LOOP;
        
        RAISE NOTICE 'Raspredeleno pivo id %: base_qty %, last_qty % (p_plan_items_count %)', 
            v_item.beer_id, v_base_qty, v_last_qty, p_plan_items_count;
    END LOOP;
END;
$$;


DO $$
DECLARE
    v_contract1_id INT;
    v_contract9_id INT;
    v_invoice_items zapis[];
    v_invoice_items_neg_price zapis[];
    v_invoice_items_neg_qty zapis[];
BEGIN

    RAISE NOTICE '--- TEST 1 ---';
    
    INSERT INTO purchase_contract (brewery_id, manager_id, contract_date, total_amount_usd, exchange_rate)
    VALUES (1, 1, CURRENT_DATE, 500.0, 95.0) 
    RETURNING id INTO v_contract1_id;

    INSERT INTO purchase_contract_item (contract_id, beer_id, quantity, price_usd) 
    VALUES (v_contract1_id, 1, 100, 5.0);

    v_invoice_items := ARRAY[(1, 5.0, 50.0)]::zapis[];
    
    RAISE NOTICE '  -Positive: korrekniy priem tovara';
    CALL proc1(v_contract1_id, 1, v_invoice_items);
    RAISE NOTICE 'Positive test 1 done';

    -- неверная цена
    v_invoice_items_neg_price := ARRAY[(1, 4.0, 10.0)]::zapis[];

    RAISE NOTICE '  -Negative: price';
    BEGIN
        CALL proc1(v_contract1_id, 1, v_invoice_items_neg_price);
        RAISE EXCEPTION 'Negative test failed';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Negative test 1 done. %', SQLERRM;
    END;


    -- Уже приняли 50, заказано 100 добавляем еще 60.
    v_invoice_items_neg_qty := ARRAY[(1, 5.0, 60.0)]::zapis[];

    RAISE NOTICE '  --Negative: previshenie kolichestva';
    BEGIN
        CALL proc1(v_contract1_id, 1, v_invoice_items_neg_qty);
        RAISE EXCEPTION 'Negative test failed';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Negative test 2 done. %', SQLERRM;
    END;


    RAISE NOTICE '--- TEST 2---';

    INSERT INTO delivery_contract (venue_id, manager_id, start_date, is_paid, is_completed)
    VALUES (1, 1, CURRENT_DATE, FALSE, FALSE)
    RETURNING id INTO v_contract9_id;

    -- Позицию не делится ровно на 3 пункта 
    INSERT INTO delivery_contract_item (contract_id, beer_id, quantity, price_rub)
    VALUES (v_contract9_id, 2, 10.0, 150.0);

    RAISE NOTICE ' --Positive: sozdanie plana (10 tovarov na 3 punkta)';
    CALL proc2(v_contract9_id, 3, 7); -- 3 пункта, 7 дней
    RAISE NOTICE 'Positive test done';

    RAISE NOTICE ' --Negative: povtornoe sozdanie planna dlya dogovora';
    BEGIN
        CALL proc2(v_contract9_id, 3, 7);
        RAISE EXCEPTION 'Negative test failed';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Negative test done. %', SQLERRM;
    END;

END $$;
