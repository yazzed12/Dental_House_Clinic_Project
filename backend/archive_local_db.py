"""
Archive local SQLite file clinic.db as clinic.db.bak
"""
import os
import shutil

DB_PATH = os.path.join(os.path.dirname(__file__), "clinic.db")
BAK_PATH = os.path.join(os.path.dirname(__file__), "clinic.db.bak")

def archive_local():
    if os.path.exists(DB_PATH):
        if os.path.exists(BAK_PATH):
            os.remove(BAK_PATH)
        shutil.move(DB_PATH, BAK_PATH)
        print("Local SQLite 'clinic.db' archived to 'clinic.db.bak'.")
    else:
        print("Local clinic.db does not exist or was already removed.")

if __name__ == "__main__":
    archive_local()
