/* ==========================================================================
   COLLEGE SMART CANTEEN TOKEN SYSTEM  -  schema.sql
   Database : college_smart_canteen
   Engine   : MySQL 8.0.16 or newer (InnoDB)
   Run in   : SQLyog Community 64-bit (connected to your MySQL server)

   ORDER OF THIS SCRIPT
     1. Create and select the database
     2. Create tables
     3. Create views and stored procedures
     4. Insert the 15 token slots
     5. Optional demonstration records
     6. Demonstration queries
     7. Verification queries
     8. Safe cleanup / reset (demo data only)
   ========================================================================== */


/* ---------------------------------------------------------------------------
   1. CREATE AND SELECT THE DATABASE
   --------------------------------------------------------------------------- */
CREATE DATABASE IF NOT EXISTS college_smart_canteen
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE college_smart_canteen;


/* ---------------------------------------------------------------------------
   2. TABLES
   --------------------------------------------------------------------------- */

/* 2.1 customers: one row per person registered at the counter */
CREATE TABLE IF NOT EXISTS customers (
    customer_id   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    full_name     VARCHAR(100)    NOT NULL,
    roll_number   VARCHAR(30)     NULL,
    created_at    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (customer_id),
    KEY idx_customers_roll (roll_number),
    CONSTRAINT chk_customers_name CHECK (CHAR_LENGTH(TRIM(full_name)) >= 2)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


/* 2.2 canteen_orders: one row per order. order_id is the PERMANENT identity.
       token_number is the DISPLAYED token (1-15), NULL while the order waits.
       daily_serial is the order's running number for its business day.        */
CREATE TABLE IF NOT EXISTS canteen_orders (
    order_id       BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
    customer_id    BIGINT UNSIGNED  NOT NULL,
    business_date  DATE             NOT NULL,
    daily_serial   INT UNSIGNED     NOT NULL,
    token_number   TINYINT UNSIGNED NULL,
    status         ENUM('WAITING','ACTIVE','COMPLETED') NOT NULL,
    created_at     DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
    activated_at   DATETIME         NULL,
    completed_at   DATETIME         NULL,

    /* Safety net: the same token can never be ACTIVE twice.
       The column holds the token only while status = 'ACTIVE', otherwise NULL.
       A UNIQUE index allows many NULLs but no duplicate numbers.              */
    active_token_key TINYINT UNSIGNED
        GENERATED ALWAYS AS (IF(status = 'ACTIVE', token_number, NULL)) STORED,

    PRIMARY KEY (order_id),
    UNIQUE KEY uq_active_token (active_token_key),
    UNIQUE KEY uq_daily_serial (business_date, daily_serial),
    KEY idx_orders_status (status),
    KEY idx_orders_date_status (business_date, status),
    KEY idx_orders_customer (customer_id),
    KEY idx_orders_completed (completed_at),

    CONSTRAINT fk_orders_customer
        FOREIGN KEY (customer_id) REFERENCES customers (customer_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,

    CONSTRAINT chk_orders_token_range
        CHECK (token_number IS NULL OR token_number BETWEEN 1 AND 15),

    /* Each status must have a consistent combination of values */
    CONSTRAINT chk_orders_status_rules CHECK (
           (status = 'WAITING'   AND token_number IS NULL     AND completed_at IS NULL)
        OR (status = 'ACTIVE'    AND token_number IS NOT NULL AND completed_at IS NULL)
        OR (status = 'COMPLETED' AND token_number IS NOT NULL AND completed_at IS NOT NULL)
    )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


/* 2.3 waiting_list: queue record linked to the order of a waiting customer.
       queue_number grows 1,2,3... per business date and is never reused.
       The queue POSITION shown on screen is calculated (see v_waiting_queue). */
CREATE TABLE IF NOT EXISTS waiting_list (
    waiting_id     BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    order_id       BIGINT UNSIGNED NOT NULL,
    business_date  DATE            NOT NULL,
    queue_number   INT UNSIGNED    NOT NULL,
    status         ENUM('WAITING','PROMOTED') NOT NULL DEFAULT 'WAITING',
    joined_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    promoted_at    DATETIME        NULL,
    PRIMARY KEY (waiting_id),
    UNIQUE KEY uq_waiting_order (order_id),
    UNIQUE KEY uq_waiting_queue_no (business_date, queue_number),
    KEY idx_waiting_status (status, waiting_id),
    CONSTRAINT fk_waiting_order
        FOREIGN KEY (order_id) REFERENCES canteen_orders (order_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_waiting_promoted CHECK (
           (status = 'WAITING'  AND promoted_at IS NULL)
        OR (status = 'PROMOTED' AND promoted_at IS NOT NULL)
    )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


/* 2.4 token_slots: exactly 15 rows = the 15 physical active-token slots.
       current_order_id is NULL when the slot is free.
       UNIQUE(current_order_id) means one order can hold only one slot.
       Because only 15 rows exist, more than 15 ACTIVE orders is impossible.   */
CREATE TABLE IF NOT EXISTS token_slots (
    slot_number       TINYINT UNSIGNED NOT NULL,
    current_order_id  BIGINT UNSIGNED  NULL,
    occupied_since    DATETIME         NULL,
    PRIMARY KEY (slot_number),
    UNIQUE KEY uq_slot_order (current_order_id),
    CONSTRAINT fk_slot_order
        FOREIGN KEY (current_order_id) REFERENCES canteen_orders (order_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_slot_range CHECK (slot_number BETWEEN 1 AND 15)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


/* 2.5 daily_counters: one row per business day (this is the daily reset).
       Holds the day's running order number and peak active-token usage.       */
CREATE TABLE IF NOT EXISTS daily_counters (
    business_date  DATE             NOT NULL,
    last_serial    INT UNSIGNED     NOT NULL DEFAULT 0,
    peak_active    TINYINT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (business_date),
    CONSTRAINT chk_peak_active CHECK (peak_active <= 15)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


/* ---------------------------------------------------------------------------
   3A. VIEWS (used by the website pages and by the demo queries)
   --------------------------------------------------------------------------- */

CREATE OR REPLACE VIEW v_active_tokens AS
SELECT  o.token_number,
        o.order_id,
        o.daily_serial,
        c.full_name,
        c.roll_number,
        o.created_at  AS registered_at,
        o.activated_at,
        o.status
FROM    canteen_orders o
JOIN    customers c ON c.customer_id = o.customer_id
WHERE   o.status = 'ACTIVE'
ORDER BY o.token_number;


CREATE OR REPLACE VIEW v_waiting_queue AS
SELECT  ROW_NUMBER() OVER (ORDER BY w.waiting_id)  AS queue_position,
        w.queue_number,
        o.order_id,
        c.full_name,
        c.roll_number,
        w.joined_at,
        TIMESTAMPDIFF(MINUTE, w.joined_at, NOW())  AS waiting_minutes,
        w.status
FROM    waiting_list w
JOIN    canteen_orders o ON o.order_id = w.order_id
JOIN    customers c      ON c.customer_id = o.customer_id
WHERE   w.status = 'WAITING'
ORDER BY w.waiting_id;


CREATE OR REPLACE VIEW v_order_history AS
SELECT  o.order_id,
        c.full_name,
        c.roll_number,
        o.token_number,
        o.created_at    AS registered_at,
        o.completed_at,
        o.business_date,
        TIMESTAMPDIFF(MINUTE, o.created_at, o.completed_at) AS total_minutes
FROM    canteen_orders o
JOIN    customers c ON c.customer_id = o.customer_id
WHERE   o.status = 'COMPLETED'
ORDER BY o.completed_at DESC;


CREATE OR REPLACE VIEW v_dashboard_summary AS
SELECT
    (SELECT COUNT(*) FROM token_slots WHERE current_order_id IS NOT NULL)  AS active_tokens,
    (SELECT COUNT(*) FROM token_slots WHERE current_order_id IS NULL)      AS available_slots,
    15                                                                     AS max_active_tokens,
    (SELECT COUNT(*) FROM waiting_list WHERE status = 'WAITING')           AS customers_waiting,
    (SELECT COUNT(*) FROM canteen_orders
      WHERE status = 'COMPLETED' AND DATE(completed_at) = CURDATE())       AS completed_today;


CREATE OR REPLACE VIEW v_daily_report AS
SELECT  o.business_date,
        COUNT(*)                                                    AS total_registered,
        SUM(o.status = 'COMPLETED')                                 AS total_completed,
        SUM(o.status = 'WAITING')                                   AS still_waiting,
        ROUND(AVG(CASE WHEN o.status = 'COMPLETED'
                  THEN TIMESTAMPDIFF(SECOND, o.created_at, o.completed_at) / 60 END), 2)
                                                                    AS avg_completion_minutes,
        COALESCE(MAX(d.peak_active), 0)                             AS peak_active_tokens
FROM    canteen_orders o
LEFT JOIN daily_counters d ON d.business_date = o.business_date
GROUP BY o.business_date
ORDER BY o.business_date DESC;


/* ---------------------------------------------------------------------------
   3B. STORED PROCEDURES
   Both procedures first lock token slot 1 (FOR UPDATE). That one row acts as
   a "counter lock": only one register/complete operation can run at a time,
   so two requests can never take the same slot or exceed 15 active orders.
   Every procedure runs inside a transaction and rolls back on any error.
   --------------------------------------------------------------------------- */

DROP PROCEDURE IF EXISTS sp_generate_token;
DROP PROCEDURE IF EXISTS sp_complete_order;
DROP PROCEDURE IF EXISTS sp_demo_register_many;
DROP PROCEDURE IF EXISTS sp_clear_demo_data;

DELIMITER $$

/* ---- Register a customer: ACTIVE token if a slot is free, else WAITING ---- */
CREATE PROCEDURE sp_generate_token (
    IN  p_full_name     VARCHAR(100),
    IN  p_roll_number   VARCHAR(30),
    OUT p_order_id      BIGINT UNSIGNED,
    OUT p_status        VARCHAR(10),
    OUT p_token_number  TINYINT UNSIGNED,
    OUT p_queue_number  INT UNSIGNED,
    OUT p_message       VARCHAR(255)
)
proc: BEGIN
    DECLARE v_name         VARCHAR(100);
    DECLARE v_roll         VARCHAR(30);
    DECLARE v_lock         TINYINT UNSIGNED;
    DECLARE v_slot         TINYINT UNSIGNED DEFAULT NULL;
    DECLARE v_customer_id  BIGINT UNSIGNED;
    DECLARE v_today        DATE;
    DECLARE v_serial       INT UNSIGNED;
    DECLARE v_queue        INT UNSIGNED;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SET p_order_id = NULL;
    SET p_status = 'REJECTED';
    SET p_token_number = NULL;
    SET p_queue_number = NULL;

    SET v_name = TRIM(p_full_name);
    SET v_roll = NULLIF(TRIM(p_roll_number), '');

    IF v_name IS NULL OR CHAR_LENGTH(v_name) < 2 THEN
        SET p_message = 'Customer name must contain at least 2 characters.';
        LEAVE proc;
    END IF;

    SET v_today = CURDATE();

    START TRANSACTION;

    /* Counter lock: serialises all token operations */
    SELECT slot_number INTO v_lock FROM token_slots WHERE slot_number = 1 FOR UPDATE;

    /* Lowest free slot (NULL when all 15 are occupied) */
    SELECT MIN(slot_number) INTO v_slot FROM token_slots WHERE current_order_id IS NULL;

    INSERT INTO customers (full_name, roll_number) VALUES (v_name, v_roll);
    SET v_customer_id = LAST_INSERT_ID();

    /* Daily order number: starts again from 1 on each new business date */
    INSERT IGNORE INTO daily_counters (business_date, last_serial, peak_active)
    VALUES (v_today, 0, 0);
    UPDATE daily_counters SET last_serial = last_serial + 1 WHERE business_date = v_today;
    SELECT last_serial INTO v_serial FROM daily_counters WHERE business_date = v_today;

    IF v_slot IS NOT NULL THEN
        /* ---- A slot is free: customer becomes ACTIVE ---- */
        INSERT INTO canteen_orders
            (customer_id, business_date, daily_serial, token_number, status, activated_at)
        VALUES
            (v_customer_id, v_today, v_serial, v_slot, 'ACTIVE', NOW());
        SET p_order_id = LAST_INSERT_ID();

        UPDATE token_slots
           SET current_order_id = p_order_id, occupied_since = NOW()
         WHERE slot_number = v_slot;

        UPDATE daily_counters
           SET peak_active = GREATEST(peak_active,
                 (SELECT COUNT(*) FROM token_slots WHERE current_order_id IS NOT NULL))
         WHERE business_date = v_today;

        SET p_status = 'ACTIVE';
        SET p_token_number = v_slot;
        SET p_message = CONCAT('Token ', v_slot, ' assigned. Order ID ', p_order_id, '.');
    ELSE
        /* ---- All 15 slots busy: customer joins the waiting list ---- */
        INSERT INTO canteen_orders
            (customer_id, business_date, daily_serial, token_number, status)
        VALUES
            (v_customer_id, v_today, v_serial, NULL, 'WAITING');
        SET p_order_id = LAST_INSERT_ID();

        SELECT COALESCE(MAX(queue_number), 0) + 1 INTO v_queue
          FROM waiting_list WHERE business_date = v_today;

        INSERT INTO waiting_list (order_id, business_date, queue_number, status)
        VALUES (p_order_id, v_today, v_queue, 'WAITING');

        SET p_status = 'WAITING';
        SET p_queue_number = v_queue;
        SET p_message = CONCAT('All 15 tokens are in use. Customer added to the waiting list (queue number ',
                               v_queue, ').');
    END IF;

    COMMIT;
END$$


/* ---- Mark an ACTIVE order as delivered and promote the first waiting one ---- */
CREATE PROCEDURE sp_complete_order (
    IN  p_order_id           BIGINT UNSIGNED,
    OUT p_result             VARCHAR(12),
    OUT p_message            VARCHAR(255),
    OUT p_promoted_order_id  BIGINT UNSIGNED,
    OUT p_promoted_token     TINYINT UNSIGNED
)
proc: BEGIN
    DECLARE v_lock        TINYINT UNSIGNED;
    DECLARE v_status      VARCHAR(10)      DEFAULT NULL;
    DECLARE v_token       TINYINT UNSIGNED DEFAULT NULL;
    DECLARE v_wait_id     BIGINT UNSIGNED  DEFAULT NULL;
    DECLARE v_next_order  BIGINT UNSIGNED  DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SET p_result = 'REJECTED';
    SET p_message = NULL;
    SET p_promoted_order_id = NULL;
    SET p_promoted_token = NULL;

    START TRANSACTION;

    SELECT slot_number INTO v_lock FROM token_slots WHERE slot_number = 1 FOR UPDATE;

    SELECT status, token_number INTO v_status, v_token
      FROM canteen_orders
     WHERE order_id = p_order_id
       FOR UPDATE;

    IF v_status IS NULL THEN
        ROLLBACK;
        SET p_result = 'NOT_FOUND';
        SET p_message = 'Order not found.';
        LEAVE proc;
    ELSEIF v_status <> 'ACTIVE' THEN
        ROLLBACK;
        SET p_result = 'REJECTED';
        SET p_message = CONCAT('Order ', p_order_id, ' is already ', v_status, ' and cannot be delivered again.');
        LEAVE proc;
    END IF;

    /* 1. Close the order */
    UPDATE canteen_orders
       SET status = 'COMPLETED', completed_at = NOW()
     WHERE order_id = p_order_id;

    /* 2. Free its slot */
    UPDATE token_slots
       SET current_order_id = NULL, occupied_since = NULL
     WHERE slot_number = v_token AND current_order_id = p_order_id;

    /* 3. Oldest waiting customer (FIFO by waiting_id) */
    SELECT MIN(waiting_id) INTO v_wait_id FROM waiting_list WHERE status = 'WAITING';

    IF v_wait_id IS NOT NULL THEN
        SELECT order_id INTO v_next_order FROM waiting_list WHERE waiting_id = v_wait_id FOR UPDATE;

        /* The same record changes WAITING -> ACTIVE and gets the freed slot */
        UPDATE canteen_orders
           SET status = 'ACTIVE', token_number = v_token, activated_at = NOW()
         WHERE order_id = v_next_order;

        UPDATE token_slots
           SET current_order_id = v_next_order, occupied_since = NOW()
         WHERE slot_number = v_token;

        UPDATE waiting_list
           SET status = 'PROMOTED', promoted_at = NOW()
         WHERE waiting_id = v_wait_id;

        SET p_promoted_order_id = v_next_order;
        SET p_promoted_token = v_token;
        SET p_message = CONCAT('Order ', p_order_id, ' delivered. Order ', v_next_order,
                               ' promoted from the waiting list to token ', v_token, '.');
    ELSE
        SET p_message = CONCAT('Order ', p_order_id, ' delivered. Token ', v_token, ' is now free.');
    END IF;

    SET p_result = 'COMPLETED';
    COMMIT;
END$$


/* ---- Demo helper: registers N demo customers (roll numbers start with DEMO-) ---- */
CREATE PROCEDURE sp_demo_register_many (IN p_count INT)
BEGIN
    DECLARE v_i      INT DEFAULT 0;
    DECLARE v_start  INT;
    DECLARE v_oid    BIGINT UNSIGNED;
    DECLARE v_stat   VARCHAR(10);
    DECLARE v_tok    TINYINT UNSIGNED;
    DECLARE v_q      INT UNSIGNED;
    DECLARE v_msg    VARCHAR(255);

    SELECT COUNT(*) INTO v_start FROM customers WHERE roll_number LIKE 'DEMO-%';

    WHILE v_i < p_count DO
        SET v_i = v_i + 1;
        CALL sp_generate_token(CONCAT('Demo Student ', v_start + v_i),
                               CONCAT('DEMO-', LPAD(v_start + v_i, 3, '0')),
                               v_oid, v_stat, v_tok, v_q, v_msg);
    END WHILE;
END$$


/* ---- Demo helper: removes ONLY rows whose roll number starts with DEMO- ----
   Use it before real data exists. It never drops tables or the database.     */
CREATE PROCEDURE sp_clear_demo_data ()
BEGIN
    DECLARE v_lock TINYINT UNSIGNED;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;
    SELECT slot_number INTO v_lock FROM token_slots WHERE slot_number = 1 FOR UPDATE;

    UPDATE token_slots
       SET current_order_id = NULL, occupied_since = NULL
     WHERE current_order_id IN (
            SELECT order_id FROM (
                SELECT o.order_id
                  FROM canteen_orders o
                  JOIN customers c ON c.customer_id = o.customer_id
                 WHERE c.roll_number LIKE 'DEMO-%') AS d);

    DELETE FROM waiting_list
     WHERE order_id IN (
            SELECT order_id FROM (
                SELECT o.order_id
                  FROM canteen_orders o
                  JOIN customers c ON c.customer_id = o.customer_id
                 WHERE c.roll_number LIKE 'DEMO-%') AS d);

    DELETE FROM canteen_orders
     WHERE customer_id IN (SELECT customer_id FROM (
                SELECT customer_id FROM customers WHERE roll_number LIKE 'DEMO-%') AS d);

    DELETE FROM customers WHERE roll_number LIKE 'DEMO-%';
    COMMIT;
END$$

DELIMITER ;


/* ---------------------------------------------------------------------------
   4. INSERT THE 15 TOKEN SLOTS  (safe to run more than once)
   --------------------------------------------------------------------------- */
INSERT IGNORE INTO token_slots (slot_number) VALUES
    (1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11),(12),(13),(14),(15);


/* ---------------------------------------------------------------------------
   5. OPTIONAL DEMONSTRATION RECORDS
   Run this section ONCE. It registers 5 demo customers and delivers the first.
   --------------------------------------------------------------------------- */
CALL sp_demo_register_many(5);

SET @first_order = (SELECT MIN(order_id) FROM canteen_orders WHERE status = 'ACTIVE');
CALL sp_complete_order(@first_order, @result, @message, @promoted_order, @promoted_token);
SELECT @result AS result, @message AS message;


/* ---------------------------------------------------------------------------
   6. DEMONSTRATION QUERIES
   --------------------------------------------------------------------------- */

/* 6.1 Register one real-looking customer by hand */
CALL sp_generate_token('Ravi Kumar', '22CS101', @oid, @st, @tok, @qn, @msg);
SELECT @oid AS order_id, @st AS status, @tok AS token_number, @qn AS queue_number, @msg AS message;

/* 6.2 Fill the canteen to test the 15-token limit (adds 12 more demo customers) */
-- CALL sp_demo_register_many(12);

/* 6.3 Deliver an order (replace 1 with a real ACTIVE order_id) */
-- CALL sp_complete_order(1, @r, @m, @po, @pt);
-- SELECT @r AS result, @m AS message, @po AS promoted_order, @pt AS promoted_token;

/* 6.4 Dashboard numbers */
SELECT * FROM v_dashboard_summary;

/* 6.5 Active tokens */
SELECT * FROM v_active_tokens;

/* 6.6 Waiting list in FIFO order */
SELECT * FROM v_waiting_queue;

/* 6.7 Order history */
SELECT * FROM v_order_history;


/* ---------------------------------------------------------------------------
   7. VERIFICATION QUERIES
   --------------------------------------------------------------------------- */

/* 7.1 Tables exist */
SHOW TABLES;

/* 7.2 Exactly 15 slots, and how many are occupied (never more than 15) */
SELECT COUNT(*) AS total_slots,
       SUM(current_order_id IS NOT NULL) AS occupied_slots,
       SUM(current_order_id IS NULL)     AS free_slots
FROM token_slots;

/* 7.3 Active-order count must equal occupied slots, and be <= 15 */
SELECT (SELECT COUNT(*) FROM canteen_orders WHERE status = 'ACTIVE')        AS active_orders,
       (SELECT COUNT(*) FROM token_slots WHERE current_order_id IS NOT NULL) AS occupied_slots;

/* 7.4 No duplicate token among ACTIVE orders (expected: 0 rows) */
SELECT token_number, COUNT(*) AS times_used
FROM canteen_orders
WHERE status = 'ACTIVE'
GROUP BY token_number
HAVING COUNT(*) > 1;

/* 7.5 Waiting list order (oldest first) */
SELECT w.queue_number, w.order_id, c.full_name, w.joined_at, w.status
FROM waiting_list w
JOIN canteen_orders o ON o.order_id = w.order_id
JOIN customers c ON c.customer_id = o.customer_id
WHERE w.status = 'WAITING'
ORDER BY w.waiting_id;

/* 7.6 Completed orders */
SELECT order_id, token_number, created_at, completed_at, business_date
FROM canteen_orders
WHERE status = 'COMPLETED'
ORDER BY completed_at;

/* 7.7 Daily token history: the same token number may appear many times on a
       day, but every row keeps its own unique order_id */
SELECT business_date, daily_serial, order_id, token_number, status, created_at, completed_at
FROM canteen_orders
ORDER BY business_date, daily_serial;

/* 7.8 Daily report */
SELECT * FROM v_daily_report;


/* ---------------------------------------------------------------------------
   8. CLEANUP / RESET (DEMONSTRATION DATA ONLY)
   These NEVER drop the database or tables.
   --------------------------------------------------------------------------- */

/* 8.1 Remove only demo customers/orders (roll numbers starting with DEMO-).
       Un-comment the next line to run it.                                      */
-- CALL sp_clear_demo_data();

/* 8.2 Check that the 15 slots are intact after cleanup */
SELECT * FROM token_slots ORDER BY slot_number;

/* 8.3 To end a real business day, deliver the remaining active orders from the
       website. Completed orders are history and are intentionally kept.        */
/* ========================== END OF schema.sql ============================== */
