"""
Export SQLite Data to JSON Backup
Reads all tables and data from clinic.db and exports them into sqlite_backup.json.
"""
import sqlite3
import json
import os

DB_PATH = os.path.join(os.path.dirname(__file__), "..", "clinic.db")
BACKUP_PATH = os.path.join(os.path.dirname(__file__), "sqlite_backup.json")

def export_data():
    if not os.path.exists(DB_PATH):
        print(f"Error: {DB_PATH} not found!")
        return

    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
    tables = [row[0] for row in cursor.fetchall() if row[0] != 'sqlite_sequence']

    full_backup = {}

    for table in tables:
        cursor.execute(f"SELECT * FROM {table}")
        rows = cursor.fetchall()
        full_backup[table] = [dict(row) for row in rows]
        print(f"Exported {len(rows)} records from table '{table}'")

    conn.close()

    with open(BACKUP_PATH, "w", encoding="utf-8") as f:
        json.dump(full_backup, f, indent=2, ensure_ascii=False)

    print(f"\nSuccessfully created backup file: {BACKUP_PATH}")

if __name__ == "__main__":
    export_data()
