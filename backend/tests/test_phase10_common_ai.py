from __future__ import annotations

from collections import Counter
from datetime import date, datetime, timedelta
import json
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from fastapi.routing import APIRoute
from fastapi.testclient import TestClient

from app.ai import ollama_provider
from tests.route_inventory import _application_routes
from tests.support import (
    TestingSessionLocal,
    active_main,
    add_patient,
    add_user,
    bearer_token,
    models,
    reset_database,
)


COMMON_PATHS = {
    ("GET", "/dashboard"),
    ("GET", "/api/dashboard"),
    ("GET", "/logs"),
    ("GET", "/api/records"),
    ("GET", "/api/appointment-conditions"),
    ("POST", "/api/appointment-conditions"),
    ("GET", "/api/ai/insights"),
    ("POST", "/api/ai/diagnosis"),
    ("POST", "/api/ai/chat"),
    ("GET", "/"),
}


class FakeAI:
    def __init__(self, content):
        self.content = content
        self.messages = None

    async def ainvoke(self, messages):
        self.messages = messages
        if isinstance(self.content, Exception):
            raise self.content
        return SimpleNamespace(content=self.content)


class Phase10CommonAITests(unittest.TestCase):
    def setUp(self):
        reset_database()
        self.client = TestClient(active_main.app)
        add_user(user_id="1", email="doctor@doctor.com", role="doctor")
        add_user(user_id="2", email="desk@receptionist.com", role="receptionist")
        add_patient(patient_id="123")
        self.doctor_headers = bearer_token("doctor@doctor.com")
        self.reception_headers = bearer_token("desk@receptionist.com")

    def test_routes_are_unique_owned_by_common_and_auth_is_preserved(self):
        routes = list(_application_routes(active_main.app.routes))
        registrations = [
            (method, route.path)
            for route in routes
            for method in route.methods or set()
        ]
        self.assertEqual([], [key for key, count in Counter(registrations).items() if count > 1])
        matched = [
            (method, route.path, route.endpoint.__module__)
            for route in routes
            for method in route.methods or set()
            if (method, route.path) in COMMON_PATHS
        ]
        self.assertEqual(COMMON_PATHS, {(method, path) for method, path, _ in matched})
        self.assertTrue(all(module == "app.routers.common" for _, _, module in matched))

        protected = (
            self.client.get("/dashboard"),
            self.client.get("/api/dashboard"),
            self.client.get("/logs"),
            self.client.get("/api/records"),
            self.client.get("/api/appointment-conditions"),
            self.client.post("/api/appointment-conditions", json={"name": "Exam"}),
            self.client.get("/api/ai/insights"),
            self.client.post(
                "/api/ai/diagnosis",
                json={"symptoms": "pain", "history": "none", "tooth_data": {}},
            ),
            self.client.post("/api/ai/chat", json={"messages": []}),
        )
        self.assertTrue(all(response.status_code == 401 for response in protected))
        self.assertEqual(200, self.client.get("/").status_code)

    def test_dashboard_logs_and_record_contracts(self):
        db = TestingSessionLocal()
        try:
            db.add_all(
                [
                    models.Appointment(
                        id="today", patient_id="123", date=date.today(),
                        time="09:30", status="pending",
                    ),
                    models.Record(
                        id="record-1", patient_id="123", tooth="11",
                        diagnosis="Caries",
                    ),
                    models.Log(
                        id="old", message="Old", created_at=datetime.utcnow() - timedelta(days=1)
                    ),
                    models.Log(id="new", message="New", created_at=datetime.utcnow()),
                ]
            )
            db.commit()
        finally:
            db.close()

        for path in ("/dashboard", "/api/dashboard"):
            response = self.client.get(path, headers=self.doctor_headers)
            self.assertEqual(
                {
                    "totalPatients": 1,
                    "todayAppointments": 1,
                    "activeRecords": 1,
                    "rating": 4.9,
                },
                response.json(),
            )
        logs = self.client.get("/logs", headers=self.doctor_headers).json()
        self.assertEqual(["new", "old"], [log["id"] for log in logs])
        self.assertEqual({"id", "message", "created_at"}, set(logs[0]))
        records = self.client.get("/api/records", headers=self.doctor_headers).json()
        self.assertEqual(
            {"id", "patient_id", "patient", "tooth", "type", "date", "doctor", "status", "size"},
            set(records[0]),
        )
        self.assertEqual("Caries", records[0]["type"])

    def test_records_preserve_clinical_report_fallback(self):
        db = TestingSessionLocal()
        try:
            db.add(
                models.ClinicalReport(
                    id="report-1", patient_id="123", doctor_id="1",
                    tooth_id="21", tooth_status="treated", status="finalized",
                    created_at=datetime(2026, 8, 9),
                )
            )
            db.commit()
        finally:
            db.close()
        records = self.client.get("/api/records", headers=self.doctor_headers).json()
        self.assertEqual("report-1", records[0]["id"])
        self.assertEqual("Tooth #21", records[0]["tooth"])
        self.assertEqual("treated", records[0]["type"])
        self.assertEqual("finalized", records[0]["status"])

    def test_appointment_condition_contracts_and_staff_security(self):
        empty = self.client.post(
            "/api/appointment-conditions", json={"name": "  "}, headers=self.doctor_headers
        )
        self.assertEqual(400, empty.status_code)
        self.assertEqual("Condition name cannot be empty", empty.json()["detail"])

        created = self.client.post(
            "/api/appointment-conditions",
            json={"name": "root canal"},
            headers=self.reception_headers,
        )
        self.assertEqual(200, created.status_code)
        self.assertEqual("Root Canal", created.json()["name"])
        duplicate = self.client.post(
            "/api/appointment-conditions",
            json={"name": "ROOT CANAL"},
            headers=self.doctor_headers,
        )
        self.assertEqual("Condition already exists", duplicate.json()["message"])
        listed = self.client.get(
            "/api/appointment-conditions", headers=self.doctor_headers
        )
        self.assertEqual([{"id": created.json()["id"], "name": "Root Canal"}], listed.json())

    def test_ai_success_contracts_prompts_and_markdown_json_parsing(self):
        insights_ai = FakeAI(
            "```json\n" + json.dumps({
                "summary": "Operational",
                "stats": {"patients": 1, "today_appointments": 0, "completed": 0, "pending": 0},
                "recommendations": ["A", "B", "C"],
            }) + "\n```"
        )
        diagnosis_ai = FakeAI(
            json.dumps({
                "diagnosis": "Assessment", "conditions": ["Condition"],
                "treatment_plan": ["Plan"],
            })
        )
        chat_ai = FakeAI("Helpful answer")
        clients = iter([insights_ai, diagnosis_ai, chat_ai])
        calls = []

        def factory(*, temperature=0.2, format=None):
            calls.append((temperature, format))
            return next(clients)

        with patch.object(active_main, "_get_ollama", side_effect=factory):
            insights = self.client.get("/api/ai/insights", headers=self.doctor_headers)
            diagnosis = self.client.post(
                "/api/ai/diagnosis",
                json={"symptoms": "pain", "history": "none", "tooth_data": {"11": "caries"}},
                headers=self.doctor_headers,
            )
            chat = self.client.post(
                "/api/ai/chat",
                json={"messages": [{"role": "user", "text": "Hello"}]},
                headers=self.doctor_headers,
            )
        self.assertEqual(200, insights.status_code)
        self.assertEqual({"summary", "stats", "recommendations"}, set(insights.json()))
        self.assertEqual({"diagnosis", "conditions", "treatment_plan"}, set(diagnosis.json()))
        self.assertEqual({"response": "Helpful answer"}, chat.json())
        self.assertEqual([(0.2, "json"), (0.1, "json"), (0.7, None)], calls)
        self.assertIn("dental clinic analytics assistant", insights_ai.messages[0].content)
        self.assertIn("experienced dental clinician assistant", diagnosis_ai.messages[0].content)
        self.assertIn("smart clinic receptionist and assistant", chat_ai.messages[0].content)

    def test_malformed_ai_fallbacks_and_chat_error_contract(self):
        with patch.object(active_main, "_get_ollama", return_value=FakeAI("not json")):
            insights = self.client.get("/api/ai/insights", headers=self.doctor_headers)
            diagnosis = self.client.post(
                "/api/ai/diagnosis",
                json={"symptoms": "pain", "history": "none", "tooth_data": {}},
                headers=self.doctor_headers,
            )
        self.assertEqual(
            "Clinic is operating normally. Continue monitoring pending appointments.",
            insights.json()["summary"],
        )
        self.assertEqual(["Non-specific irritation"], diagnosis.json()["conditions"])

        with patch.object(
            active_main, "_get_ollama", return_value=FakeAI(RuntimeError("offline"))
        ):
            chat = self.client.post(
                "/api/ai/chat", json={"messages": []}, headers=self.doctor_headers
            )
        self.assertEqual(500, chat.status_code)
        self.assertEqual("Failed to generate AI response", chat.json()["detail"])

    def test_provider_runtime_configuration(self):
        self.assertEqual("llama3.2:3b", ollama_provider.OLLAMA_MODEL)
        self.assertEqual("http://127.0.0.1:11434", ollama_provider.OLLAMA_BASE_URL)
        with patch.object(ollama_provider, "ChatOllama") as constructor:
            ollama_provider.create_ollama_client(temperature=0.7, format="json")
        constructor.assert_called_once_with(
            model="llama3.2:3b",
            base_url="http://127.0.0.1:11434",
            temperature=0.7,
            num_predict=1024,
            format="json",
        )

    def test_provider_uses_shared_runtime_configuration(self):
        from app.core import config

        self.assertIs(ollama_provider.OLLAMA_MODEL, config.OLLAMA_MODEL)
        self.assertIs(ollama_provider.OLLAMA_BASE_URL, config.OLLAMA_BASE_URL)


if __name__ == "__main__":
    unittest.main()
