"""
Check appointment_type Enum values in PostgreSQL
"""
import sys
import os
from dotenv import load_dotenv
load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))

from database import SessionLocal
from sqlalchemy import text

def check():
    db = SessionLocal()
    try:
        res = db.execute(text("SELECT enumlabel FROM pg_enum JOIN pg_type ON pg_enum.enumtypid = pg_type.oid WHERE typname = 'appointment_type';")).fetchall()
        print("Allowed PostgreSQL enum values for appointment_type:", [e[0] for e in res])

        # Check existing appointment types in appointments table
        types = db.execute(text("SELECT type, count(*) FROM appointments GROUP BY type;")).fetchall()
        print("Current appointment types in DB:", types)
    finally:
        db.close()

if __name__ == "__main__":
    check()
