import re
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
MIGRATION = ROOT / 'backend/migrations/018_clinical_session_persistence.sql'
PREFLIGHT = ROOT / 'backend/migrations/018_clinical_session_persistence_preflight.sql'
VERIFY = ROOT / 'backend/migrations/018_clinical_session_persistence_verify.sql'

class ClinicalSessionPersistenceContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = ' '.join(MIGRATION.read_text().lower().split())
        cls.preflight = PREFLIGHT.read_text().lower()
        cls.verify = ' '.join(VERIFY.read_text().lower().split())

    def test_preflight_is_read_only(self):
        executable = re.sub(r'--[^\n]*', '', self.preflight)
        self.assertNotRegex(executable, r'\b(insert|update|delete|alter|drop|create|grant|revoke|truncate)\b')
        for marker in ('consultations', 'clinical_reports', 'logs', 'duplicate', 'constraint'):
            self.assertIn(marker, self.preflight)

    def test_symptoms_are_nullable_snapshot_and_saved_atomically(self):
        self.assertIn('add column symptoms_snapshot jsonb null', self.sql)
        self.assertIn("jsonb_typeof(symptoms_snapshot) = 'array'", self.sql)
        self.assertIn('p_symptoms_supplied boolean', self.sql)
        self.assertIn('set symptoms_snapshot = p_symptoms_snapshot', self.sql)
        self.assertIn('public.save_current_consultation(', self.sql)

    def test_only_eight_parameter_consultation_save_is_browser_executable(self):
        eight = 'public.save_current_consultation(uuid, jsonb, integer, integer, text, boolean, jsonb, boolean)'
        six = 'public.save_current_consultation(uuid, jsonb, integer, integer, text, boolean)'
        self.assertIn(f'grant execute on function {eight} to authenticated', self.sql)
        self.assertIn(f'revoke execute on function {six} from authenticated', self.sql)
        self.assertIn(f'revoke execute on function {eight} from anon', self.sql)
        self.assertIn(f'revoke execute on function {six} from anon', self.sql)
        for signature in (eight, six):
            self.assertIn(f'revoke all on function {signature} from public', self.sql)

        self.assertIn(
            'to_regprocedure(\'public.save_current_consultation(uuid,jsonb,integer,integer,text,boolean,jsonb,boolean)\')',
            self.verify,
        )
        self.assertIn(
            'to_regprocedure(\'public.save_current_consultation(uuid,jsonb,integer,integer,text,boolean)\')',
            self.verify,
        )
        self.assertNotIn('uuid,jsonb,integer,text,integer,jsonb,boolean', self.verify)
        self.assertIn("has_function_privilege('authenticated', v_save_eight, 'execute')", self.verify)
        self.assertIn("has_function_privilege('authenticated', v_save_six, 'execute')", self.verify)
        self.assertIn('privilege.grantee = 0', self.verify)

    def test_verifier_checks_report_schema_policy_and_table_containment(self):
        for marker in (
            "column_name='symptoms_snapshot' and data_type='jsonb'",
            "column_name='consultation_id' and data_type='uuid'",
            'constraint_record.contype = \'f\'',
            "policyname in ('allow clinic staff full access', 'allow initial data migration')",
            "grantee = 'authenticated'",
        ):
            self.assertIn(marker, self.verify)

    def test_reports_are_consultation_linked_authorized_and_logged(self):
        for marker in ('add column consultation_id uuid null', 'security.clinical_report_actor()',
                       'insert into public.clinical_reports', 'insert into public.logs',
                       'p_symptoms is distinct from v_consultation.symptoms_snapshot'):
            self.assertIn(marker, self.sql)
        self.assertIn("app_user.role in ('doctor', 'admin')", self.sql)

    def test_report_write_surface_is_rpc_only(self):
        self.assertIn('drop policy if exists "allow clinic staff full access" on public.clinical_reports', self.sql)
        self.assertIn('drop policy if exists "allow initial data migration" on public.clinical_reports', self.sql)
        self.assertIn('revoke all on table public.clinical_reports from public, anon, authenticated', self.sql)
        self.assertIn('grant execute on function public.save_clinical_report', self.sql)
        self.assertIn('grant execute on function public.update_clinical_report', self.sql)

    def test_history_prefers_snapshot_and_falls_back_only_for_legacy_null(self):
        self.assertIn('when consultation.symptoms_snapshot is not null then consultation.symptoms_snapshot', self.sql)
        self.assertIn('security.consultation_history_json_array(consultation.report_symptoms)', self.sql)
        self.assertIn("'reportonly', true", self.sql)
        self.assertIn("select lower(pg_get_functiondef(", self.verify)
        self.assertIn("position('when consultation.symptoms_snapshot is not null' in v_history)", self.verify)
        self.assertIn("position('then consultation.symptoms_snapshot' in v_history)", self.verify)
        self.assertIn("position('else security.consultation_history_json_array(consultation.report_symptoms)' in v_history)", self.verify)

    def test_no_ai_transport_or_enum_schema_change(self):
        self.assertNotRegex(self.sql, r'\b(ollama|langchain|alter type)\b')
        self.assertIn('verification successful: clinical session persistence is contained', self.verify)

if __name__ == '__main__':
    unittest.main()
