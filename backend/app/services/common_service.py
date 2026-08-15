from collections.abc import Callable
from datetime import date
import json

from fastapi import HTTPException
from langchain_core.messages import AIMessage, HumanMessage, SystemMessage
from sqlalchemy.orm import Session

from app.repositories.common_repository import CommonRepository


class CommonService:
    def __init__(
        self,
        *,
        ai_factory: Callable,
        repository: CommonRepository | None = None,
        logger,
    ):
        self.repository = repository or CommonRepository()
        self.ai_factory = ai_factory
        self.logger = logger

    def dashboard(self, db: Session) -> dict:
        total_patients, today_appointments, active_records = (
            self.repository.dashboard_counts(db)
        )
        return {
            "totalPatients": total_patients,
            "todayAppointments": today_appointments,
            "activeRecords": active_records,
            "rating": 4.9,
        }

    def logs(self, db: Session) -> list[dict]:
        return [
            {
                "id": log.id,
                "message": log.message,
                "created_at": (
                    log.created_at.isoformat() + "Z" if log.created_at else None
                ),
            }
            for log in self.repository.recent_logs(db, 10)
        ]

    def records(self, db: Session) -> list[dict]:
        records = self.repository.records(db)
        if not records:
            reports = self.repository.reports_for_record_fallback(db)
            return [
                {
                    "id": report.id,
                    "patient_id": report.patient_id,
                    "patient": report.patient.name if report.patient else "Unknown",
                    "tooth": (
                        f"Tooth #{report.tooth_id}" if report.tooth_id else "General"
                    ),
                    "type": report.tooth_status or "Clinical Note",
                    "date": (
                        report.created_at.strftime("%Y-%m-%d")
                        if report.created_at
                        else "2026-08-03"
                    ),
                    "doctor": (
                        report.doctor.full_name or report.doctor.username
                        if report.doctor
                        else "DR Yehia El-Amir"
                    ),
                    "status": report.status or "Final",
                    "size": "N/A",
                }
                for report in reports
            ]
        return [
            {
                "id": record.id,
                "patient_id": record.patient_id,
                "patient": record.patient.name if record.patient else "Unknown",
                "tooth": record.tooth,
                "type": record.diagnosis,
                "date": "2026-05-10",
                "doctor": "Dr. API",
                "status": "Final",
                "size": "N/A",
            }
            for record in records
        ]

    def appointment_conditions(self, db: Session) -> list[dict]:
        return [
            {"id": str(condition.id), "name": condition.name}
            for condition in self.repository.active_appointment_conditions(db)
        ]

    def create_appointment_condition(self, db: Session, payload, user) -> dict:
        normalized_name = payload.name.strip().title()
        if not normalized_name:
            raise HTTPException(
                status_code=400, detail="Condition name cannot be empty"
            )
        existing = self.repository.appointment_condition_by_name(db, normalized_name)
        if existing:
            return {
                "id": str(existing.id),
                "name": existing.name,
                "message": "Condition already exists",
            }
        condition = self.repository.create_appointment_condition(
            db, normalized_name, user.id
        )
        return {"id": str(condition.id), "name": condition.name}

    async def insights(self, db: Session) -> dict:
        total_patients = 0
        today_appointments = []
        completed = 0
        pending = 0
        try:
            total_patients, today_appointments, recent_records = (
                self.repository.insight_context(db)
            )
            completed = len(
                [appointment for appointment in today_appointments if appointment.status == "Completed"]
            )
            pending = len(
                [appointment for appointment in today_appointments if appointment.status != "Completed"]
            )
            treatments = [record.diagnosis for record in recent_records]
            stats_context = {
                "total_patients": total_patients,
                "today_total": len(today_appointments),
                "completed": completed,
                "pending": pending,
                "recent_treatments": treatments[:5],
            }
            llm = self.ai_factory(temperature=0.2, format="json")
            system_prompt = """You are a dental clinic analytics assistant. Analyze the provided clinic statistics and return a valid JSON object with exactly these keys:
- "summary": a short professional summary string
- "stats": an object with keys "patients" (int), "today_appointments" (int), "completed" (int), "pending" (int)
- "recommendations": an array of exactly 3 short recommendation strings

Return ONLY valid JSON, no markdown, no explanation."""
            human_prompt = f"Analyze these clinic stats: {json.dumps(stats_context)}. Tone: Professional, operational, helpful."
            response = await llm.ainvoke(
                [SystemMessage(content=system_prompt), HumanMessage(content=human_prompt)]
            )
            return self._parse_json_response(response.content)
        except Exception as error:
            self.logger.error(f"AI Insights Error: {error}")
            return {
                "summary": "Clinic is operating normally. Continue monitoring pending appointments.",
                "stats": {
                    "patients": total_patients,
                    "today_appointments": len(today_appointments),
                    "completed": completed,
                    "pending": pending,
                },
                "recommendations": [
                    "Optimize scheduling for pending slots",
                    "Review recent treatment logs",
                    "Ensure all patient records are up to date",
                ],
            }

    async def diagnosis(self, payload) -> dict:
        try:
            llm = self.ai_factory(temperature=0.1, format="json")
            system_prompt = """You are an experienced dental clinician assistant. Analyze the provided patient symptoms, history, and tooth data to produce a clinical assessment.
Return a valid JSON object with exactly these keys:
- "diagnosis": a detailed diagnosis string
- "conditions": an array of identified condition strings
- "treatment_plan": an array of recommended treatment steps

Return ONLY valid JSON, no markdown, no explanation."""
            human_prompt = f"Perform a dental clinical diagnosis based on: Symptoms: {payload.symptoms}. History: {payload.history}. Tooth Data: {json.dumps(payload.tooth_data)}."
            response = await llm.ainvoke(
                [SystemMessage(content=system_prompt), HumanMessage(content=human_prompt)]
            )
            return self._parse_json_response(response.content)
        except Exception as error:
            self.logger.error(f"AI Diagnosis Error: {error}")
            return {
                "diagnosis": "Preliminary finding indicates potential irritation. Clinical exam required.",
                "conditions": ["Non-specific irritation"],
                "treatment_plan": ["Visual examination", "Sensitivity test"],
            }

    async def chat(self, db: Session, request) -> dict:
        try:
            total_patients, today_appointments, recent_logs = (
                self.repository.chat_context(db)
            )
            today_date = date.today()
            appointment_summary = ", ".join(
                [
                    f"{appointment.time}: {appointment.patient.name if appointment.patient else 'Unknown'}"
                    for appointment in today_appointments
                ]
            )
            log_summary = ", ".join([log.message for log in recent_logs])
            system_instruction = (
                f"You are a smart clinic receptionist and assistant. "
                f"Today is {today_date.strftime('%B %d, %Y')}. "
                f"Context: Total Patients: {total_patients}. "
                f"Today's Schedule: {appointment_summary if appointment_summary else 'No appointments'}. "
                f"Recent Activity: {log_summary if log_summary else 'No recent logs'}. "
                f"Keep responses operational, helpful, and short."
            )
            llm = self.ai_factory(temperature=0.7)
            messages = [SystemMessage(content=system_instruction)]
            for message in request.messages:
                if message.role == "ai":
                    messages.append(AIMessage(content=message.text))
                else:
                    messages.append(HumanMessage(content=message.text))
            response = await llm.ainvoke(messages)
            self.logger.info("AI Chat Action: Processed message with context. Status: OK")
            return {"response": response.content}
        except Exception as error:
            self.logger.error(f"AI Chat Error: {error}")
            raise HTTPException(status_code=500, detail="Failed to generate AI response")

    @staticmethod
    def health() -> dict:
        return {"status": "operational", "version": "2.0.0-enterprise"}

    @staticmethod
    def _parse_json_response(content: str) -> dict:
        raw = content.strip()
        if raw.startswith("```"):
            lines = raw.strip("`").strip().split("\n")
            if lines[0].lower() == "json":
                lines = lines[1:]
            raw = "\n".join(lines).strip()
        return json.loads(raw)
