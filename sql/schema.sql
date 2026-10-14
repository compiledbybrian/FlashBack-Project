-- Check if you have the DB on your machine and deletes it to create a new one
DROP DATABASE IF EXISTS shop;
-- Creates a DB called shop if it doesnt exist
CREATE DATABASE IF NOT EXISTS shop;
USE shop;

-- Creates table customer
CREATE TABLE customers (
    customer_id INT AUTO_INCREMENT PRIMARY KEY ,
    name VARCHAR(90) NOT NULL,
    email VARCHAR(90) UNIQUE NOT NULL,
    country VARCHAR(50)

);

-- Creates table products
CREATE TABLE products(
    product_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(90) NOT NULL,
    description VARCHAR(250),
    stock_count INT DEFAULT(0) NOT NULL,
    price_per_unit DECIMAL(6,2) NOT NULL,
    in_inventory BOOLEAN DEFAULT(TRUE)
    
);