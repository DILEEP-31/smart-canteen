# 🍽️ College Smart Canteen Token System

A production-grade, beginner-friendly Flask + MySQL web application designed to eliminate lunch-hour counter overcrowding in college canteens through a strict 15-token physical slot constraint, FIFO waiting queue, and automated token promotion.

---

## 🏗️ Architecture & DBMS Design

This project demonstrates how web applications should delegate critical concurrency and state management to the **Database Management System (DBMS)** rather than implementing duplicate logic in Python:

- **Database Engine:** MySQL 8.0+ (InnoDB)
- **Database Name:** `college_smart_canteen`
- **15-Token Slot Constraint:** Guaranteed by `token_slots` (15 physical rows) and unique index constraints.
- **Concurrency Serialization:** Handled via MySQL stored procedures locking `token_slots` slot #1 (`FOR UPDATE`) inside transactions with rollback handlers.
- **Python Framework:** Flask 3.x with Jinja2, parameterized queries, and session CSRF protection.
- **Analytics:** Dynamic visualization using Chart.js powered exclusively by live data from MySQL view `v_daily_report`.

---

## 📁 Project Structure

```
canteen-token-system/
├── app.py                     # Flask application routes, CSRF middleware & error handlers
├── db.py                      # Database connection manager, view queries & stored procedure calls
├── config.py                  # Environment configuration loaded from .env
├── schema.sql                 # MySQL schema, tables, views, triggers & stored procedures
├── requirements.txt           # Python dependencies
├── .env.example               # Template for environment configuration
├── .env                       # Local environment credentials (ignored by git)
├── .gitignore                 # Git ignore rules for venv, bytecode, and secrets
├── README.md                  # Comprehensive setup, architecture & testing checklist
├── templates/                 # Jinja2 HTML5 templates
│   ├── base.html              # Base layout with sidebar, topbar, clock & toasts
│   ├── dashboard.html         # Live overview, capacity banner & 4 metric cards
│   ├── register.html          # Customer registration form with double-submit guard
│   ├── active_tokens.html     # Active kitchen tokens (1–15) & mark delivered action
│   ├── waiting_list.html      # FIFO waiting queue with live wait times
│   ├── history.html           # Completed orders history with search & date filter
│   ├── reports.html           # Aggregated daily reports & real-data Chart.js graphs
│   └── error.html             # Friendly MySQL connection & HTTP error page
└── static/
    ├── css/
    │   └── style.css          # Modern dashboard design system & responsive UI
    └── js/
        └── app.js             # Double-submit guard, confirm modal & auto-dismiss toasts
```

---

## ⚡ Quick Start: Windows PowerShell Commands

Run the following exact commands in **Windows PowerShell** inside this project folder:

### 1. Create and Activate Python Virtual Environment
```powershell
python -m venv venv
.\venv\Scripts\Activate.ps1
```
*(If PowerShell restricts script execution, run: `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`)*

### 2. Install Dependencies
```powershell
pip install -r requirements.txt
```

### 3. Configure Database Credentials (`.env`)
Copy `.env.example` to `.env` (or edit the existing `.env`):
```ini
DB_HOST=localhost
DB_PORT=3306
DB_USER=canteen_app
DB_PASSWORD=your_actual_mysql_password
DB_NAME=college_smart_canteen
SECRET_KEY=canteen-token-secret-key-2026
```

### 4. MySQL User & Schema Setup (Run in SQLyog)
Make sure the `canteen_app` user has access to `college_smart_canteen`. If you haven't created the user yet, run this in SQLyog:
```sql
CREATE USER IF NOT EXISTS 'canteen_app'@'localhost' IDENTIFIED BY 'your_actual_mysql_password';
GRANT ALL PRIVILEGES ON college_smart_canteen.* TO 'canteen_app'@'localhost';
FLUSH PRIVILEGES;
```
Ensure that `schema.sql` has been executed in SQLyog so all 5 tables, 5 views, and 2 stored procedures are created.

### 5. Launch the Application
```powershell
python app.py
```
Open your web browser and navigate to:
👉 **[http://127.0.0.1:5000](http://127.0.0.1:5000)**

---

## 📋 Comprehensive Testing Checklist

Follow this checklist step-by-step to verify the core requirements and DBMS concurrency handling:

- [ ] **1. Test First Customer Registration (ACTIVE Token):**
  - Navigate to **Register Customer** (`/register`).
  - Enter name: `Ravi Kumar`, Roll Number: `22CS101`.
  - Click **Generate Token**.
  - **Expected:** Order status is `ACTIVE`, and Token `#1` is assigned immediately.

- [ ] **2. Test 15-Token Slot Limit (Fill Canteen):**
  - Register customers until all 15 active slots are occupied (Token #1 to #15).
  - Open **Dashboard** (`/`).
  - **Expected:** Active tokens display `15 / 15`, Available Slots display `0`, and a prominent red **"FULL CAPACITY REACHED (15 / 15 TOKENS OCCUPIED)"** alert banner is displayed.

- [ ] **3. Test 16th Customer Registration (WAITING Queue):**
  - While all 15 tokens are occupied, register a 16th customer (e.g. `Ananya Sharma`).
  - **Expected:** Status is `WAITING`, Queue `#1` is assigned, and no active token number is issued.
  - Visit **Waiting Queue** (`/waiting-list`) to see them at Queue Position `#1`.

- [ ] **4. Test Delivery & Automatic FIFO Promotion:**
  - Navigate to **Active Tokens** (`/active-tokens`).
  - Click **✓ Mark as Delivered** on Token `#1` and confirm in the modal dialog.
  - **Expected:**
    - The stored procedure `sp_complete_order` executes.
    - Token `#1` order changes to `COMPLETED` and moves to Order History.
    - Waiting customer `Ananya Sharma` is **automatically promoted** to Token `#1`!
    - A success toast informs: *"Order #1 marked as DELIVERED! Waiting Order #16 was automatically promoted to Token #1."*

- [ ] **5. Test Double-Delivery Prevention:**
  - Try delivering an order that has already been delivered (or repeat the request).
  - **Expected:** MySQL rejects the operation (`p_result = 'REJECTED'`), and a warning is displayed: *"Order X is already COMPLETED and cannot be delivered again."*

- [ ] **6. Test Order History & Search:**
  - Visit **Order History** (`/history`).
  - Test searching by customer name (`Ravi`) and filtering by today's date.
  - **Expected:** Parameterized filtering returns only matching completed records with total preparation turnaround time in minutes.

- [ ] **7. Test Reports & Chart.js Visualizations:**
  - Visit **Daily Reports** (`/reports`).
  - **Expected:** Summary statistics and three Chart.js charts (Order Volume, Turnaround Time, and Peak Active Tokens vs 15-slot capacity line) render with real database values from `v_daily_report`.

- [ ] **8. Test Data Persistence:**
  - Refresh the page and restart the Flask server (`Ctrl+C` then `python app.py`).
  - **Expected:** All tokens, queue positions, and order records persist because they are stored permanently in MySQL InnoDB tables.

---

## 🔍 Verification & Transparency Note

- **Automated Verification Completed During Development:**
  - Python virtual environment creation and dependency installation (`Flask`, `mysql-connector-python`, `python-dotenv`).
  - Clean template compilation and Jinja2 rendering.
  - CSRF token middleware validation.
  - `DatabaseConnectionError` handling verification (returns HTTP 503 with friendly diagnostic guide when MySQL credentials need to be configured).
- **Steps You Must Run Yourself:**
  - Update `.env` with your actual MySQL password for `canteen_app` (or `root`).
  - Ensure the MySQL service (`MySQL267`) is running on port 3306.
  - Follow the testing checklist in your web browser at `http://127.0.0.1:5000`.
