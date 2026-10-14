-- Check if you have the DB on your machine 
DROP DATABASE IF EXISTS shop;
-- Creates a DB called shop if it doesnt exist
CREATE DATABASE IF NOT EXISTS shop;

-- Creates table customer
CREATE TABLE customers (
    customer_id CHAR(36) PRIMARY KEY DEFAULT(UUID()) ,
    name VARCHAR(90) NOT NULL,
    email VARCHAR(90) UNIQUE NOT NULL,
    country VARCHAR(25)

);

-- Creates table products
CREATE TABLE products(
    product_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(90),
    description VARCHAR(100),
    stock_count INT DEFAULT(0)
    price_per_unit DECIMAL(4,2),
    in_inventory BOOLEAN DEFAULT(TRUE),
    
);