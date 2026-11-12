#  A project for area 9, "FLASHBACK: undo without a restore" for the [MariaDB student database projects, 2026-09](https://mariadb.org/bachelor_hackathon_2026-09/).

## 1. What this project is about ?
- MariaDB Flashback : undo a bad change using the binary log without restoring a backup
- Using a staged disaster e.g an `UPDATE` with no ``WHERE`` clause , `DELETE` without `FROM` clause . (A deplyed branch of code that corrupts the table basically)
- Recover to a point in time of the DB, verify the result, and time it against the full restore.
  
## 2. Setting up the environment
- This project heavily relies on the bin log files.
- Making sure that they are activated for any devices running the project is almost the whole project.
- Logging should be on , in the row format and with full image.
  
### 2.1 Windows setup

**1. Edit the config file.** Open `my.ini` in MariaDB's data folder (e.g. `C:\Program Files\MariaDB 12.3\data\my.ini`). Saving it may need an editor running as administrator. Under `[mysqld]`, add:

```ini
log_bin = mariadb-bin
binlog_format = ROW
binlog_row_image = FULL
```

- `log_bin` turns the binary log on.
- `binlog_format = ROW` logs the actual row changes. `STATEMENT` only stores SQL text, which has no before-values to restore.
- `binlog_row_image = FULL` stores the complete before and after version of each changed row, which FLASHBACK needs to build the undo statements.

A copy of these lines is in `config/my.ini.example`.

**2. Restart the MariaDB service** (the config is only read at startup). In an administrator terminal:

```
net stop MariaDB
net start MariaDB
```

Use the real service name if yours differs.

**3. Verify in the MariaDB terminal client.** Don't use an editor extension for this, because some hide `SHOW` output.

```sql
SHOW VARIABLES LIKE 'log_bin';           -- ON
SHOW VARIABLES LIKE 'binlog_format';     -- ROW
SHOW VARIABLES LIKE 'binlog_row_image';  -- FULL
SHOW BINARY LOGS;                        -- lists mariadb-bin.00000N files
```

If `SHOW BINARY LOGS;` says binary logging is not in use, check that the lines are under `[mysqld]`, that you edited the right `my.ini`, and that the service was restarted.

**4. Check the FLASHBACK tool exists:**

```
mariadb-binlog --help | findstr flashback
```

A line mentioning `--flashback` should appear. If the command isn't found, add MariaDB's `bin` folder to PATH and open a new terminal.

**NB:** a new log file starts on every restart, so many small files pile up.


## 3. Schema Design
- Our scenario is a small online shop, inspired by real Shopify order handling.
  
| Table | Purpose | Key |
| ---- | ---- | ---- |
| `customers`| people who order the products. | `customer_id` INT AUTO_INCREMENT |
| `products` | what store is selling | `product_id` INT AUTO_INCREMENT |
| `orders` | one row per order | `order_id` INT AUTO_INCREMENT |
| `ordered_items` | one row per product in an order | composite ( `order_id`, `product_id`) |

### Decisions And Reasoning:
- **INT AUTO_INCREMENT KEYS** : Considered UUIDs but dropped them because they are bigger, harder to read in binlog file and are not what the project tests.
- **4 tables, not 3** : An order can contain several products, so `ordered_items` is the link table (many-to-many).
- `status` is the disaster target. Setting every order to one value is an obvious, realistic corruption.

## 5. Seeding Data
- Goal: enough realistic rows that the damage and the recovery are visible and the timings mean something.

How we did it:
- MariaDB's `SEQUENCE` engine: `seq_1_to_N` is a virtual table of numbers; ``INSERT ... SELECT ... FROM seq_1_to_N`` generates N rows at once.
- **Uniqueness vs randomness**. Anything that must be unique (emails, product names) is built from ``seq``. Anything that may repeat (price, stock, country) uses ``RAND()``. Random values in a UNIQUE column would eventually collide and fail the insert.