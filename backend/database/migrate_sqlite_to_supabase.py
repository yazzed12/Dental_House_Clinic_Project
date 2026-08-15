"""
Migrate SQLite Data to Supabase (PostgreSQL)
Handles UUID primary keys and foreign key mapping.
"""
import os
import json
import uuid
from dotenv import load_dotenv
from sqlalchemy import create_engine, text

load_dotenv()

BACKUP_PATH = os.path.join(os.path.dirname(__file__), "sqlite_backup.json")
DATABASE_URL = os.getenv("DATABASE_URL")

# Deterministic namespace for converting SQLite integer IDs to valid UUIDs
NAMESPACE = uuid.UUID('6ba7b810-9dad-11d1-80b4-00c04fd430c8')

def to_uuid(entity_type: str, val):
    if val is None:
        return None
    if isinstance(val, str) and len(val) == 36 and "-" in val:
        return val
    return str(uuid.uuid5(NAMESPACE, f"{entity_type}-{val}"))

def migrate():
    if not DATABASE_URL or "sqlite" in DATABASE_URL:
        print("[Error]: DATABASE_URL is not set to PostgreSQL in backend/.env")
        return

    if not os.path.exists(BACKUP_PATH):
        print(f"[Error]: Backup file {BACKUP_PATH} not found.")
        return

    with open(BACKUP_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)

    db_url = DATABASE_URL
    if db_url.startswith("postgres://"):
        db_url = db_url.replace("postgres://", "postgresql://", 1)

    engine = create_engine(db_url)
    
    with engine.connect() as conn:
        trans = conn.begin()
        try:
            print("Connected to Supabase PostgreSQL!")
            
            # Map SQLite integer IDs & FKs to UUIDs
            fk_mappings = {
                "users": ["id"],
                "patients": ["id"],
                "appointments": ["id", "patient_id", "doctor_id"],
                "notifications": ["id", "user_id"],
                "clinic_settings": ["id"],
                "records": ["id", "patient_id"],
                "logs": ["id", "doctor_id", "patient_id"],
                "consultations": ["id", "patient_id"],
                "clinical_reports": ["id", "patient_id", "doctor_id", "appointment_id"],
                "symptoms": ["id", "created_by"],
                "appointment_conditions": ["id", "created_by"],
            }

            table_order = [
                "users", "clinic_settings", "patients", "symptoms", 
                "appointment_conditions", "appointments", "records", 
                "consultations", "notifications", "clinical_reports", "logs"
            ]

            for table in table_order:
                rows = data.get(table, [])
                if not rows:
                    continue

                print(f"Migrating {len(rows)} records into '{table}'...")

                processed_rows = []
                for row in rows:
                    r = dict(row)
                    # Convert primary and foreign keys to UUID if required
                    for field in fk_mappings.get(table, []):
                        if field in r and r[field] is not None:
                            entity = field.replace("_id", "") if field.endswith("_id") else table[:-1]
                            r[field] = to_uuid(entity, r[field])
                    processed_rows.append(r)

                columns = list(processed_rows[0].keys())
                col_names = ", ".join([f'"{c}"' for c in columns])
                val_placeholders = ", ".join([f":{c}" for c in columns])

                insert_stmt = text(f'INSERT INTO public."{table}" ({col_names}) VALUES ({val_placeholders}) ON CONFLICT (id) DO NOTHING;')

                for r in processed_rows:
                    conn.execute(insert_stmt, r)

            trans.commit()
            print("\nMigration completed successfully! All data transferred to Supabase.")
        except Exception as e:
            trans.rollback()
            print(f"\nMigration failed: {e}")

if __name__ == "__main__":
    migrate()
