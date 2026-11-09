-- Using the database shop created from the schema
USE shop;

-- Making some dummy data for all the tables right now
-- For customers 1000 users

INSERT INTO customers (name, email, country)
SELECT CONCAT('customer_',  seq),
       CONCAT('person', seq, '@example.com'),
       ELT(FLOOR(1 + RAND() * 6), 'Zimbabwe', 'Senegal', 'India', 'Ghana', 'USA', 'Peuto Rico')
FROM seq_1_to_1000;

-- Inserting 100 products
INSERT INTO products (name, stock_count, price_per_unit)
SELECT CONCAT(ELT(FLOOR(1 + RAND() * 4), "Mug#", "Shirt#", "Jacket#", "Flask#"), seq),
        FLOOR(RAND() * 50),
        ROUND( 5 + RAND() * 195, 2)
FROM seq_1_to_100;


-- INSERTING SOME ORDERS
INSERT INTO orders (customer_id, ordered_at, status)
SELECT FLOOR ( 1 + RAND() * 1000 ),
        NOW() - INTERVAL FLOOR(RAND() * 365 * 86400 ) SECOND AS ordered_at,
        -- Skewing the status data (README for more info)
        ELT( FLOOR( 1 + RAND() * 10),
                'delivered','delivered','delivered','delivered',
                'shipped','shipped','shipped',
                'pending', 'pending',
                'cancelled'
        )
FROM seq_1_to_20000;

-- Verification
SELECT COUNT(*) FROM orders;
SELECT status, COUNT(*) FROM orders GROUP BY status;
SELECT MIN(customer_id), MAX(customer_id) FROM orders;


INSERT INTO ordered_items (order_id, product_id, quantity, unit_price_at_purchase)
SELECT t.order_id,
       t.pid,
       FLOOR(1 + RAND() * 5),
       p.price_per_unit
FROM (
    SELECT order_id, FLOOR(1 + RAND() * 100) AS pid
    FROM orders
) AS t
JOIN products p ON p.product_id = t.pid;

SELECT COUNT(*) FROM ordered_items;      -- should be 20000 (same as orders)
SELECT status, COUNT(*) FROM orders GROUP BY status;   -- your baseline
SHOW VARIABLES LIKE 'binlog_format';     -- ROW
SHOW VARIABLES LIKE 'binlog_row_image';  -- FULL
SHOW BINARY LOGS;                        -- note the file name(s)

