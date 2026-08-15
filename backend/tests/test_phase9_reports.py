from __future__ import annotations

from datetime import datetime
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import AsyncMock, patch

from fastapi.routing import APIRoute
from fastapi.testclient import TestClient

from tests.support import (
    TestingSessionLocal,
    active_main,
    add_patient,
    add_user,
    bearer_token,
    models,
    reset_database,
)


REPORT_PATHS = {
    ("POST", "/api/ai/generate-report"),
    ("POST", "/api/ai/humanize-report"),
    ("POST", "/api/reports"),
    ("GET", "/api/reports/patient/{patient_id}"),
    ("GET", "/api/reports/{report_id}/download"),
    ("PUT", "/api/reports/{report_id}"),
}


class Phase9ReportTests(unittest.TestCase):
    def setUp(self):
        reset_database()
        self.client = TestClient(active_main.app)
        add_user(user_id="1", email="admin@admin.com", role="admin")
        add_user(user_id="2", email="doctor@doctor.com", role="doctor")
        add_user(user_id="3", email="other@doctor.com", role="doctor")
        add_user(user_id="4", email="desk@receptionist.com", role="receptionist")
        add_patient(patient_id="123")
        self.admin_headers = bearer_token("admin@admin.com")
        self.doctor_headers = bearer_token("doctor@doctor.com")
        self.other_headers = bearer_token("other@doctor.com")
        self.reception_headers = bearer_token("desk@receptionist.com")
        self.pdf_directory = tempfile.TemporaryDirectory(prefix="phase9-pdf-")
        self.addCleanup(self.pdf_directory.cleanup)

        def fake_pdf(report, db):
            path = Path(self.pdf_directory.name) / f"report_{report.id}.pdf"
            path.write_bytes(b"%PDF-1.4\nphase9\n")
            report.pdf_path = str(path)
            db.commit()
            return str(path)

        pdf_patcher = patch.object(
            active_main, "generate_pdf_report_file", side_effect=fake_pdf
        )
        self.pdf_generator = pdf_patcher.start()
        self.addCleanup(pdf_patcher.stop)

    def _save(self, headers=None, **overrides):
        payload = {
            "patient_id": "123",
            "appointment_id": "appointment-7",
            "tooth_id": "11",
            "tooth_status": "caries",
            "symptoms": ["Sharp Pain"],
            "doctor_notes": "Private note",
            "ai_draft_report": "AI draft",
            "final_medical_report": "Approved final",
            "humanized_report": "Friendly explanation",
            "status": "finalized",
        }
        payload.update(overrides)
        return self.client.post(
            "/api/reports", json=payload, headers=headers or self.doctor_headers
        )

    def test_report_routes_are_unique_and_owned_by_modular_router(self):
        def application_routes(routes):
            for route in routes:
                if isinstance(route, APIRoute):
                    yield route
                    continue
                included_router = getattr(route, "original_router", None)
                if included_router is not None:
                    yield from application_routes(included_router.routes)

        matched = []
        for route in application_routes(active_main.app.routes):
            for method in route.methods or set():
                if (method, route.path) in REPORT_PATHS:
                    matched.append((method, route.path, route.endpoint.__module__))
        self.assertEqual(len(REPORT_PATHS), len(matched))
        self.assertEqual(REPORT_PATHS, {(m, p) for m, p, _ in matched})
        self.assertTrue(
            all(module == "app.routers.reports" for _, _, module in matched)
        )

    def test_all_report_routes_require_authentication(self):
        responses = (
            self.client.post("/api/ai/generate-report", json={}),
            self.client.post("/api/ai/humanize-report", json={"report": "x"}),
            self.client.post("/api/reports", json={"patient_id": "123"}),
            self.client.get("/api/reports/patient/123"),
            self.client.get("/api/reports/report-1/download"),
            self.client.put("/api/reports/report-1", json={}),
        )
        self.assertTrue(all(response.status_code == 401 for response in responses))

    def test_doctor_admin_write_rules_and_owner_update_are_preserved(self):
        denied = self._save(headers=self.reception_headers)
        self.assertEqual(403, denied.status_code)
        self.assertEqual("Insufficient permissions", denied.json()["detail"])

        doctor_saved = self._save()
        admin_saved = self._save(headers=self.admin_headers, tooth_id="21")
        self.assertEqual(200, doctor_saved.status_code)
        self.assertEqual(200, admin_saved.status_code)

        forbidden = self.client.put(
            f"/api/reports/{doctor_saved.json()['id']}",
            json={"status": "approved"},
            headers=self.other_headers,
        )
        self.assertEqual(403, forbidden.status_code)
        self.assertEqual(
            "Not authorized to edit this report", forbidden.json()["detail"]
        )

    def test_ai_humanize_save_contract_and_all_fields_are_preserved(self):
        with patch.object(
            active_main,
            "generate_clinical_report",
            new=AsyncMock(return_value="AI draft"),
        ):
            draft = self.client.post(
                "/api/ai/generate-report",
                json={"patient_id": "123"},
                headers=self.doctor_headers,
            )
        with patch.object(
            active_main,
            "humanize_report_ai",
            new=AsyncMock(return_value="Friendly explanation"),
        ):
            humanized = self.client.post(
                "/api/ai/humanize-report",
                json={"report": draft.json()["report"], "patient_name": "Patient"},
                headers=self.doctor_headers,
            )

        self.assertEqual({"status": "success", "report": "AI draft"}, draft.json())
        self.assertEqual(
            {"status": "success", "humanized_report": "Friendly explanation"},
            humanized.json(),
        )
        saved = self._save(
            ai_draft_report=draft.json()["report"],
            humanized_report=humanized.json()["humanized_report"],
        )
        self.assertEqual(200, saved.status_code, saved.text)
        self.assertEqual(
            {"id", "patient_id", "status", "tooth_id", "created_at"},
            set(saved.json()),
        )
        db = TestingSessionLocal()
        try:
            report = db.get(models.ClinicalReport, saved.json()["id"])
            self.assertEqual("appointment-7", report.appointment_id)
            self.assertEqual("caries", report.tooth_status)
            self.assertEqual(["Sharp Pain"], json.loads(report.symptoms))
            self.assertEqual("Private note", report.doctor_notes)
            self.assertEqual("AI draft", report.ai_draft_report)
            self.assertEqual("Approved final", report.final_medical_report)
            self.assertEqual("Friendly explanation", report.humanized_report)
            self.assertEqual("finalized", report.status)
            self.assertTrue(report.pdf_path)
        finally:
            db.close()
        self.assertEqual(1, self.pdf_generator.call_count)

    def test_patient_list_is_newest_first_and_supports_numeric_string_ids(self):
        db = TestingSessionLocal()
        try:
            db.add_all(
                [
                    models.ClinicalReport(
                        id="older", patient_id="123", doctor_id="2",
                        symptoms='["old"]', created_at=datetime(2026, 8, 1),
                    ),
                    models.ClinicalReport(
                        id="newer", patient_id="123", doctor_id="2",
                        symptoms='["new"]', pdf_path="existing.pdf",
                        created_at=datetime(2026, 8, 2),
                    ),
                ]
            )
            db.commit()
        finally:
            db.close()
        response = self.client.get(
            "/api/reports/patient/123", headers=self.reception_headers
        )
        self.assertEqual(200, response.status_code)
        self.assertEqual(["newer", "older"], [item["id"] for item in response.json()])
        self.assertEqual(["new"], response.json()[0]["symptoms"])
        self.assertEqual("/api/reports/newer/download", response.json()[0]["pdf_url"])

    def test_update_not_found_owner_fields_and_pdf_regeneration(self):
        missing = self.client.put(
            "/api/reports/missing",
            json={"status": "approved"},
            headers=self.doctor_headers,
        )
        self.assertEqual(404, missing.status_code)
        self.assertEqual("Report not found", missing.json()["detail"])

        saved = self._save()
        updated = self.client.put(
            f"/api/reports/{saved.json()['id']}",
            json={
                "humanized_report": "Updated friendly text",
                "symptoms": ["Sensitivity"],
                "tooth_status": "treated",
                "status": "approved",
            },
            headers=self.doctor_headers,
        )
        self.assertEqual(200, updated.status_code, updated.text)
        self.assertEqual({"id", "status", "updated_at"}, set(updated.json()))
        self.assertEqual(2, self.pdf_generator.call_count)

    def test_download_fallback_content_type_filename_and_missing_contract(self):
        missing = self.client.get(
            "/api/reports/missing/download", headers=self.doctor_headers
        )
        self.assertEqual(404, missing.status_code)
        self.assertEqual("Clinical report not found", missing.json()["detail"])

        saved = self._save()
        response = self.client.get(
            f"/api/reports/{saved.json()['id']}/download",
            headers=self.reception_headers,
        )
        self.assertEqual(200, response.status_code)
        self.assertEqual("application/pdf", response.headers["content-type"])
        self.assertIn("Clinical_Report_Characterization%20Patient_11.pdf", response.headers["content-disposition"])
        self.assertTrue(response.content.startswith(b"%PDF"))

    def test_consultation_history_remains_compatible(self):
        saved = self._save()
        history = self.client.get(
            "/api/doctor/consultations/history", headers=self.doctor_headers
        )
        self.assertEqual(200, history.status_code)
        self.assertEqual(saved.json()["id"], history.json()[0]["id"])
        self.assertEqual("Friendly explanation", history.json()[0]["humanized_report"])
        self.assertEqual("caries", history.json()[0]["tooth_status"])

    def test_pdf_failure_keeps_committed_report_retrievable(self):
        client = TestClient(active_main.app, raise_server_exceptions=False)
        self.pdf_generator.side_effect = RuntimeError("synthetic PDF failure")
        response = client.post(
            "/api/reports",
            json={
                "patient_id": "123",
                "tooth_id": "11",
                "final_medical_report": "Committed before PDF generation",
                "status": "approved",
            },
            headers=self.doctor_headers,
        )
        self.assertEqual(500, response.status_code)

        reports = client.get(
            "/api/reports/patient/123", headers=self.doctor_headers
        )
        self.assertEqual(200, reports.status_code)
        self.assertEqual(1, len(reports.json()))
        self.assertEqual(
            "Committed before PDF generation",
            reports.json()[0]["final_medical_report"],
        )


if __name__ == "__main__":
    unittest.main()
