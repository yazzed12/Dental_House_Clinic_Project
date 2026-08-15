"""
Check Supabase PostgreSQL Tables & Row Counts
Supports both direct DATABASE_URL (SQLAlchemy) and SUPABASE_URL + SUPABASE_KEY (Supabase REST API).
"""
import os
import requests
from dotenv import load_dotenv

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_KEY")
DATABASE_URL = os.getenv("DATABASE_URL")

def check_tables():
    print("\n==========================================")
    print("Checking Supabase Connection & Tables...")
    print("==========================================")

    # 1. Try Supabase REST API via SUPABASE_URL + SUPABASE_KEY
    if SUPABASE_URL and SUPABASE_KEY:
        print(f"Connecting to Supabase Project: {SUPABASE_URL}")
        tables_to_check = [
            "users", "clinic_settings", "patients", "symptoms", 
            "appointment_conditions", "appointments", "records", 
            "consultations", "notifications", "clinical_reports", "logs"
        ]
        
        headers = {
            "apikey": SUPABASE_KEY,
            "Authorization": f"Bearer {SUPABASE_KEY}",
            "Prefer": "count=exact"
        }

        found_any = False
        for table in tables_to_check:
            try:
                url = f"{SUPABASE_URL}/rest/v1/{table}?select=count"
                resp = requests.get(url, headers=headers)
                if resp.status_code == 200:
                    found_any = True
                    content_range = resp.headers.get("Content-Range", "")
                    count = content_range.split("/")[-1] if "/" in content_range else "0"
                    print(f"  [FOUND] Table '{table}': {count} rows")
                elif resp.status_code == 404:
                    print(f"  [MISSING] Table '{table}': Not created yet in Supabase (404)")
                else:
                    print(f"  [STATUS {resp.status_code}] Table '{table}': {resp.text}")
            except Exception as e:
                print(f"  [ERROR] Checking table '{table}': {e}")
                
        if not found_any:
            print("\nNotice: Tables do not exist yet in your Supabase database.")
            print("Please run the SQL Query in Supabase SQL Editor to create the tables!")

    # 2. Try direct SQLAlchemy PostgreSQL connection if DATABASE_URL is set
    if DATABASE_URL and not "sqlite" in DATABASE_URL:
        print("\n--- Direct Database Connection (SQLAlchemy) ---")
        try:
            from sqlalchemy import create_engine, inspect, text
            db_url = DATABASE_URL
            if db_url.startswith("postgres://"):
                db_url = db_url.replace("postgres://", "postgresql://", 1)
            engine = create_engine(db_url)
            inspector = inspect(engine)
            tables = inspector.get_table_names(schema="public")
            print(f"Found {len(tables)} tables in PostgreSQL schema:")
            with engine.connect() as conn:
                for table in sorted(tables):
                    res = conn.execute(text(f'SELECT COUNT(*) FROM public."{table}";'))
                    print(f"  - Table '{table}': {res.scalar()} rows")
        except Exception as err:
            print(f"SQLAlchemy DB connection note: {err}")

    print("==========================================\n")

if __name__ == "__main__":
    check_tables()
