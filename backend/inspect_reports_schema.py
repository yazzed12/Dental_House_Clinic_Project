import sys
import os
from dotenv import load_dotenv
load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))

from database import SessionLocal
from sqlalchemy import text

def inspect():
    db = SessionLocal()
    try:
        res = db.execute(text("SELECT column_name, is_nullable, data_type FROM information_schema.columns WHERE table_name = 'clinical_reports';")).fetchall()
        print("Columns in 'clinical_reports' table:")
        for r in res:
            print(f"  Column: {r[0]:<25} | Nullable: {r[1]:<5} | Type: {r[2]}")
    finally:
        db.close()

if __name__ == "__main__":
    inspect()
