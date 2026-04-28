SET client_encoding = 'UTF8';
SET search_path TO beer_import;
\setenv PAGER ''

DROP INDEX IF EXISTS idx_td_transfer_date_id;
DROP INDEX IF EXISTS idx_td_recent_contract;
DROP INDEX IF EXISTS idx_tdi_document_beer_covering;
DROP INDEX IF EXISTS idx_ws_beer_quantity;
DROP INDEX IF EXISTS idx_dc_id_venue;


CREATE INDEX idx_td_transfer_date_id -- составной
ON transfer_document (transfer_date, id);

CREATE INDEX idx_td_recent_contract -- частичный
ON transfer_document (transfer_date, contract_id)
WHERE transfer_date >= '2026-01-01'::date;

CREATE INDEX idx_tdi_document_beer_covering -- покрывающий
ON transfer_document_item (document_id, beer_id)
INCLUDE (quantity, actual_price);

CREATE INDEX idx_ws_beer_quantity -- покрывающий
ON warehouse_stock (beer_id)
INCLUDE (quantity);

CREATE INDEX idx_dc_id_venue -- составной
ON delivery_contract (id, venue_id);

ANALYZE transfer_document;
ANALYZE transfer_document_item;
ANALYZE warehouse_stock;
ANALYZE delivery_contract;


\echo '---1---'


EXPLAIN (ANALYZE, BUFFERS)
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


\echo '---5---'


EXPLAIN (ANALYZE, BUFFERS)
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
