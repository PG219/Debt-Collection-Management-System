# Debt Collection Management System


---

## Project Structure

```
dcrs/
├── app.py              ← Flask backend (Python API)
├── index.html          ← Frontend web app
├── requirements.txt    ← Python dependencies
└── README.md
```

---

## Setup Instructions

### Step 1 — Set up MySQL Database
1. Open MySQL Workbench
2. Run `debt_collection_system.sql` (the SQL file from earlier)
3. Confirm `debt_collection_db` database is created

### Step 2 — Install Python dependencies
```bash
pip install flask flask-cors mysql-connector-python
```

### Step 3 — Configure database credentials in app.py
Open `app.py` and update these lines:
```python
DB_CONFIG = {
    'host':     'localhost',
    'user':     'root',       # ← your MySQL username
    'password': '',           # ← your MySQL password
    'database': 'debt_collection_db'
}
```

### Step 4 — Run the Flask server
```bash
python app.py
```
You should see:
```
🚀 DCRS Flask API running at http://localhost:5000
```

### Step 5 — Open the frontend
Open `index.html` in your browser.
The app will automatically fetch live data from MySQL via Flask.

---

## API Endpoints

| Method | Endpoint                          | Description                    |
|--------|-----------------------------------|--------------------------------|
| GET    | /api/dashboard                    | Summary stats                  |
| GET    | /api/agencies                     | All agencies + performance     |
| GET    | /api/customers                    | All customers (Individual + Corporate) |
| GET    | /api/invoices                     | All invoices with payment data |
| POST   | /api/invoices                     | Create new invoice             |
| PUT    | /api/invoices/<id>/assign         | Assign invoice to agency       |
| GET    | /api/payments                     | All payment records            |
| POST   | /api/payments                     | Record a new payment           |
| GET    | /api/legal                        | Legal escalation invoices      |

---

## How It All Connects

```
index.html  ──fetch()──▶  app.py (Flask)  ──SQL──▶  MySQL (debt_collection_db)
   ▲                           │
   └───────── JSON ────────────┘
```

Every button click (New Invoice, Record Payment) sends a request to Flask,
which executes SQL and returns the result as JSON back to the browser.
MySQL triggers handle auto-closing invoices and commission calculation automatically.