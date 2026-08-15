"""
Cleanup Extra Doctor Accounts
Keeps 'dr__yehia@doctor.com' as the main doctor, reassigns appointments/reports/logs to Dr. Yehia,
and removes all other doctor accounts from SQLite and Supabase.
"""
import os
import json
import sqlite3
import requests
from dotenv import load_dotenv

load_dotenv()

DB_PATH = os.path.join(os.path.dirname(__file__), "..", "clinic.db")
SUPABASE_URL = os.getenv("SUPABASE_URL", "https://tmiezzketfifihreamir.supabase.co")
SUPABASE_KEY = os.getenv("SUPABASE_KEY", "sb_publishable_gBtkDmJAjv7kJEJgn1lVEw_dOUVPAh-")

headers = {
    "apikey": SUPABASE_KEY,
    "Authorization": f"Bearer {SUPABASE_KEY}",
    "Content-Type": "application/json"
}

MAIN_DOCTOR_EMAIL = "dr__yehia@doctor.com"

def cleanup():
    print("\n==========================================")
    print("Cleaning up extra doctor accounts...")
    print("==========================================")

    # 1. Clean local SQLite database
    if os.path.exists(DB_PATH):
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()

        cursor.execute("SELECT id FROM users WHERE email=?", (MAIN_DOCTOR_EMAIL,))
        main_doc = cursor.fetchone()
        if not main_doc:
            print(f"Error: {MAIN_DOCTOR_EMAIL} not found in SQLite users table!")
            return
        main_doc_id = main_doc[0]

        cursor.execute("SELECT id, email, username FROM users WHERE role='doctor' AND email!=?", (MAIN_DOCTOR_EMAIL,))
        other_doctors = cursor.fetchall()

        print(f"Found {len(other_doctors)} other doctor accounts to delete in SQLite.")

        for doc in other_doctors:
            doc_id, doc_email, doc_name = doc
            cursor.execute("UPDATE appointments SET doctor_id=? WHERE doctor_id=?", (main_doc_id, doc_id))
            cursor.execute("UPDATE clinical_reports SET doctor_id=? WHERE doctor_id=?", (main_doc_id, doc_id))
            cursor.execute("UPDATE logs SET doctor_id=? WHERE doctor_id=?", (main_doc_id, doc_id))
            cursor.execute("UPDATE symptoms SET created_by=? WHERE created_by=?", (main_doc_id, doc_id))
            cursor.execute("UPDATE appointment_conditions SET created_by=? WHERE created_by=?", (main_doc_id, doc_id))
            
            cursor.execute("DELETE FROM users WHERE id=?", (doc_id,))
            print(f"  - Deleted doctor in SQLite: {doc_email} ({doc_name})")

        conn.commit()
        conn.close()
        print("Local SQLite database cleanup complete!")

    # 2. Clean Supabase PostgreSQL database via REST API
    if SUPABASE_URL and SUPABASE_KEY:
        try:
            url = f"{SUPABASE_URL}/rest/v1/users?role=eq.doctor&select=id,email"
            res = requests.get(url, headers=headers)
            if res.status_code == 200:
                supa_users = res.json()
                main_supa_doc = next((u for u in supa_users if u["email"] == MAIN_DOCTOR_EMAIL), None)
                if main_supa_doc:
                    main_supa_id = main_supa_doc["id"]
                    other_supa_docs = [u for u in supa_users if u["email"] != MAIN_DOCTOR_EMAIL]
                    
                    print(f"Found {len(other_supa_docs)} other doctor accounts in Supabase.")
                    for u in other_supa_docs:
                        doc_id = u["id"]
                        requests.patch(f"{SUPABASE_URL}/rest/v1/appointments?doctor_id=eq.{doc_id}", headers=headers, json={"doctor_id": main_supa_id})
                        requests.patch(f"{SUPABASE_URL}/rest/v1/clinical_reports?doctor_id=eq.{doc_id}", headers=headers, json={"doctor_id": main_supa_id})
                        requests.patch(f"{SUPABASE_URL}/rest/v1/logs?doctor_id=eq.{doc_id}", headers=headers, json={"doctor_id": main_supa_id})
                        
                        del_res = requests.delete(f"{SUPABASE_URL}/rest/v1/users?id=eq.{doc_id}", headers=headers)
                        print(f"  - Deleted doctor in Supabase: {u['email']} (Status: {del_res.status_code})")

            print("Supabase database cleanup complete!")
        except Exception as err:
            print(f"Supabase cleanup error: {err}")

    print("\nDoctor accounts cleanup finished! Only 'dr__yehia@doctor.com' remains as active doctor.")
    print("==========================================\n")

if __name__ == "__main__":
    cleanup()
