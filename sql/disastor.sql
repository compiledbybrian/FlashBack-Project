USE shop;

-- Take the last known good copy
DROP TABLE IF EXISTS orders_copy;
CREATE  TABLE orders_copy LIKE orders;
INSERT INTO orders_copy SELECT * FROM orders;

-- Flush the binary logs
FLUSH BINARY LOGS;
SHOW MASTER STATUS;
SELECT NOW();

-- SHOW BINLOG EVENTS IN 'mariadb-bin.000040';

/*
This is mainly the disaster part of it and update happened where all the rows are affected:
A case where the orders were delivered at a certain point in time would also have constraints:

WHERE order_id = 42
WHERE customer_id = 7 AND status = 'delivered'
WHERE status = 'pending' AND ordered_at < '2026-01-01'
*/
UPDATE orders
SET status = 'delivered';

-- Check what position was last written after commmit of changes
SHOW MASTER STATUS;

-- Showing that all the rows were changed status to 'delivered'
SELECT status, COUNT(*) FROM orders GROUP BY status;

-- Shows the logging events that happened in the current log file
SHOW BINLOG EVENTS IN 'mariadb-bin.000040';
