/*
WARNING: the snapshot below is copied from orders AS IT IS RIGHT NOW.
Run this file only on healthy data. If the table is already damaged (for example
this file was run twice), re-seed first: run 01_schema.sql, then 02_seed.sql.
Otherwise the snapshot is bad and the recovery check will report "nothing to recover".
*/

USE shop;

-- Take the last known good copy of the data 
DROP TABLE IF EXISTS orders_copy;
CREATE  TABLE orders_copy LIKE orders;
INSERT INTO orders_copy SELECT * FROM orders;

-- Flush the binary log: starting new log file so the disaster sit alone
FLUSH BINARY LOGS;
SHOW MASTER STATUS; -- StartPos note this number down and the file being currently written to
SELECT NOW();

/*
This is mainly the disaster part of it and update happened where all the rows are affected:
A case where the orders were delivered at a certain point in time would also have constraints:

WHERE order_id = 42
WHERE customer_id = 7 AND status = 'delivered'
WHERE status = 'pending' AND ordered_at < '2026-01-01'
*/
UPDATE orders
SET status = 'delivered'; -- Intended WHERE clause

-- Check what position was last written after commmit of changes
-- Note the start pos of the GDIT and the last pos of the final commit check README for or example
SHOW MASTER STATUS;

-- Showing that all the rows were changed status to 'delivered'
SELECT status, COUNT(*) FROM orders GROUP BY status;

-- To inspect the log file with the disaster
-- SHOW BINLOG EVENTS IN '<new bib log file>'
