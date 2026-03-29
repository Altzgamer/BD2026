SET client_encoding = 'UTF8';
SET search_path TO beer_import;
\setenv PAGER ''

\echo '---1---'

SELECT
    b.name AS "Название пива",
    b.id AS "ID пива",

    ROUND(COALESCE(s.sales_rub, 0), 2) AS "Сумма продаж, руб.", -- ROUND (,2) два знака после запятой
    
    COALESCE(s.qty_sold, 0) AS "Кол-во продаж", 
    COALESCE(st.total_stock, 0) AS "Остаток",

    CASE
        WHEN s.qty_sold IS NULL OR s.qty_sold = 0 THEN 'не определено' -- продаж не было
        WHEN COALESCE(st.total_stock, 0) = 0 THEN '0' -- уже закончился
        ELSE ROUND( 
            COALESCE(st.total_stock, 0) /  -- остаток
            ( -- делим на среднюю продажу в день
                s.qty_sold::numeric / ((CURRENT_DATE - '2026-01-01'::date) + 1)) -- дата отсчета периода
            )::text || ' дн.'
    END AS "Прогноз продаж"
FROM beer b

LEFT JOIN ( -- продажи за всё время
    SELECT
        tdi.beer_id,
        SUM(tdi.quantity * tdi.actual_price) AS sales_rub, -- количество * цена
        SUM(tdi.quantity)                    AS qty_sold  -- общее количество проданного пива
    FROM transfer_document_item tdi
    JOIN transfer_document td ON td.id = tdi.document_id
    WHERE td.transfer_date >= '2026-01-01'::date
    GROUP BY tdi.beer_id
) s ON s.beer_id = b.id

LEFT JOIN (
    SELECT beer_id, SUM(quantity) AS total_stock -- суммарный остаток по всем складам
    FROM warehouse_stock
    GROUP BY beer_id
) st ON st.beer_id = b.id

ORDER BY COALESCE(s.sales_rub, 0) DESC;

\echo '---2---'

SELECT
    b.name AS "Название пива",
    b.id AS "ID пива",
    
    COALESCE(s.qty_sold, 0) AS "Кол-во проданного пива",
    
    ROUND(COALESCE(c.avg_unit_cost_rub, 0), 2)  AS "Себестоимость ед, руб.",
    
    ROUND(COALESCE(s.qty_sold, 0) * COALESCE(c.avg_unit_cost_rub, 0), 2)  AS "Суммарная себестоимость, руб.",
    
    ROUND(COALESCE(s.total_sales_rub, 0), 2) AS "Сумма продаж, руб.",
    
    ROUND(COALESCE(s.total_sales_rub, 0) - COALESCE(c.avg_unit_cost_rub, 0), 2) 
    AS "Валовая прибыль, руб.", -- разница между суммой продаж и себестоимостью ???суммарная себестоимость мб???
    
    ROUND(COALESCE(s.avg_sell_price, 0), 2) AS "Средняя цена продажи, руб.",
    
    CASE 
        WHEN COALESCE(s.qty_sold, 0) * COALESCE(c.avg_unit_cost_rub, 0) = 0 THEN NULL 
        ELSE ROUND(
                (COALESCE(s.total_sales_rub, 0) - COALESCE(s.qty_sold, 0) * COALESCE(c.avg_unit_cost_rub, 0)) 
                / 
                COALESCE(c.avg_unit_cost_rub, 0) * 100, 
                2
             ) 
    END AS "Эффективность продаж, %", -- (валовая прибыль / себестоимость?) * 100 %
    
    CASE 
        WHEN COALESCE(s.total_sales_rub, 0) = 0 THEN NULL 
        ELSE ROUND(
                (COALESCE(s.total_sales_rub, 0) - 
                 COALESCE(s.qty_sold, 0) * COALESCE(c.avg_unit_cost_rub, 0)) /  -- валовая прибль делить на
                COALESCE(s.total_sales_rub, 0) * 100,  -- сумма продаж * 100
                2
             ) 
    END AS "Рентабельность продаж, %" -- (валовая прибыль / сумма продаж) * 100 %.
FROM beer b

LEFT JOIN (
    SELECT
        tdi.beer_id,
        SUM(tdi.quantity) AS qty_sold, -- общее колво проданного пива
        SUM(tdi.quantity * tdi.actual_price) AS total_sales_rub, -- общая сумма продаж
        AVG(tdi.actual_price) AS avg_sell_price -- средняя цена продажи
    FROM transfer_document_item tdi
    GROUP BY tdi.beer_id
) s ON s.beer_id = b.id

LEFT JOIN (
    SELECT
        ii.beer_id,
        -- среднее значение закупочной цены с учетом количества единиц в поставках с учетом курса ?на тот момент?
        -- вроде во варианте фиксировалли только доллар
        SUM(ii.quantity * ii.price_rub) / SUM(ii.quantity) AS avg_unit_cost_rub 
    FROM invoice_item ii
    GROUP BY ii.beer_id
) c ON c.beer_id = b.id
ORDER BY COALESCE(s.total_sales_rub, 0) DESC;


\echo '---3---'

SELECT
    br.name AS "Наименование поставщика",

    -- есть ли просрочка
    CASE 
        WHEN SUM(
            CASE 
                WHEN ppi.due_date < CURRENT_DATE -- дата платежа раньше
                     AND op.id IS NULL 
                THEN ppi.amount_usd * pc.exchange_rate -- сумма
                ELSE 0
            END
        ) > 0 
        THEN 'Да'
        ELSE 'Нет'
    END AS "Наличие просроченных платежей",

    
    ROUND(
        SUM(
            CASE 
                WHEN ppi.due_date < CURRENT_DATE 
                     AND op.id IS NULL 
                THEN ppi.amount_usd * pc.exchange_rate -- сумма просрочки
                ELSE 0
            END
        ),
        2
    ) AS "Сумма просроченных платежей, руб.",

    ROUND(SUM(CASE WHEN ppi.due_date = CURRENT_DATE -- pivot
                   AND op.id IS NULL 
              THEN ppi.amount_usd * pc.exchange_rate ELSE 0 END), 2)
        AS "29.03",

    ROUND(SUM(CASE WHEN ppi.due_date = CURRENT_DATE + 1 
                   AND op.id IS NULL 
              THEN ppi.amount_usd * pc.exchange_rate ELSE 0 END), 2)
        AS "30.03",

    ROUND(SUM(CASE WHEN ppi.due_date = CURRENT_DATE + 2 
                   AND op.id IS NULL 
              THEN ppi.amount_usd * pc.exchange_rate ELSE 0 END), 2)
        AS "31.03"


FROM brewery br
JOIN purchase_contract pc ON pc.brewery_id = br.id
JOIN payment_plan_item ppi ON ppi.contract_id = pc.id
LEFT JOIN outgoing_payment op ON op.payment_plan_item_id = ppi.id

GROUP BY br.name
ORDER BY br.name;

\echo '---4---'

WITH

    stock_total AS (
        SELECT beer_id, SUM(quantity) AS total_stock -- остатки по всем складам
        FROM warehouse_stock
        GROUP BY beer_id
    ),

    
    venue_count AS (
        SELECT
            dci.beer_id,
            COUNT(DISTINCT dc.venue_id) AS venues_count -- сколько заведений когда-либо покупали определенное пиво
        FROM delivery_contract_item dci
        JOIN delivery_contract dc ON dc.id = dci.contract_id
        GROUP BY dci.beer_id
    ),

    invoice_ranked AS (
        SELECT
            ii.beer_id,
            i.invoice_date,
            ii.price_usd,
            ROW_NUMBER() OVER (
                PARTITION BY ii.beer_id ORDER BY i.invoice_date ASC -- сортируем по дате от старой к новой поставке
                )  AS rn_asc,
            ROW_NUMBER() OVER (
                PARTITION BY ii.beer_id ORDER BY i.invoice_date DESC
                ) AS rn_desc
        FROM invoice_item ii
        JOIN invoice i ON i.id = ii.invoice_id -- пункт накладной с самой накладной
    ),

    first_invoice AS (
        SELECT beer_id, invoice_date AS first_date
        FROM invoice_ranked
        WHERE rn_asc = 1 -- самая первая поставка
    ),

    last_invoice AS (
        SELECT beer_id, invoice_date AS last_date, price_usd AS last_price_usd
        FROM invoice_ranked
        WHERE rn_desc = 1 -- последняя поставка
    )

SELECT
    b.name AS "Наименование пива",
    COALESCE(st.total_stock, 0) AS "Остатки",
    COALESCE(vc.venues_count, 0) AS "Число заведений",
    li.last_date AS "Дата последней поставки",
    fi.first_date AS "Дата первой поставки",
    li.last_price_usd AS "Цена посл. поставки, USD"
FROM beer b
LEFT JOIN stock_total st ON st.beer_id = b.id
LEFT JOIN venue_count vc ON vc.beer_id = b.id
LEFT JOIN first_invoice fi ON fi.beer_id = b.id
LEFT JOIN last_invoice li ON li.beer_id = b.id
ORDER BY b.name;


\echo '---5---'

WITH 
    sales_detail AS (
        SELECT
            dc.venue_id, -- заведение
            td.transfer_date, -- дата
            
            SUM(tdi.quantity * tdi.actual_price) AS day_sales_rub, -- сумма продаж
            
            SUM(tdi.quantity) AS day_qty -- проданные единицы за день
        FROM transfer_document_item tdi
        
        JOIN transfer_document td ON td.id = tdi.document_id
        JOIN delivery_contract dc ON dc.id = td.contract_id
        
        WHERE td.transfer_date >= '2026-01-01'::date
        GROUP BY dc.venue_id, td.transfer_date
    ),

    gap_flag AS (
        SELECT 
            venue_id,
            MAX(gap) > 90 AS has_long_gap -- флаг если хотя бы один перерыв дольше
        FROM ( -- считаем разницу между текущей и предыдущей датой продажи
            SELECT 
                venue_id,
                transfer_date - LAG(transfer_date) -- LAG берет предыдущую строку
                    OVER (PARTITION BY venue_id ORDER BY transfer_date) AS gap -- для каждого заведения сортируем по дате
            FROM sales_detail
        ) calcgap
        GROUP BY venue_id
    )

SELECT
    v.name AS "Название заведения",
    ROUND(SUM(sd.day_sales_rub), 2) AS "сумма продаж, руб.",
    SUM(sd.day_qty) AS "кол-во проданных единиц",
    
    COALESCE(CASE WHEN gf.has_long_gap THEN 'Да' 
                  ELSE 'Нет' 
             END, 'Нет') AS "Был перерыв?"
FROM venue v

JOIN sales_detail sd ON sd.venue_id = v.id
LEFT JOIN gap_flag gf ON gf.venue_id = v.id
GROUP BY v.id, v.name, gf.has_long_gap
ORDER BY SUM(sd.day_sales_rub) DESC;