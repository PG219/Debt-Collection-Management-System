from flask import Flask, jsonify, request
from flask_cors import CORS
import mysql.connector
from datetime import date, datetime
import decimal

app = Flask(__name__)
CORS(app)

DB_CONFIG = {
    'host':     'localhost',
    'user':     'root',
    'password': '12345',
    'database': 'debt_collection_db'
}

def get_db():
    return mysql.connector.connect(**DB_CONFIG)

def serialize(obj):
    if isinstance(obj, decimal.Decimal):
        return float(obj)
    if isinstance(obj, (date, datetime)):
        return str(obj)
    return obj

def row_to_dict(cursor, row):
    columns = [col[0] for col in cursor.description]
    return {col: serialize(val) for col, val in zip(columns, row)}

def rows_to_list(cursor, rows):
    return [row_to_dict(cursor, row) for row in rows]


@app.route('/api/agencies', methods=['GET'])
def get_agencies():
    conn = get_db()
    cur = conn.cursor()
    cur.execute("""
        SELECT
            a.Agency_ID, a.Agency_Name, a.Contact_Number, a.Commission_Rate,
            COUNT(DISTINCT i.Invoice_ID)   AS total_invoices,
            COUNT(DISTINCT CASE WHEN i.Status = 'Closed' THEN i.Invoice_ID END) AS closed_invoices,
            COALESCE(SUM(p.Amount_Paid), 0)         AS total_recovered,
            COALESCE(SUM(p.Commission_Amount), 0)   AS total_commission
        FROM Agency a
        LEFT JOIN Invoice i ON a.Agency_ID = i.Agency_ID
        LEFT JOIN Payment p ON i.Invoice_ID = p.Invoice_ID
        GROUP BY a.Agency_ID, a.Agency_Name, a.Contact_Number, a.Commission_Rate
    """)
    result = rows_to_list(cur, cur.fetchall())
    cur.close(); conn.close()
    return jsonify(result)


@app.route('/api/customers', methods=['GET'])
def get_customers():
    conn = get_db()
    cur = conn.cursor()
    cur.execute("""
        SELECT
            c.Customer_ID, c.Email, c.Phone_Number, c.Risk_Level, c.Registration_Date,
            CASE
                WHEN ic.Customer_ID IS NOT NULL THEN 'Individual'
                WHEN cc.Customer_ID IS NOT NULL THEN 'Corporate'
                ELSE 'Unknown'
            END AS customer_type,
            COALESCE(
                CONCAT(ic.First_Name, ' ', ic.Last_Name),
                cc.Company_Name
            ) AS display_name,
            COALESCE(ic.National_ID, cc.Tax_Reg_Number) AS identifier
        FROM Customer c
        LEFT JOIN Individual_Customer ic ON c.Customer_ID = ic.Customer_ID
        LEFT JOIN Corporate_Customer  cc ON c.Customer_ID = cc.Customer_ID
        ORDER BY c.Customer_ID
    """)
    result = rows_to_list(cur, cur.fetchall())
    cur.close(); conn.close()
    return jsonify(result)


@app.route('/api/invoices', methods=['GET'])
def get_invoices():
    conn = get_db()
    cur = conn.cursor()
    cur.execute("""
        SELECT
            i.Invoice_ID, i.Amount_Due, i.Due_Date, i.Status,
            i.Customer_ID, i.Agency_ID,
            COALESCE(CONCAT(ic.First_Name,' ',ic.Last_Name), cc.Company_Name) AS customer_name,
            CASE
                WHEN ic.Customer_ID IS NOT NULL THEN 'Individual'
                ELSE 'Corporate'
            END AS customer_type,
            a.Agency_Name,
            COALESCE(SUM(p.Amount_Paid), 0) AS total_paid,
            DATEDIFF(CURDATE(), i.Due_Date)  AS days_overdue
        FROM Invoice i
        LEFT JOIN Customer c             ON i.Customer_ID  = c.Customer_ID
        LEFT JOIN Individual_Customer ic ON c.Customer_ID  = ic.Customer_ID
        LEFT JOIN Corporate_Customer  cc ON c.Customer_ID  = cc.Customer_ID
        LEFT JOIN Agency a               ON i.Agency_ID    = a.Agency_ID
        LEFT JOIN Payment p              ON i.Invoice_ID   = p.Invoice_ID
        GROUP BY i.Invoice_ID, i.Amount_Due, i.Due_Date, i.Status,
                 i.Customer_ID, i.Agency_ID, customer_name, customer_type,
                 a.Agency_Name
        ORDER BY i.Invoice_ID
    """)
    result = rows_to_list(cur, cur.fetchall())
    cur.close(); conn.close()
    return jsonify(result)


@app.route('/api/invoices', methods=['POST'])
def create_invoice():
    data = request.get_json()
    required = ['amount_due', 'due_date', 'customer_id']
    for field in required:
        if field not in data:
            return jsonify({'error': f'Missing field: {field}'}), 400

    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute("""
            INSERT INTO Invoice (Amount_Due, Due_Date, Customer_ID, Agency_ID, Status)
            VALUES (%s, %s, %s, %s, 'Open')
        """, (
            data['amount_due'],
            data['due_date'],
            data['customer_id'],
            data.get('agency_id')
        ))
        conn.commit()
        new_id = cur.lastrowid
        cur.close(); conn.close()
        return jsonify({'message': 'Invoice created', 'invoice_id': new_id}), 201
    except Exception as e:
        conn.rollback()
        cur.close(); conn.close()
        return jsonify({'error': str(e)}), 400


@app.route('/api/invoices/<int:invoice_id>/assign', methods=['PUT'])
def assign_invoice(invoice_id):
    data = request.get_json()
    agency_id = data.get('agency_id')
    if not agency_id:
        return jsonify({'error': 'agency_id is required'}), 400

    conn = get_db()
    cur = conn.cursor()
    try:
        cur.callproc('AssignInvoiceToAgency', [invoice_id, agency_id])
        conn.commit()
        cur.close(); conn.close()
        return jsonify({'message': f'Invoice #{invoice_id} assigned to agency #{agency_id}'})
    except mysql.connector.Error as e:
        cur.close(); conn.close()
        return jsonify({'error': e.msg}), 400


@app.route('/api/payments', methods=['GET'])
def get_payments():
    conn = get_db()
    cur = conn.cursor()
    cur.execute("""
        SELECT
            p.Payment_ID, p.Payment_Date, p.Amount_Paid,
            p.Payment_Method, p.Commission_Amount, p.Invoice_ID,
            a.Agency_Name,
            COALESCE(CONCAT(ic.First_Name,' ',ic.Last_Name), cc.Company_Name) AS customer_name
        FROM Payment p
        JOIN Invoice i               ON p.Invoice_ID   = i.Invoice_ID
        LEFT JOIN Agency a           ON i.Agency_ID    = a.Agency_ID
        LEFT JOIN Customer c         ON i.Customer_ID  = c.Customer_ID
        LEFT JOIN Individual_Customer ic ON c.Customer_ID = ic.Customer_ID
        LEFT JOIN Corporate_Customer  cc ON c.Customer_ID = cc.Customer_ID
        ORDER BY p.Payment_Date DESC
    """)
    result = rows_to_list(cur, cur.fetchall())
    cur.close(); conn.close()
    return jsonify(result)


@app.route('/api/payments', methods=['POST'])
def record_payment():
    data = request.get_json()
    required = ['invoice_id', 'amount_paid', 'payment_method']
    for field in required:
        if field not in data:
            return jsonify({'error': f'Missing field: {field}'}), 400

    conn = get_db()
    cur = conn.cursor()
    try:
        cur.callproc('RecordPayment', [
            data['invoice_id'],
            data['amount_paid'],
            data['payment_method']
        ])
        conn.commit()
        cur.close(); conn.close()
        return jsonify({'message': 'Payment recorded successfully'}), 201
    except mysql.connector.Error as e:
        conn.rollback()
        cur.close(); conn.close()
        return jsonify({'error': e.msg}), 400


@app.route('/api/dashboard', methods=['GET'])
def get_dashboard():
    conn = get_db()
    cur = conn.cursor()

    cur.execute("SELECT COALESCE(SUM(Amount_Due), 0) FROM Invoice WHERE Status != 'Closed'")
    total_outstanding = serialize(cur.fetchone()[0])

    cur.execute("SELECT COALESCE(SUM(Amount_Paid), 0) FROM Payment")
    total_recovered = serialize(cur.fetchone()[0])

    cur.execute("SELECT COUNT(*) FROM Agency")
    agency_count = cur.fetchone()[0]

    cur.execute("SELECT COUNT(*) FROM Invoice WHERE Status = 'Legal Action Required'")
    legal_count = cur.fetchone()[0]

    cur.execute("SELECT COUNT(*) FROM Invoice WHERE Status = 'Open'")
    open_count = cur.fetchone()[0]

    cur.close(); conn.close()
    return jsonify({
        'total_outstanding': total_outstanding,
        'total_recovered':   total_recovered,
        'agency_count':      agency_count,
        'legal_count':       legal_count,
        'open_count':        open_count,
    })


@app.route('/api/legal', methods=['GET'])
def get_legal():
    conn = get_db()
    cur = conn.cursor()
    cur.execute("""
        SELECT
            i.Invoice_ID, i.Amount_Due, i.Due_Date, i.Status,
            DATEDIFF(CURDATE(), i.Due_Date)  AS days_overdue,
            COALESCE(SUM(p.Amount_Paid), 0)  AS total_paid,
            a.Agency_Name,
            COALESCE(CONCAT(ic.First_Name,' ',ic.Last_Name), cc.Company_Name) AS customer_name,
            CASE WHEN ic.Customer_ID IS NOT NULL THEN 'Individual' ELSE 'Corporate' END AS customer_type
        FROM Invoice i
        LEFT JOIN Payment p              ON i.Invoice_ID  = p.Invoice_ID
        LEFT JOIN Agency a               ON i.Agency_ID   = a.Agency_ID
        LEFT JOIN Customer c             ON i.Customer_ID = c.Customer_ID
        LEFT JOIN Individual_Customer ic ON c.Customer_ID = ic.Customer_ID
        LEFT JOIN Corporate_Customer  cc ON c.Customer_ID = cc.Customer_ID
        WHERE i.Status = 'Legal Action Required'
        GROUP BY i.Invoice_ID, i.Amount_Due, i.Due_Date, i.Status,
                 a.Agency_Name, customer_name, customer_type
    """)
    result = rows_to_list(cur, cur.fetchall())
    cur.close(); conn.close()
    return jsonify(result)


if __name__ == '__main__':
    print("DCRS Flask API running at http://localhost:5000")
    app.run(debug=True, port=5000)
