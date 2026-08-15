import sys
import os
from dotenv import load_dotenv
load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))

from database import SessionLocal
from sqlalchemy import text

def inspect():
    db = SessionLocal()
    try:
        tables = ["users", "patients", "appointments", "clinical_reports", "records", "consultations", "notifications"]
        for table in tables:
            res = db.execute(text(f"""
                SELECT column_name, column_default, data_type 
                FROM information_schema.columns 
                WHERE table_name = '{table}' AND column_name = 'id';
            """)).fetchone()
            if res:
                print(f"Table: {table:<20} | Column: {res[0]:<5} | Default: {str(res[1]):<30} | Type: {res[2]}")
            else:
                print(f"Table: {table:<20} | No 'id' column found")
    finally:
        db.close()

if __name__ == "__main__":
    inspect()
