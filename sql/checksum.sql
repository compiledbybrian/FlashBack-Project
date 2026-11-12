/*
This file is a check to show that the other tables (customer,products, ordered_items) 
were not tampered with during the disastor

Run before the disaster.sql
Run after the disaster.sql

Should produce the same result showing data was never changed in these tables.

*/

USE shop;
CHECKSUM TABLE customers, products, ordered_items;