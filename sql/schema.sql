-- Creates a DB called shop if it doesnt exist
CREATE DATABASE IF NOT EXISTS shop;
USE shop;

-- Creates table customer
CREATE TABLE customers (
    customer_id INT AUTO_INCREMENT PRIMARY KEY,
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
    in_inventory BOOLEAN DEFAULT(TRUE) NOT NULL
    
);

-- Create orders table
CREATE TABLE orders(
    order_id INT AUTO_INCREMENT PRIMARY KEY,
    customer_id INT NOT NULL,
    ordered_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status ENUM('pending', 'shipped', 'delivered', 'cancelled') NOT NULL DEFAULT('pending'),   
    CONSTRAINT fk_orders_customers
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)

);

-- Create ordered_items
CREATE TABLE ordered_items(
    order_id INT NOT NULL,
    product_id INT NOT NULL,
    quantity INT NOT NULL,
    unit_price_at_purchase DECIMAL(6,2) NOT NULL,
    PRIMARY KEY ( order_id, product_id),
    FOREIGN KEY (product_id) REFERENCES products(product_id),
    FOREIGN KEY (order_id) REFERENCES orders(order_id)
   
);

-- Check if the DB is working properly, should show your shop db and its tables
/*
SHOW DATABASES;
USE shop;
SHOW TABLES;
*/

-- Testing the DB for expected behaviour

