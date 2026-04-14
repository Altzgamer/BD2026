SET client_encoding = 'UTF8';
SET search_path TO beer_import;
\setenv PAGER ''


\echo '---1---'
-- При оформлении накладной, суммарное количество полученных от поставщика товаров
-- по всем накладным не может превышать количество заказанного товара с учетом типа товара.

CREATE OR REPLACE FUNCTION trg_check_invoice_item_qty()
RETURNS TRIGGER AS $$
DECLARE
    v_contract_id   INTEGER;
    v_ordered_qty   NUMERIC;
    v_received_qty  NUMERIC;
    v_beer_name     VARCHAR;
BEGIN
    SELECT contract_id INTO v_contract_id -- получаем contract id из накладной
    FROM invoice
    WHERE id = NEW.invoice_id;

    SELECT quantity INTO v_ordered_qty -- получаем заказанное количество данного пива в договоре
    FROM purchase_contract_item
    WHERE contract_id = v_contract_id
      AND beer_id = NEW.beer_id;

    IF v_ordered_qty IS NULL THEN -- если пиво не найдено в договоре ошибка
        SELECT name INTO v_beer_name FROM beer WHERE id = NEW.beer_id;
        RAISE EXCEPTION 'Pivo % (id %) ne vxodit v dogovor %', v_beer_name, NEW.beer_id, v_contract_id;
    END IF;

    SELECT COALESCE(SUM(ii.quantity), 0) INTO v_received_qty -- считаем уже полученное количество 
    FROM invoice_item ii
    JOIN invoice i ON i.id = ii.invoice_id
    WHERE i.contract_id = v_contract_id AND ii.beer_id = NEW.beer_id;

    IF v_received_qty + NEW.quantity > v_ordered_qty THEN -- проверяем лимит
        SELECT name INTO v_beer_name FROM beer WHERE id = NEW.beer_id;
        RAISE EXCEPTION
            'Previshenie limita dlya % (id %), zakazano=%, uzhe polucheno %,  dobavlayem %',
            v_beer_name, NEW.beer_id, v_ordered_qty, v_received_qty, NEW.quantity;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_invoice_item_qty_check ON invoice_item;
CREATE TRIGGER trg_invoice_item_qty_check
    BEFORE INSERT ON invoice_item
    FOR EACH ROW
    EXECUTE FUNCTION trg_check_invoice_item_qty();


\echo '---2---'
-- При формировании исходящего платежного документа по некоторому договору, 
-- проверяется сумма по всем пунктам плана для данного договора о закупках. 
-- Если сумма платежей равна или превысила, то в пунктах плана платежей проставляется отметка об их оплате.
-- При попытке добавить в уже оплаченный договор еще один платежный документ выдается ошибка 

CREATE OR REPLACE FUNCTION trg_check_outgoing_payment()
RETURNS TRIGGER AS $$
DECLARE
    v_contract_id       INTEGER;
    v_contract_total    NUMERIC;
    v_is_paid           BOOLEAN;
    v_total_paid        NUMERIC;
BEGIN
    SELECT ppi.contract_id INTO v_contract_id -- получаем contract id через пункт плана оплат
    FROM payment_plan_item ppi
    WHERE ppi.id = NEW.payment_plan_item_id;

    SELECT total_amount_usd, is_paid -- оплачен ли уже договор
    INTO v_contract_total, v_is_paid
    FROM purchase_contract
    WHERE id = v_contract_id;

    IF v_is_paid THEN
        RAISE EXCEPTION
            'Dogovor % yze oplachen',
            v_contract_id;
    END IF;

    SELECT COALESCE(SUM(op.amount_usd), 0) INTO v_total_paid -- считаем сумму всех платежей по договору включая текущий
    FROM outgoing_payment op
    JOIN payment_plan_item ppi ON ppi.id = op.payment_plan_item_id
    WHERE ppi.contract_id = v_contract_id;

    v_total_paid := v_total_paid + NEW.amount_usd;

    IF v_total_paid >= v_contract_total THEN -- если сумма >= стоимости договора - то оплаченный
        UPDATE purchase_contract
        SET is_paid = TRUE
        WHERE id = v_contract_id;

        RAISE NOTICE 'Dogovor % oplachen (oplacheno %, summa %)',
            v_contract_id, v_total_paid, v_contract_total;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_outgoing_payment_check ON outgoing_payment;
CREATE TRIGGER trg_outgoing_payment_check
    BEFORE INSERT ON outgoing_payment
    FOR EACH ROW
    EXECUTE FUNCTION trg_check_outgoing_payment();



DO $$
DECLARE
    v_contract_id   INTEGER;
    v_plan_item1    INTEGER;
    v_invoice1      INTEGER;
    v_invoice2      INTEGER;
BEGIN
    RAISE NOTICE '--- trigger 1 ---';

    -- 1. Создаем договор
    INSERT INTO purchase_contract
        (brewery_id, manager_id, contract_date, total_amount_usd, exchange_rate)
    VALUES
        (2, 2, '2026-03-01', 4900.00, 92.00)
    RETURNING id INTO v_contract_id;

    INSERT INTO purchase_contract_item (contract_id, beer_id, quantity, price_usd) VALUES (v_contract_id, 2, 100, 5.50);  

    INSERT INTO payment_plan_item (contract_id, due_date, amount_usd) VALUES (v_contract_id, '2026-03-15', 4900.00) RETURNING id INTO v_plan_item1;


    INSERT INTO invoice (contract_id, warehouse_id, invoice_date, total_usd, total_rub) VALUES (v_contract_id, 1, '2026-03-10', 0, 0)
    RETURNING id INTO v_invoice1;

    INSERT INTO invoice (contract_id, warehouse_id, invoice_date, total_usd, total_rub) VALUES (v_contract_id, 2, '2026-03-11', 0, 0)
    RETURNING id INTO v_invoice2;


    INSERT INTO invoice_item (invoice_id, beer_id, quantity, price_usd, price_rub)
    VALUES 
        (v_invoice1, 2, 50, 5.50, 506.00),
        (v_invoice2, 2, 50, 5.50, 506.00);
    RAISE NOTICE 'Positive test done';

    BEGIN
        INSERT INTO invoice_item (invoice_id, beer_id, quantity, price_usd, price_rub)
        VALUES (v_invoice1, 2, 1, 5.50, 506.00); -- добавляем сверх лимита
        RAISE EXCEPTION 'Negative test failed';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Negative test done. Error: %', SQLERRM;
    END;

    RAISE NOTICE '--- trigger 2 ---';

    INSERT INTO outgoing_payment (payment_plan_item_id, accountant_id, payment_date, amount_usd, exchange_rate, purchase_type)
    VALUES 
        (v_plan_item1, 4, '2026-03-14', 2450.00, 92.00, 'initiative'),
        (v_plan_item1, 4, '2026-03-15', 2450.00, 92.00, 'initiative'); -- разрешенный множественный платёж
    
    IF NOT EXISTS (SELECT 1 FROM purchase_contract WHERE id = v_contract_id AND is_paid) THEN
        RAISE EXCEPTION 'Positive test failed';
    ELSE
        RAISE NOTICE 'Positive test done';
    END IF;

    BEGIN
        INSERT INTO outgoing_payment (payment_plan_item_id, accountant_id, payment_date, amount_usd, exchange_rate, purchase_type)
        VALUES (v_plan_item1, 4, '2026-04-20', 100.00, 92.00, 'initiative'); -- попытка добавить платёж в оплаченный договор
        RAISE EXCEPTION 'Negative test failed';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Negative test done. Error: %', SQLERRM;
    END;

END $$;
