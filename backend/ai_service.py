"""
AI Service Layer — LangChain + Ollama Integration
Handles clinical report generation and humanization.
"""
from langchain_ollama import ChatOllama
from langchain_core.messages import SystemMessage, HumanMessage
import json, logging
import re

from app.core.config import OLLAMA_BASE_URL, OLLAMA_MODEL

logger = logging.getLogger(__name__)


def _get_llm(temperature=0.2):
    return ChatOllama(
        model=OLLAMA_MODEL,
        base_url=OLLAMA_BASE_URL,
        temperature=temperature,
        num_predict=1024,
        num_ctx=4096,
    )


_DOCTOR_PLACEHOLDER = re.compile(
    r"\[(?:your\s+name|doctor\s+name|name)\]|(?:reviewed\s+by\s*:\s*)(?:tbd|n/?a)\b",
    re.IGNORECASE,
)


def _append_authoritative_doctor_information(
    report: str, doctor: dict, report_date: str | None
) -> str:
    if _DOCTOR_PLACEHOLDER.search(report):
        raise ValueError("AI report contains an invalid Doctor identity placeholder")
    # A model-supplied identity section is never authoritative. Keep only the
    # clinical body and append server-owned identity fields below.
    body = re.split(
        r"^\s*##\s+Doctor Information\s*$", report, maxsplit=1,
        flags=re.IGNORECASE | re.MULTILINE,
    )[0].rstrip()
    doctor_name = (doctor.get("name") or "").strip()
    specialty = (doctor.get("specialty") or "").strip()
    lines = ["## Doctor Information"]
    if doctor_name:
        lines.append(f"- **Doctor Name:** {doctor_name}")
    if specialty:
        lines.append(f"- **Specialty:** {specialty}")
    if report_date:
        lines.append(f"- **Report Date:** {report_date}")
    if doctor_name:
        lines.append(f"- **Reviewed By:** {doctor_name}")
    return body + "\n\n" + "\n".join(lines)


async def generate_clinical_report(data: dict) -> str:
    """Generate one complete Markdown dental report from current consultation data."""
    try:
        llm = _get_llm(temperature=0.2)
        patient = data.get("patient") or {}
        procedures = data.get("performedProcedures") or []
        doctor = data.get("doctor") or {}
        clinic = doctor.get("clinic") or {}
        context = {
            "patient": {
                "name": patient.get("name"),
                "age": patient.get("age"),
                "gender": patient.get("gender"),
            },
            "examinationDate": data.get("examinationDate") or data.get("consultationDate"),
            "clinicalFindings": data.get("clinicalFindings") or [],
            "performedProcedures": [
                {"name": item.get("name"), "quantity": item.get("quantity")}
                for item in procedures
            ],
            "approvedPrescription": data.get("approvedPrescription"),
            "doctor": {
                "name": doctor.get("name"),
                "specialty": doctor.get("specialty") or doctor.get("specialization"),
                "clinic": {
                    key: clinic.get(key) for key in ("name", "email", "phone", "address")
                    if clinic.get(key)
                } or None,
            },
            "reportDate": data.get("reportDate"),
            "aiInstructions": data.get("aiInstructions"),
        }
        system_prompt = """You are an experienced dental clinical report writer. Write ONE complete professional Medical Dental Report in Markdown from the supplied consultation context.

Use exactly this structure:
# Clinical Dental Report
## Patient Information
- Name
- Age
- Gender
- Date of Examination
## Clinical Findings & Diagnosis
| FDI Tooth Number | Clinical Description | ICD-10 Code | Diagnosis |
| --- | --- | --- | --- |
## Treatment Plan
## Procedures Performed (only when authoritative performed procedures are supplied)
## Approved Prescription (only when an approved prescription is supplied)
## Clinical Summary / Impression

Represent every supplied consultation tooth once in the findings table. Professionally synthesize each Clinical Description from its supplied status, symptoms, and tooth note. Suggest a reasonable diagnosis, unverified ICD-10 candidate, and future treatment plan when supported. Never invent or change patient identity, FDI numbers, tooth status, symptoms, tooth notes, or performed procedures. Never invent radiographic or physical examination observations. Never present a proposed treatment as already performed. Keep authoritative procedures separate and do not invent tooth associations. NEVER print Patient ID, Procedure ID, internal UUIDs, or database identifiers. Do not include Date of Birth or a Consultation Note section.

The approvedPrescription value is immutable clinician-approved source data. When it is present, reproduce every supplied prescription item exactly and only organize or format it. Do not add or remove a medication. Do not change or infer brand, generic, strength, dosage form, route, dose, frequency, duration, or instructions. Do not add interactions, contraindications, side effects, pharmacological rationale, dosage advice, or postoperative medication advice. When approvedPrescription is null, do not create an Approved Prescription section and do not fabricate any prescription.

Do NOT output a Doctor Information section, Doctor Name, Specialty, Report Date, or Reviewed By; the authenticated server appends those fields. Never output identity placeholders. Return only the complete Markdown clinical body, with no JSON or surrounding commentary. The report remains a draft until Doctor approval."""
        clinical_context = {
            key: value for key, value in context.items()
            if key not in ("doctor", "reportDate")
        }
        human_prompt = "CURRENT AUTHORITATIVE CONSULTATION CONTEXT:\n" + json.dumps(
            clinical_context, ensure_ascii=False, separators=(",", ":")
        )
        response = await llm.ainvoke([
            SystemMessage(content=system_prompt),
            HumanMessage(content=human_prompt),
        ])
        return _append_authoritative_doctor_information(
            response.content, context["doctor"], context["reportDate"]
        )
    except Exception as e:
        logger.error(f"AI Report Generation Error: {e}")
        raise Exception(f"Failed to generate report: {str(e)}")


async def humanize_report(medical_report: str, patient_name: str = "Patient") -> str:
    """Convert a medical dental report into patient-friendly language."""
    try:
        llm = _get_llm(temperature=0.4)
        
        system_prompt = """You are a kind, patient-friendly medical communicator. Convert the provided dental clinical report into simple, easy-to-understand language that a patient with no medical background can read.

Rules:
- Use simple everyday words, not medical jargon
- Explain what was found, what it means, and what happens next
- Be reassuring but honest
- Use short sentences and bullet points
- Do NOT add any new diagnoses, treatments, or medical information not present in the original report
- Do NOT contradict the original report
- If an Approved Prescription section is present, preserve every medication, brand/generic name,
  strength, dosage form, route, dose, frequency, duration, and instruction exactly. Do not add
  medication advice, interactions, contraindications, side effects, or rationale.
- Address the patient directly ("You have..." not "The patient has...")
- Include sections: What We Found, What This Means, What We Recommend, What You Should Do At Home"""

        human_prompt = f"""Please convert this dental clinical report into simple patient-friendly language for {patient_name}:

---
{medical_report}
---

Write the simplified version now:"""

        messages = [SystemMessage(content=system_prompt), HumanMessage(content=human_prompt)]
        response = await llm.ainvoke(messages)
        return response.content
        
    except Exception as e:
        logger.error(f"Report Humanization Error: {e}")
        raise Exception(f"Failed to humanize report: {str(e)}")
