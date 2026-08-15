import sqlite3
import datetime
import os
import logging

logger = logging.getLogger(__name__)

DB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pending_users.db")

def init_pending_db():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    # 1. Pending registrations table (added attempts column)
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS pending_registrations (
            personal_email TEXT PRIMARY KEY,
            username TEXT NOT NULL,
            password TEXT NOT NULL,
            full_name TEXT NOT NULL,
            role TEXT NOT NULL,
            phone TEXT,
            specialization TEXT,
            verification_code TEXT NOT NULL,
            expires_at TIMESTAMP NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0
        )
    """)
    
    # 2. Clinic email to Personal email mapping table
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS email_mappings (
            clinic_email TEXT PRIMARY KEY,
            personal_email TEXT NOT NULL UNIQUE
        )
    """)
    
    # 3. Password resets table (added attempts column)
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS password_resets (
            reset_token TEXT PRIMARY KEY,
            clinic_email TEXT NOT NULL,
            personal_email TEXT NOT NULL,
            expires_at TIMESTAMP NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0
        )
    """)
    
    # 4. Blacklisted tokens table
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS blacklisted_tokens (
            token TEXT PRIMARY KEY,
            expires_at TIMESTAMP NOT NULL
        )
    """)
    
    # 5. Email sent times table (for rate limiting)
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS email_sent_times (
            email TEXT,
            sent_at TIMESTAMP NOT NULL
        )
    """)
    
    conn.commit()
    conn.close()

def save_pending_registration(personal_email, username, password, full_name, role, phone, specialization, verification_code):
    init_pending_db()
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    # Expire in exactly 10 minutes
    expires_at = datetime.datetime.utcnow() + datetime.timedelta(minutes=10)
    cursor.execute("""
        INSERT OR REPLACE INTO pending_registrations 
        (personal_email, username, password, full_name, role, phone, specialization, verification_code, expires_at, attempts)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
    """, (
        personal_email.strip().lower(),
        username.strip().lower(),
        password,
        full_name.strip(),
        role.strip().lower(),
        phone.strip() if phone else None,
        specialization.strip() if specialization else None,
        verification_code,
        expires_at
    ))
    conn.commit()
    conn.close()

def get_pending_registration(personal_email):
    init_pending_db()
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("""
        SELECT username, password, full_name, role, phone, specialization, verification_code, expires_at, attempts, personal_email
        FROM pending_registrations
        WHERE personal_email = ?
    """, (personal_email.strip().lower(),))
    row = cursor.fetchone()
    conn.close()
    
    if not row:
        return None
        
    return {
        "username": row[0],
        "password": row[1],
        "full_name": row[2],
        "role": row[3],
        "phone": row[4],
        "specialization": row[5],
        "verification_code": row[6],
        "expires_at": datetime.datetime.fromisoformat(row[7]) if isinstance(row[7], str) else row[7],
        "attempts": row[8],
        "personal_email": row[9]
    }

def get_pending_registration_by_username(username):
    init_pending_db()
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("""
        SELECT personal_email, username, password, full_name, role, phone, specialization, verification_code, expires_at, attempts
        FROM pending_registrations
        WHERE username = ?
    """, (username.strip().lower(),))
    row = cursor.fetchone()
    conn.close()
    
    if not row:
        return None
        
    return {
        "personal_email": row[0],
        "username": row[1],
        "password": row[2],
        "full_name": row[3],
        "role": row[4],
        "phone": row[5],
        "specialization": row[6],
        "verification_code": row[7],
        "expires_at": datetime.datetime.fromisoformat(row[8]) if isinstance(row[8], str) else row[8],
        "attempts": row[9]
    }

def increment_registration_attempts(personal_email):
    init_pending_db()
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("""
        UPDATE pending_registrations
        SET attempts = attempts + 1
        WHERE personal_email = ?
    """, (personal_email.strip().lower(),))
    conn.commit()
    
    cursor.execute("SELECT attempts FROM pending_registrations WHERE personal_email = ?", (personal_email.strip().lower(),))
    row = cursor.fetchone()
    conn.close()
    return row[0] if row else 0

def delete_pending_registration(personal_email):
    init_pending_db()
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("DELETE FROM pending_registrations WHERE personal_email = ?", (personal_email.strip().lower(),))
    conn.commit()
    conn.close()

def save_email_mapping(clinic_email, personal_email):
    init_pending_db()
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("""
        INSERT OR REPLACE INTO email_mappings (clinic_email, personal_email)
        VALUES (?, ?)
    """, (clinic_email.strip().lower(), personal_email.strip().lower()))
    conn.commit()
    conn.close()

def get_personal_email_by_clinic_email(clinic_email):
    init_pending_db()
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("""
        SELECT personal_email FROM email_mappings WHERE clinic_email = ?
    """, (clinic_email.strip().lower(),))
    row = cursor.fetchone()
    conn.close()
    return row[0] if row else None

def is_personal_email_exists(personal_email):
    init_pending_db()
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("""
        SELECT 1 FROM email_mappings WHERE personal_email = ?
    """, (personal_email.strip().lower(),))
    row = cursor.fetchone()
    conn.close()
    return row is not None

def is_username_or_email_pending(username, personal_email):
    init_pending_db()
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    now = datetime.datetime.utcnow()
    cursor.execute("""
        SELECT 1 FROM pending_registrations 
        WHERE (username = ? OR personal_email = ?) AND expires_at > ?
    """, (username.strip().lower(), personal_email.strip().lower(), now))
    row = cursor.fetchone()
    conn.close()
    return row is not None

def save_password_reset(clinic_email, personal_email, reset_token):
    init_pending_db()
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    # Expire in exactly 10 minutes
    expires_at = datetime.datetime.utcnow() + datetime.timedelta(minutes=10)
    cursor.execute("""
        INSERT OR REPLACE INTO password_resets (reset_token, clinic_email, personal_email, expires_at, attempts)
        VALUES (?, ?, ?, ?, 0)
    """, (reset_token, clinic_email.strip().lower(), personal_email.strip().lower(), expires_at))
    conn.commit()
    conn.close()

def get_password_reset(reset_token):
    init_pending_db()
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("""
        SELECT clinic_email, personal_email, expires_at, attempts, reset_token FROM password_resets WHERE reset_token = ?
    """, (reset_token,))
    row = cursor.fetchone()
    conn.close()
    
    if not row:
        return None
        
    return {
        "clinic_email": row[0],
        "personal_email": row[1],
        "expires_at": datetime.datetime.fromisoformat(row[2]) if isinstance(row[2], str) else row[2],
        "attempts": row[3],
        "reset_token": row[4]
    }

def increment_reset_attempts(reset_token):
    init_pending_db()
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("""
        UPDATE password_resets
        SET attempts = attempts + 1
        WHERE reset_token = ?
    """, (reset_token,))
    conn.commit()
    
    cursor.execute("SELECT attempts FROM password_resets WHERE reset_token = ?", (reset_token,))
    row = cursor.fetchone()
    conn.close()
    return row[0] if row else 0

def delete_password_reset(reset_token):
    init_pending_db()
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("DELETE FROM password_resets WHERE reset_token = ?", (reset_token,))
    conn.commit()
    conn.close()

def blacklist_token(token, expires_at_datetime):
    init_pending_db()
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("""
        INSERT OR REPLACE INTO blacklisted_tokens (token, expires_at)
        VALUES (?, ?)
    """, (token, expires_at_datetime))
    conn.commit()
    conn.close()

def is_token_blacklisted(token):
    init_pending_db()
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT 1 FROM blacklisted_tokens WHERE token = ?", (token,))
    row = cursor.fetchone()
    conn.close()
    return row is not None

def log_email_sent(email):
    init_pending_db()
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("INSERT INTO email_sent_times (email, sent_at) VALUES (?, ?)", (email.strip().lower(), datetime.datetime.utcnow()))
    conn.commit()
    conn.close()

def get_email_sent_count_last_minute(email):
    init_pending_db()
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    one_minute_ago = datetime.datetime.utcnow() - datetime.timedelta(minutes=1)
    cursor.execute("SELECT COUNT(*) FROM email_sent_times WHERE email = ? AND sent_at > ?", (email.strip().lower(), one_minute_ago))
    count = cursor.fetchone()[0]
    conn.close()
    return count

def cleanup_expired_records():
    init_pending_db()
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    now = datetime.datetime.utcnow()
    cursor.execute("DELETE FROM pending_registrations WHERE expires_at < ?", (now,))
    cursor.execute("DELETE FROM password_resets WHERE expires_at < ?", (now,))
    cursor.execute("DELETE FROM blacklisted_tokens WHERE expires_at < ?", (now,))
    cursor.execute("DELETE FROM email_sent_times WHERE sent_at < ?", (now - datetime.timedelta(hours=1),))
    conn.commit()
    conn.close()
    logger.info("Cleaned up expired records from pending store.")
