from __future__ import annotations

import json
import unittest
from pathlib import Path
from unittest.mock import patch

import ai_service


class _CapturingLlm:
    def __init__(self, content="# Clinical Dental Report\n\n## Clinical Summary / Impression\nStable findings."):
        self.content = content
        self.calls = []

    async def ainvoke(self, messages):
        self.calls.append(messages)
        return type("Response", (), {"content": self.content})()


class WholeReportPromptTests(unittest.IsolatedAsyncioTestCase):
    def payload(self):
        return {
            "patient": {"id": "patient-1", "name": "Ada", "age": 36, "gender": "Female"},
            "examinationDate": "2026-08-14",
            "clinicalFindings": [
                {"toothId": "14", "toothStatus": "problem", "symptoms": ["Pain"], "toothNote": "Deep lesion"},
                {"toothId": "24", "toothStatus": "treated", "symptoms": ["Sensitivity"], "toothNote": "Stable restoration"},
            ],
            "performedProcedures": [{"id": "one", "procedureId": "p1", "name": "Cleaning", "quantity": 1}],
            "doctor": {"name": "Dr Noor", "specialty": "Dentistry", "clinic": {"name": "Clinic"}},
            "reportDate": "2026-08-14",
            "aiInstructions": "Keep concise",
            "consultationNote": "Internal only",
        }

    async def test_one_ollama_call_gets_deterministic_final_doctor_section(self):
        markdown = "# Clinical Dental Report\n\n## Patient Information\n\n- Name: Ada\n- Age: 36\n- Gender: Female\n\n## Procedures Performed\n\n- Cleaning × 1\n\n## Doctor Information\n- Reviewed By: Dr Differently Formatted"
        llm = _CapturingLlm(markdown)
        with patch.object(ai_service, "_get_llm", return_value=llm) as get_llm:
            result = await ai_service.generate_clinical_report(self.payload())
        self.assertIn("- **Doctor Name:** Dr Noor", result)
        self.assertIn("- **Specialty:** Dentistry", result)
        self.assertIn("- **Report Date:** 2026-08-14", result)
        self.assertTrue(result.endswith("- **Reviewed By:** Dr Noor"))
        self.assertNotIn("Dr Differently Formatted", result)
        self.assertNotIn("patient-1", result)
        self.assertNotIn("procedure-1", result)
        self.assertIn("Cleaning × 1", result)
        self.assertEqual(1, len(llm.calls))
        get_llm.assert_called_once_with(temperature=0.2)

    async def test_complete_multi_tooth_context_is_sent_to_the_single_prompt(self):
        llm = _CapturingLlm()
        with patch.object(ai_service, "_get_llm", return_value=llm):
            await ai_service.generate_clinical_report(self.payload())
        context = json.loads(llm.calls[0][1].content.split("\n", 1)[1])
        self.assertEqual(["14", "24"], [item["toothId"] for item in context["clinicalFindings"]])
        self.assertEqual(["Pain"], context["clinicalFindings"][0]["symptoms"])
        self.assertEqual({"name": "Cleaning", "quantity": 1}, context["performedProcedures"][0])
        self.assertNotIn("doctor", context)
        self.assertNotIn("reportDate", context)
        self.assertNotIn("id", context["patient"])
        self.assertNotIn("procedureId", context["performedProcedures"][0])
        self.assertNotIn("id", context["performedProcedures"][0])
        self.assertNotIn("consultationNote", context)

    async def test_prompt_requires_report_structure_safety_and_all_teeth(self):
        llm = _CapturingLlm()
        with patch.object(ai_service, "_get_llm", return_value=llm):
            await ai_service.generate_clinical_report(self.payload())
        system = llm.calls[0][0].content
        for required in (
            "# Clinical Dental Report", "## Patient Information",
            "| FDI Tooth Number | Clinical Description | ICD-10 Code | Diagnosis |",
            "## Treatment Plan", "## Procedures Performed",
            "## Clinical Summary / Impression",
            "Represent every supplied consultation tooth once",
            "NEVER print Patient ID, Procedure ID, internal UUIDs, or database identifiers",
            "Do not include Date of Birth or a Consultation Note section",
        ):
            self.assertIn(required, system)
        self.assertIn("Do NOT output a Doctor Information section", system)
        self.assertIn("the authenticated server appends those fields", system)
        self.assertIn("Never output identity placeholders", system)
        self.assertNotIn("\n- Patient ID", system)

    async def test_placeholder_is_rejected_but_free_form_doctor_section_is_replaced(self):
        placeholder = "# Clinical Dental Report\n- Reviewed By: [Your Name]"
        with patch.object(ai_service, "_get_llm", return_value=_CapturingLlm(placeholder)):
            with self.assertRaisesRegex(Exception, "Failed to generate report"):
                await ai_service.generate_clinical_report(self.payload())
        different = "# Clinical Dental Report\n\n## Doctor Information\n- Reviewed By: Dr Browser"
        with patch.object(ai_service, "_get_llm", return_value=_CapturingLlm(different)):
            result = await ai_service.generate_clinical_report(self.payload())
        self.assertNotIn("Dr Browser", result)
        self.assertTrue(result.endswith("- **Reviewed By:** Dr Noor"))

    async def test_missing_authoritative_doctor_name_requires_reviewed_by_omission(self):
        payload = self.payload()
        payload["doctor"] = {"name": None, "specialty": "Dentistry"}
        report = "# Clinical Dental Report\n\n## Doctor Information\n- Reviewed By: Dr Invented"
        with patch.object(ai_service, "_get_llm", return_value=_CapturingLlm(report)):
            result = await ai_service.generate_clinical_report(payload)
        self.assertNotIn("Dr Invented", result)
        self.assertNotIn("Doctor Name", result)
        self.assertNotIn("Reviewed By", result)
        self.assertIn("- **Specialty:** Dentistry", result)
        self.assertTrue(result.endswith("- **Report Date:** 2026-08-14"))

    async def test_no_per_tooth_json_or_composition_pipeline_remains(self):
        source = Path(ai_service.__file__).read_text(encoding="utf-8")
        self.assertNotIn("_validate_tooth_response", source)
        self.assertNotIn("_validate_composed_report", source)
        self.assertNotIn('format="json"', source)
        self.assertNotIn("REPAIR REQUIRED", source)
        self.assertNotIn("suggestedAssessment", source)


if __name__ == "__main__":
    unittest.main()
