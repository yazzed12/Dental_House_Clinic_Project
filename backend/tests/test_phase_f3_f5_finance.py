from __future__ import annotations

from datetime import date, datetime, timezone
from decimal import Decimal
import unittest

from fastapi.testclient import TestClient

from tests.support import TestingSessionLocal, active_main, add_patient, add_user, bearer_token, models, reset_database


class FinancialRuntimeTests(unittest.TestCase):
    def setUp(self):
        reset_database()
        self.client = TestClient(active_main.app)
        self.doctor_id = "10000000-0000-0000-0000-000000000001"
        self.patient_a = "20000000-0000-0000-0000-000000000001"
        self.patient_b = "20000000-0000-0000-0000-000000000002"
        add_user(user_id=self.doctor_id, email="doctor@example.test", role="doctor")
        add_user(user_id="10000000-0000-0000-0000-000000000002", email="desk@example.test", role="receptionist")
        add_patient(patient_id=self.patient_a)
        add_patient(patient_id=self.patient_b)
        self.headers = bearer_token("doctor@example.test")
        self.desk_headers = bearer_token("desk@example.test")

    def billed_consultation(self, patient_id, amount="400.00", name="Crown"):
        procedure = self.client.post("/api/clinic-procedures", json={"name": f"{name} {patient_id[-2:]}", "price": amount}, headers=self.headers).json()
        appointment_id = f"30000000-0000-0000-0000-{patient_id[-12:]}"
        db = TestingSessionLocal()
        try:
            db.add(models.Appointment(id=appointment_id, patient_id=patient_id, doctor_id=self.doctor_id, date=date.today(), time="09:00", status="pending"))
            db.commit()
        finally:
            db.close()
        saved = self.client.put(f"/api/consultations/{patient_id}/procedures", json={"version": 0, "selections": [{"procedureId": procedure["id"], "quantity": 1}]}, headers=self.headers)
        self.assertEqual(200, saved.status_code, saved.text)
        return saved.json()["consultationId"], procedure

    def add_payment(self, consultation_id, version, amount):
        response = self.client.post(f"/api/finance/consultations/{consultation_id}/payments", json={"billingVersion": version, "amount": amount, "paidAt": datetime.now(timezone.utc).isoformat()}, headers=self.headers)
        self.assertEqual(201, response.status_code, response.text)
        return response.json()

    def test_partial_later_payment_correction_overpayment_and_stale_conflict(self):
        consultation_id, _ = self.billed_consultation(self.patient_a)
        partial = self.add_payment(consultation_id, 0, "200.00")
        self.assertEqual("200.00", partial["outstandingTotal"])
        second = self.add_payment(consultation_id, 1, "100.00")
        self.assertEqual("100.00", second["outstandingTotal"])

        first = next(row for row in second["payments"] if row["amount"] == "200.00")
        corrected = self.client.post(f"/api/finance/payments/{first['paymentId']}/corrections", json={"billingVersion": 2, "expectedRevision": first["revision"], "amount": "150.00", "paidAt": first["paidAt"], "reason": "Corrected receipt"}, headers=self.headers)
        self.assertEqual(201, corrected.status_code, corrected.text)
        self.assertEqual("150.00", corrected.json()["outstandingTotal"])
        self.assertTrue(next(row for row in corrected.json()["payments"] if row["paymentId"] == first["paymentId"])["corrected"])

        stale = self.client.post(f"/api/finance/consultations/{consultation_id}/payments", json={"billingVersion": 2, "amount": "10.00", "paidAt": datetime.now(timezone.utc).isoformat()}, headers=self.headers)
        self.assertEqual(409, stale.status_code)
        extra = self.add_payment(consultation_id, 3, "300.00")
        self.assertEqual("150.00", extra["creditTotal"])

    def test_patient_aggregation_isolation_outstanding_and_safe_projection(self):
        consultation_a, _ = self.billed_consultation(self.patient_a, "100.00", "Crown")
        consultation_b, _ = self.billed_consultation(self.patient_b, "300.00", "Root")
        self.add_payment(consultation_a, 0, "50.00")
        history_a = self.client.get(f"/api/finance/patients/{self.patient_a}/history", headers=self.headers).json()
        self.assertEqual("50.00", history_a["outstandingTotal"])
        self.assertEqual({consultation_a}, {row["consultationId"] for row in history_a["consultations"]})
        payload_text = str(history_a).lower()
        for forbidden in ("sessionnote", "dental", "diagnosis", "report", "ai content", "toothdata"):
            self.assertNotIn(forbidden, payload_text)
        outstanding_b = self.client.get(f"/api/finance/patients/{self.patient_b}/outstanding", headers=self.headers).json()
        self.assertEqual("300.00", outstanding_b["totalOutstanding"])
        self.assertTrue(all(row["consultationId"] == consultation_b for row in outstanding_b["items"]))
        self.assertEqual(403, self.client.get("/api/finance/billing", headers=self.desk_headers).status_code)

    def test_procedure_correction_after_payment_preserves_snapshot_and_creates_credit(self):
        consultation_id, procedure = self.billed_consultation(self.patient_a, "100.00", "Bridge")
        selected = self.client.get(f"/api/consultations/{self.patient_a}/procedures", headers=self.headers).json()
        doubled = self.client.put(f"/api/consultations/{self.patient_a}/procedures", json={"version": selected["version"], "selections": [{"procedureId": procedure["id"], "quantity": 2}]}, headers=self.headers).json()
        paid = self.add_payment(consultation_id, 0, "100.00")
        corrected = self.client.put(f"/api/consultations/{self.patient_a}/procedures", json={"version": doubled["version"], "selections": []}, headers=self.headers)
        self.assertEqual(200, corrected.status_code, corrected.text)
        billing = self.client.get("/api/finance/billing", headers=self.headers).json()[0]
        self.assertEqual([], billing["procedures"])
        self.assertEqual("100.00", billing["creditTotal"])
        db = TestingSessionLocal()
        try:
            self.assertEqual(1, db.query(models.ConsultationProcedure).filter_by(consultation_id=consultation_id).count())
            self.assertEqual(1, db.query(models.FinancialChargeAdjustment).count())
            self.assertEqual("100.00", format(Decimal(db.query(models.ConsultationProcedure).one().unit_price_snapshot), ".2f"))
        finally:
            db.close()


if __name__ == "__main__":
    unittest.main()
