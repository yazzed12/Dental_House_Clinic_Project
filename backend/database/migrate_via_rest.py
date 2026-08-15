"""
Migrate SQLite Data to Supabase via HTTP REST API
Refined Foreign Key Entity Mapping & Appointment Date Compatibility.
"""
import os
import json
import uuid
import requests
from dotenv import load_dotenv

load_dotenv()

BACKUP_PATH = os.path.join(os.path.dirname(__file__), "sqlite_backup.json")
SUPABASE_URL = os.getenv("SUPABASE_URL", "https://tmiezzketfifihreamir.supabase.co")
SUPABASE_KEY = os.getenv("SUPABASE_KEY", "sb_publishable_gBtkDmJAjv7kJEJgn1lVEw_dOUVPAh-")

NAMESPACE = uuid.UUID('6ba7b810-9dad-11d1-80b4-00c04fd430c8')

def to_uuid(entity_type: str, val):
    if val is None:
        return None
    if isinstance(val, str) and len(val) == 36 and "-" in val:
        return val
    # Map entity aliases correctly to matching table base names
    entity_map = {
        "doctor": "user",
        "created_by": "user",
        "user": "user",
        "patient": "patient",
        "appointment": "appointment"
    }
    base_entity = entity_map.get(entity_type, entity_type)
    return str(uuid.uuid5(NAMESPACE, f"{base_entity}-{val}"))

def migrate_rest():
    if not os.path.exists(BACKUP_PATH):
        print(f"[Error]: Backup file {BACKUP_PATH} not found.")
        return

    with open(BACKUP_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)

    headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "resolution=merge-duplicates"
    }

    # Field -> Entity Type mapping for UUID generation
    fk_field_types = {
        "id": None, # Will be set to table name singular
        "user_id": "user",
        "doctor_id": "user",
        "created_by": "user",
        "patient_id": "patient",
        "appointment_id": "appointment"
    }

    table_order = [
        "users", "clinic_settings", "patients", "symptoms", 
        "appointment_conditions", "appointments", "records", 
        "consultations", "notifications", "clinical_reports", "logs"
    ]

    print("\n==========================================")
    print("Starting REST Data Migration to Supabase (Refined)...")
    print("==========================================")

    total_inserted = 0

    for table in table_order:
        rows = data.get(table, [])
        if not rows:
            continue

        table_singular = table[:-1] if table.endswith("s") else table
        if table == "symptoms": table_singular = "symptom"
        if table == "clinical_reports": table_singular = "clinical_report"

        processed_rows = []
        for row in rows:
            r = dict(row)
            
            # 1. UUID mapping
            for field in list(r.keys()):
                if field == "id":
                    r["id"] = to_uuid(table_singular, r["id"])
                elif field in fk_field_types and fk_field_types[field]:
                    if r[field] is not None:
                        r[field] = to_uuid(fk_field_types[field], r[field])

            # 2. Patients normalization
            if table == "patients":
                if "gender" in r and r["gender"]:
                    r["gender"] = str(r["gender"]).lower()
                    if r["gender"] not in ["male", "female", "other", "unknown"]:
                        r["gender"] = "unknown"
                if "status" in r and r["status"]:
                    r["status"] = str(r["status"]).lower()
                    if r["status"] not in ["active", "inactive", "archived"]:
                        r["status"] = "active"

            # 3. Appointments normalization (populate date and appointment_date, time and appointment_time)
            if table == "appointments":
                val_date = r.get("date") or r.get("appointment_date") or "2026-08-03"
                val_time = r.get("time") or r.get("appointment_time") or "10:00"
                r["date"] = str(val_date)
                r["appointment_date"] = str(val_date)
                r["time"] = str(val_time)
                r["appointment_time"] = str(val_time)

                if "type" in r and r["type"]:
                    r["type"] = str(r["type"]).lower()
                    if r["type"] not in ["normal", "urgent", "follow_up", "consultation"]:
                        r["type"] = "normal"
                if "status" in r and r["status"]:
                    r["status"] = str(r["status"]).lower()
                    if r["status"] not in ["pending", "confirmed", "completed", "cancelled", "no_show"]:
                        r["status"] = "pending"

            # 4. Notifications normalization
            if table == "notifications":
                if "is_read" in r and "read" not in r:
                    r["read"] = 1 if r["is_read"] else 0

            processed_rows.append(r)

        url = f"{SUPABASE_URL}/rest/v1/{table}"
        
        chunk_size = 50
        inserted_count = 0
        for i in range(0, len(processed_rows), chunk_size):
            chunk = processed_rows[i:i + chunk_size]
            resp = requests.post(url, headers=headers, json=chunk)
            if resp.status_code in (200, 201):
                inserted_count += len(chunk)
            else:
                print(f"  [WARNING] Batch error on '{table}': HTTP {resp.status_code} - {resp.text[:150]}")

        print(f"  [MIGRATED] Table '{table}': {inserted_count}/{len(processed_rows)} rows inserted.")
        total_inserted += inserted_count

    print(f"\nMigration completed! Total records inserted: {total_inserted}")
    print("==========================================\n")

if __name__ == "__main__":
    migrate_rest()
