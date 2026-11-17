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

**1. Prerequisites**
| Need | Why |
| --- | --- |
| Maria DB server 10.x  or newer | Project uses the `mariadb-binlog --flashback` which is specific to MariaDB |
| Windows Powershell | To run the scripts `recover.ps1` and `restore.ps1` (bash scripts still a work in progress) |



**2. Edit the config file.** Open `my.ini` in MariaDB's data folder (e.g. `C:\Program Files\MariaDB 12.3\data\my.ini`). Saving it may need an editor running as administrator. Under `[mysqld]`, add:

```ini
log_bin = mariadb-bin
binlog_format = ROW
binlog_row_image = FULL
```

- `log_bin` turns the binary log on.
- `binlog_format = ROW` logs the actual row changes. `STATEMENT` only stores SQL text, which has no before-values to restore.
- `binlog_row_image = FULL` stores the complete before and after version of each changed row, which FLASHBACK needs to build the undo statements.

A copy of these lines is in `config/my.ini.example`.

**3. Restart the MariaDB service** (the config is only read at startup). In an administrator terminal:

```
net stop MariaDB
net start MariaDB
```

Use the real service name if yours differs.

**4. Verify in the MariaDB terminal client.** Don't use an editor extension for this, because some hide `SHOW` output.

```sql
SHOW VARIABLES LIKE 'log_bin';           -- ON
SHOW VARIABLES LIKE 'binlog_format';     -- ROW
SHOW VARIABLES LIKE 'binlog_row_image';  -- FULL
SHOW BINARY LOGS;                        -- lists mariadb-bin.00000N files
```

If `SHOW BINARY LOGS;` says binary logging is not in use, check that the lines are under `[mysqld]`, that you edited the right `my.ini`, and that the service was restarted.




**5. Check the FLASHBACK tool exists:**

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
- Picking from a list using `ELT(n, 'a', 'b', ..)` for some of our dummy data.

| Table | Rows | Notes |
| --- | --- | --- |
| `customers` | 1000 | formatted as `customer_N`, unique emails using `seq` |
| `products` | 100 | numbered names, random prices from 5.00 -200.00 , random stock |
|`orders` | 20,000 | 	random customer `(FLOOR(1 + RAND() * 1000)`, `FLOOR` is required or values round to a nonexistent customer 1001), random timestamp in the past year, weighted status | 
| ` ordered_items`| 20,000 | one row per order avoids composite-key collisions; price copied from products via a `JOIN` so data stays coherent


**NB** : Seed scripts are not rerunnable. A second/ n run will double the rows. Reseed by running the schema first(which drops the tables). THEN run the seed  file.

### Baseline for our status's in our orders
- Run the command:
  
```
SELECT status, COUNT(*) FROM orders GROUP BY status;
```


![Baseline for order status distribution](pics/baseline%20skew%20for%20status.png)


## Disastor Scenario

![Funny database meme](pics/DB%20meme.jpg)

- Backstory: A deployment meant to change one order but the `WHERE` clause was forgotten. Intended statement is commented out in the file `sql/disastor.sql`
- Order of steps to reverse the damage:

**1.Backup DB**
- In a real world scenario you wouldn't know when to back up or it is done in regular intervals
- Backup the healthy version of the data because it is needed for the timing comaprison.

```
mariadb-dump --defaults-extra-file=config/recovery.example.cnf --single-transaction --result-file=shop_backup.sql shop

```
- Run the command (make sure your db account and password are in config/recovery.cnf).

**2. Flush the binary log file** 
- Start a new log file so that the bad `UPDATE` is the only content in it
- Record the start maker : `SHOW MASTER STATUS();` (file and postion)

![first mater show](pics/first%20mater%20show.png)

**3.Run the bad update**
- Run the bad update..
  
![result of disastor](pics/result%20of%20disastor.png)

- The bad update made every order's status `'delivered'`.
- Note thr end marker of the bin log file (field position).
  
### Other details
- Positions are the primary way to define a window/point in time we want to recover to.
- Unchanged rows are not logged (almost like a version history Git) so FLASHBACK never touches them.
- You can use sql/checksum.sql to verify this.
![Check sum after disaster](pics/Checksum%20after%20disaster.png)
- **Run sql/disastor in the terminal for better results**. We used an extension at first running the sql statements but started struggiling on commands like `SOURCE`.
```
SOURCE sql/disaster.sql;
```
- Remember your `WHERE` clauses next time :)



## 6. Recovery / Restore

- Command:
``` 
mariadb-binlog --flashback --start-position=<start> --stop-position=<stop> --database=shop --result-file=<out.sql> <logfile> 
```

- Writes a `.sql` file; applying it undoes the incident. Add `--verbose` for readable `###` pseudo-SQL (the file then gets very large: about 2.6 MB for 12,052 rows).
- The generated file is mostly base64 `BINLOG '...'` blocks.
- Output is one transaction (`START TRANSACTION` ... `COMMIT`), with the row reads in reverse order. Only the rows that actually changed are reversed.
- Verified in the `--verbose` output:  `# Number of rows: 12052`, each row reads `WHERE @4=3 SET @4=<original>` (column 4 is `status`, 3 is `delivered`), and the restored values split 6077 shipped / 4046 pending / 1929 cancelled, which adds up to 12,052 and matches the baseline.
- Applied from the terminal with `SOURCE <file>` (not from the editor).
- **The generated file contains `SET TIMESTAMP` statements**, which freeze `NOW()`for the rest of that session. A second `NOW(6)` after applying printed 18:17:08.000000, an old time. Use `SYSDATE(6)` (or an external stopwatch) for timing.
- Write output with `--result-file`, not shell `>` (PowerShell `>` re-encodes to UTF-16).
- Watch time zones: check `@@global.time_zone`, `@@session.time_zone`, `NOW()`; binlog time options use the server's local time.

**Script: scripts/recover.ps1** (written for the project; one run against real data was done).

- Parameters: `-LogFile`, `-StartPos`, `-StopPos` (required); `-Database`(default shop), `-Cnf` (default `config/recovery.cnf`), `-Inspect` (adds `--verbose`), `-Force`.
- Flow: check inputs and tools, count rows that differ from `orders_copy` (stop with "Nothing to recover" if 0), safety-check that the server's current log file and position equal the log name and stop position (so nothing was written after the incident; fails unless `-Force`), generate `out/flashback_<timestamp>.sql` , apply it, re-count the differences, print a summary with generate, apply and total seconds. Exit code is 1 if the result is not verified.
- Each run writes a new timestamped file in `out/` so earlier output is never overwritten ( `out/` is gitignored).
- Confirmed: run against already-recovered data it prints "Nothing to recover".

**Connection file:** `config/recovery.cnf`(an option file with file is gitignored; `[client]` , `user` , `password` ). The real `recovery.cnf.example` is committed. It is passed as `--defaults-extra-file` , which must be the first argument.


## 7. Verification (DONE, method)

Proof, not assumption, in three layers

1. **Row-by-row diff** of `orders` against the `orders_copy` screenshot (null-safe `<=>` ), plus any rowcount difference. The result must be 0. The scripts print this count before and after.
``` sql
SELECT (SELECT COUNT(*) FROM orders o JOIN orders_copy c ON c.order_id = o.order_id 
    WHERE NOT (o.customer_id <=> c.customer_id AND o.ordered_at <=> 
    c.ordered_at AND o.status <=> c.status)) 
    + ABS((SELECT COUNT(*) FROM orders) - (SELECT COUNT(*) FROM orders_copy))
```
2. **Status counts** ( `GROUP BY status` ) back to the baseline in section 5.
3. **`CHECKSUM TABLE`** (`sql/checksums.sql`) before the disaster and after recovery. `customers`, `products` and `ordered_items` must be identical (untouched by the incident), and `orders` must return to its "before" value.
- Limitation to state: the screenshot is made by the same drill, so layer 1 only proves something if the screenshot itself was healthy. The checksum comparison is the independent check.

## 8. Timing comparison 

- Two runs from the same damaged state: FLASHBACK (`recover.ps1`) vs full backup + restore (`restore.ps1 -DumpFile shop_backup.sql`). Write down these numbers for later comparison.
TODO :: Put recovery pictures @Tavonga-Mushohwe
- `restore.ps1` : refuses to run if there is nothing to repair (unless `-Force` ), restores with `SOURCE` under a stopwatch, re-verifies with the same mismatch query, prints a summary.
- A restore overwrites the **whole** database, so anything written after the dump is lost; FLASHBACK reverses only the one bad transaction. In this drill nothing was written in between, so the restore looks lossless; in real life it usually is not.
- Binary logging is on for both runs; both start from the same damaged state.
- Timing tool: stopwatch inside the scripts; never `NOW()` after applying a flashback file (see the `SET TIMESTAMP` gotcha in section 6).

## 9. Limits of FLASHBACK



- Row-based DML only ( `INSERT` , `UPDATE `, `DELETE` ); not DDL (dropped/altered tables).
- Needs the binlog config in section 3, and the log files for the window must still exist (not purged or rotated away).
- Unchanged rows are not in the log, so there is nothing to reverse for them.
- It reverses a window of the log: anything else that happened in the same window gets reversed too, so keep the window tight and check for other writers.
- Seeding and copying are logged as well, so the recovery window must start after them. 
- Cascaded foreign-key deletes: check whether they are logged as row events (we avoided `CASCADE` , section 4).
- Writes made by other sessions after the incident: what FLASHBACK does to them if the window is too wide.

