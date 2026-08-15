import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "migrations" / "014_financial_system_supabase_vertical_slice.sql"
PREFLIGHT = ROOT / "migrations" / "014_financial_system_production_preflight.sql"
VERIFY = ROOT / "migrations" / "014_financial_system_supabase_vertical_slice_verify.sql"


class FinancialSystemSqlContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text()
        cls.normalized = re.sub(r"\s+", " ", cls.sql.lower())
        cls.preflight = PREFLIGHT.read_text().lower()
        cls.verify = VERIFY.read_text().lower()

    def function_body(self, schema, name):
        matches = re.findall(
            rf"create or replace function {schema}\.{name}\([\s\S]*?\$function\$;",
            self.sql,
            re.IGNORECASE,
        )
        self.assertTrue(matches, f"missing {schema}.{name}")
        return re.sub(r"\s+", " ", matches[-1].lower())

    def test_preflight_is_read_only_and_complete(self):
        for table in (
            "clinic_procedures", "consultation_procedures", "consultations",
            "financial_payment_records", "financial_payment_allocations",
            "financial_charge_adjustments",
        ):
            self.assertIn(table, self.preflight)
        for marker in (
            "information_schema.columns", "pg_constraint", "pg_enum",
            "relrowsecurity", "relforcerowsecurity", "pg_policies",
            "information_schema.table_privileges", "information_schema.triggers",
            "normalized_name", "effective_quantity", "allocated_total",
            "invalid_procedures_version_count", "invalid_billing_version_count",
        ):
            self.assertIn(marker, self.preflight)
        executable = re.sub(r"--[^\n]*", "", self.preflight)
        self.assertNotRegex(executable, r"\b(insert|update|delete|alter|drop|create|grant|revoke|truncate)\b")

    def test_actor_is_auth_uid_derived_active_approved_doctor_or_admin(self):
        body = self.function_body("security", "financial_actor")
        self.assertIn("supabase_user_id = auth.uid()", body)
        self.assertIn("is_active = true", body)
        self.assertIn("approved_at is not null", body)
        self.assertIn("role in ('doctor', 'admin')", body)
        self.assertNotIn("receptionist", body)

    def test_catalog_projection_and_management_are_controlled(self):
        listed = self.function_body("public", "list_clinic_procedures")
        self.assertIn("id uuid, name text, price text", listed)
        self.assertIn('"isactive" boolean', listed)
        self.assertIn("financial_money(procedure.price)", listed)
        self.assertIn("order by lower(btrim(procedure.name)), procedure.id", listed)
        created = self.function_body("public", "create_clinic_procedure")
        updated = self.function_body("public", "update_clinic_procedure")
        self.assertIn("pg_advisory_xact_lock", created)
        self.assertIn("procedure_duplicate", created)
        self.assertIn("for update", updated)
        self.assertNotIn("p_created_by", created + updated)

    def test_current_procedure_read_matches_consultation_appointment_containment(self):
        current = self.function_body("security", "current_financial_appointment")
        self.assertIn("appointment.status::text in ('pending', 'confirmed')", current)
        self.assertIn("appointment.doctor_id = p_actor_id", current)
        self.assertIn("appointment.id", current)
        read = self.function_body("public", "get_current_consultation_procedures")
        self.assertIn("financial_no_current_appointment", read)
        self.assertIn("'consultationid', null", read)
        self.assertIn("'items', '[]'::jsonb", read)
        self.assertIn("financial_effective_items", read)
        self.assertIn("procedures_version", read)

    def test_selection_write_preserves_snapshots_versions_and_adjustment_semantics(self):
        body = self.function_body("public", "save_current_consultation_procedures")
        self.assertIn("for update", body)
        self.assertIn("financial_duplicate_selection", body)
        self.assertIn("financial_invalid_quantity", body)
        self.assertIn("financial_inactive_procedure", body)
        self.assertIn("procedures_version <> p_version", body)
        self.assertIn("errcode = 'p3008'", body)
        self.assertIn("errcode = 'p3009'", body)
        self.assertIn("errcode = 'p3010'", body)
        self.assertIn("previous.procedure_name_snapshot", body)
        self.assertIn("previous.unit_price_snapshot", body)
        self.assertIn("procedure quantity corrected after payment history", body)
        self.assertIn("v_current_quantity - v_target_quantity", body)
        self.assertIn("rebalance_financial_allocations", body)
        self.assertIn("billing_version = billing_version + 1", body)
        self.assertIn("procedures_version = procedures_version + 1", body)

    def test_effective_items_and_billing_projection_preserve_decimal_contract(self):
        items = self.function_body("security", "financial_effective_items")
        self.assertIn("selection.quantity - coalesce(sum(adjustment.quantity_delta), 0)", items)
        self.assertIn("procedure_name_snapshot", items)
        self.assertIn("unit_price_snapshot", items)
        projection = self.function_body("security", "financial_billing_projection")
        for field in (
            "grosstotal", "adjustmenttotal", "effectivetotal", "billedtotal",
            "paidtotal", "balance", "outstandingtotal",
            "credittotal", "outstandingitems", "billingversion", "payments",
        ):
            self.assertIn(f"'{field}'", projection)
        self.assertIn("selection.quantity * selection.unit_price_snapshot", projection)
        self.assertIn("distinct on (payment.payment_id)", projection)

    def test_payment_revisions_and_allocations_follow_proven_algorithm(self):
        rebalance = self.function_body("security", "rebalance_financial_allocations")
        self.assertIn("distinct on (payment.payment_id)", rebalance)
        self.assertIn("order by latest.paid_at, latest.payment_id", rebalance)
        self.assertIn("least(v_available, v_amount)", rebalance)
        self.assertIn("revision_number + 1", rebalance)
        self.assertIn("automatic allocation rebalance", rebalance)
        add = self.function_body("public", "add_financial_payment")
        correction = self.function_body("public", "correct_financial_payment")
        self.assertIn("revision_number, amount", add)
        self.assertIn("v_current.revision_number + 1", correction)
        self.assertIn("financial_billing_version_conflict", add + correction)
        self.assertIn("financial_payment_revision_conflict", correction)
        self.assertIn("errcode = 'p3011'", add + correction)
        self.assertIn("errcode = 'p3012'", correction)
        self.assertIn("errcode = 'p3013'", add + correction)
        self.assertNotIn("overpayment", add + correction)

    def test_immutable_ledger_and_direct_table_containment_remain(self):
        for table in (
            "clinic_procedures", "consultation_procedures",
            "financial_payment_records", "financial_payment_allocations",
            "financial_charge_adjustments",
        ):
            self.assertIn(f"revoke all on table public.{table} from public, anon, authenticated", self.normalized)
            self.assertIn(f"alter table public.{table} enable row level security", self.normalized)
        self.assertIn("financial_payment_records_immutable", self.verify)
        self.assertIn("financial_payment_allocations_immutable", self.verify)
        self.assertIn("financial_charge_adjustments_immutable", self.verify)
        self.assertNotIn("service_role", self.normalized)

    def test_public_rpc_privileges_are_authenticated_only(self):
        signatures = (
            "list_clinic_procedures(boolean)",
            "create_clinic_procedure(text, numeric)",
            "update_clinic_procedure(uuid, jsonb)",
            "get_current_consultation_procedures(uuid)",
            "save_current_consultation_procedures(uuid, integer, jsonb)",
            "list_financial_billing()",
            "get_patient_financial_history(uuid)",
            "get_patient_financial_outstanding(uuid)",
            "get_patient_financial_summaries()",
            "add_financial_payment(uuid, integer, numeric, timestamptz)",
            "correct_financial_payment(uuid, integer, integer, numeric, timestamptz, text)",
        )
        for signature in signatures:
            self.assertIn(f"revoke all on function public.{signature} from public", self.normalized)
            self.assertIn(f"revoke execute on function public.{signature} from anon", self.normalized)
            self.assertIn(f"grant execute on function public.{signature} to authenticated", self.normalized)

    def test_ai_reports_and_history_are_out_of_scope(self):
        self.assertNotIn("ollama", self.normalized)
        self.assertNotIn("clinical_reports", self.normalized)
        self.assertNotIn("consultation_history", self.normalized)


if __name__ == "__main__":
    unittest.main()
