import sys
import os
from dotenv import load_dotenv
load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))

from database import SessionLocal
import models

def test_save_report():
    db = SessionLocal()
    try:
        patient = db.query(models.Patient).first()
        doctor = db.query(models.User).filter(models.User.role == "doctor").first()
        if not patient or not doctor:
            print("Required patient or doctor not found in DB")
            return

        report = models.ClinicalReport(
            patient_id=patient.id,
            doctor_id=doctor.id,
            tooth_id="16",
            tooth_status="treated",
            symptoms="[]",
            doctor_notes="Test notes",
            ai_draft_report="Test draft",
            final_medical_report="Test final",
            humanized_report="Test humanized",
            status="approved"
        )
        db.add(report)
        db.commit()
        print("Success! Report saved successfully.")
    except Exception as e:
        print("Error saving report:")
        import traceback
        traceback.print_exc()
    finally:
        db.close()

if __name__ == "__main__":
    test_save_report()
