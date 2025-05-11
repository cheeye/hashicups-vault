import psycopg2
from datetime import datetime
from flask import Flask, render_template, request, jsonify
import os
import json
import requests
import base64

app = Flask(__name__)

products = [
    {"name": "Consul Spiced Latte", "image": "coffee1.png"},
    {"name": "Nomad Macchiato", "image": "coffee2.png"},
    {"name": "Terraform Cold Brew", "image": "coffee3.png"},
    {"name": "Vault Vanilla Roast", "image": "coffee4.png"}
]

VAULT_ADDR = os.environ.get('VAULT_ADDR', 'http://127.0.0.1:8100')

def get_db_connection():
    """Get a PostgreSQL connection using dynamic credentials from Vault"""
    try:
        # Read credentials from Vault agent generated file
        with open('/etc/vault-agent/secrets.json', 'r') as f:
            creds = json.load(f)
            username = creds['database_creds']['username']
            password = creds['database_creds']['password']
        
        # Connect to the database
        host = os.environ.get('DB_HOST', 'localhost')
        conn = psycopg2.connect(
            host=host,
            database="postgres",
            user=username,
            password=password
        )
        return conn
    except Exception as e:
        print(f"Database connection error: {e}")
        return None
    
def encrypt_transit(card_number):
    """Encrypt card number using Vault Transit"""
    try:
        # Base64 encode the card number
        encoded_card = base64.b64encode(card_number.encode()).decode('utf-8')
        
        # Call Vault API to encrypt
        data = {'plaintext': encoded_card}
        response = requests.post(
            f"{VAULT_ADDR}/v1/transit/encrypt/card-encrypt",
            json=data
        )
        
        if response.status_code == 200:
            return response.json()['data']['ciphertext']
        else:
            print(f"Encryption error: {response.text}")
            return None
    except Exception as e:
        print(f"Encryption error: {e}")
        return None

def tokenize_card(card_number):
    """Tokenize card number using Vault Transform FPE"""
    try:
        data = {
            'value': card_number,
            'transformation': 'card-number',
            'tweak': ''
        }
        response = requests.post(
            f"{VAULT_ADDR}/v1/transform/encode/payments",
            json=data
        )
        
        if response.status_code == 200:
            return response.json()['data']['encoded_value']
        else:
            print(f"Tokenization error: {response.text}")
            return None
    except Exception as e:
        print(f"Tokenization error: {e}")
        return None

def mask_card(card_number):
    """Mask card number using Vault Transform masking"""
    try:
        data = {
            'value': card_number,
            'transformation': 'masked-card-number',
            'tweak': ''
        }
        response = requests.post(
            f"{VAULT_ADDR}/v1/transform/encode/custsupport",
            json=data
        )
        
        if response.status_code == 200:
            return response.json()['data']['encoded_value']
        else:
            print(f"Masking error: {response.text}")
            return None
    except Exception as e:
        print(f"Masking error: {e}")
        return None

def save_transaction(name, card_number, card_transit, card_fpe, card_masked):
    """Save transaction to PostgreSQL using dynamic credentials"""
    conn = get_db_connection()
    if conn:
        try:
            cur = conn.cursor()
            # Insert the transaction
            cur.execute(
                """
                INSERT INTO transactions (name, card_number, card_number_transit, card_number_fpe, card_number_masked)
                VALUES (%s, %s, %s, %s, %s)
                """,
                (name, card_number[-4:], card_transit, card_fpe, card_masked)
            )
            conn.commit()
            cur.close()
            conn.close()
            return True
        except Exception as e:
            print(f"Database error: {e}")
            if conn:
                conn.close()
            return False
    return False

@app.route('/')
def index():
    return render_template('index.html', products=products)

@app.route('/buy', methods=['POST'])
def buy():
    product = request.form.get('product', '')
    return render_template('payment.html', product=product, submitted=False)

@app.route('/submit', methods=['POST'])
def submit():
    # Get card data from form
    card_number = request.form.get('number', '').replace(' ', '')
    name = request.form.get('name', '')
    cvv = request.form.get('cvv', '')
    expiry = request.form.get('expiry', '')
    
    # Validate CVV
    if not cvv.isdigit() or len(cvv) not in [3, 4]:
        return render_template(
            'payment.html',
            submitted=True,
            success=False,
            error="Invalid CVV. Please enter 3 or 4 digits."
        )
    
    # Validate expiry date
    try:
        month, year = expiry.split('/')
        month = int(month)
        year = int(year)
        if not (1 <= month <= 12):
            return render_template(
                'payment.html',
                submitted=True,
                success=False,
                error="Invalid expiry month. Please enter a month between 01 and 12."
            )
        current_year = datetime.now().year % 100
        if year < current_year or (year == current_year and month < datetime.now().month):
            return render_template(
                'payment.html',
                submitted=True,
                success=False,
                error="Card has expired."
            )
    except (ValueError, AttributeError):
        return render_template(
            'payment.html',
            submitted=True,
            success=False,
            error="Invalid expiry date format. Please use MM/YY."
        )
    
    # Process card data with Vault
    card_transit = encrypt_transit(card_number)
    card_fpe = tokenize_card(card_number)
    formatted_card_fpe = '-'.join([card_fpe[i:i+4] for i in range(0, len(card_fpe), 4)])
    card_masked = mask_card(card_number)
    
    #Save to database
    success = save_transaction(name, card_number, card_transit, card_fpe, card_masked)
    
    # Return processed data to display
    return render_template(
        'payment.html',
        submitted=True,
        success=success,
        name=name,
        last_four=card_number[-4:],
        encrypted=card_transit[:25] + '...' if card_transit else 'Error',
        tokenized=formatted_card_fpe if card_fpe else 'Error',
        masked=card_masked if card_masked else 'Error'
    )

@app.route('/alldata')
def alldata():
    conn = get_db_connection()
    if conn:
        try:
            cur = conn.cursor()
            cur.execute("SELECT id, name, card_number, card_number_transit, card_number_fpe, card_number_masked FROM transactions ORDER BY id DESC;")
            rows = cur.fetchall()
            columns = [desc[0] for desc in cur.description]
            cur.close()
            conn.close()
            return render_template('alldata.html', rows=rows, columns=columns)
        except Exception as e:
            print(f"Query error: {e}")
            return "Error fetching data", 500
    return "DB connection failed", 500


@app.route('/healthcheck')
def healthcheck():
    return jsonify({"status": "healthy", "timestamp": datetime.now().isoformat()})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
