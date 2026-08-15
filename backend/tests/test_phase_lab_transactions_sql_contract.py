import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "migrations" / "024_lab_transactions.sql"
PREFLIGHT = ROOT / "migrations" / "024_lab_transactions_preflight.sql"
VERIFY = ROOT / "migrations" / "024_lab_transactions_verify.sql"


class LabTransactionsSqlContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text()
        cls.normalized = re.sub(r"\s+", " ", cls.sql.lower())
        cls.preflight = PREFLIGHT.read_text().lower()
        cls.verify = VERIFY.read_text().lower()

    def body(self, name):
        matches = re.findall(
            rf"create or replace function public\.{name}\([\s\S]*?\$function\$;",
            self.sql,
            re.IGNORECASE,
        )
        self.assertTrue(matches, f"missing public.{name}")
        return re.sub(r"\s+", " ", matches[-1].lower())

    def test_preflight_is_read_only_and_consolidated(self):
        executable = re.sub(r"--[^\n]*", "", self.preflight)
        self.assertNotRegex(executable, r"\b(insert|update|delete|alter|drop|create|grant|revoke|truncate)\b")
        self.assertIn("select check_name,status,details", self.preflight)
        for marker in ("consultation_lab_items", "list_doctor_consultation_history",
                       "security.lab_actor", "archived_lab_items", "clinical_report.isolation",
                       "preflight.summary"):
            self.assertIn(marker, self.preflight)

    def test_no_duplicate_purchase_table_and_snapshot_only_projection(self):
        self.assertNotIn("create table public.lab_transactions", self.normalized)
        body = self.body("list_lab_transactions")
        for marker in ("item.lab_name_snapshot", "item.product_name_snapshot",
                       "item.unit_price_snapshot", "item.total_amount"):
            self.assertIn(marker, body)
        self.assertNotIn("public.lab_products", body)
        self.assertNotIn("current_price", body)
        self.assertIn("item.lab_id=p_lab_id", body)
        self.assertIn("'consultationid'", body)

    def test_transaction_date_is_immutable_consultation_timestamp_and_half_open(self):
        for name in ("list_lab_transactions", "get_lab_transaction_summary"):
            body = self.body(name)
            self.assertIn("consultation.created_at>=p_date_from", body)
            self.assertIn("consultation.created_at<p_date_to", body)
        self.assertNotIn("item.created_at>=p_date_from", self.body("list_lab_transactions"))

    def test_payment_money_ownership_and_append_only_corrections(self):
        self.assertIn("amount numeric(15,2) not null", self.normalized)
        self.assertIn("check (amount>0)", self.normalized)
        created = self.body("create_lab_payment")
        corrected = self.body("correct_lab_payment")
        self.assertIn("security.lab_actor()", created + corrected)
        self.assertNotIn("p_created_by", created + corrected)
        self.assertIn("v_actor_id", created + corrected)
        self.assertIn("revision_number+1", corrected.replace(" ", ""))
        self.assertIn("lab_payments_immutable", self.normalized)
        self.assertNotRegex(created + corrected, r"\b(delete|update)\s+(from\s+)?public\.lab_payments")

    def test_summary_uses_selected_lab_snapshot_totals_and_latest_payments(self):
        body = self.body("get_lab_transaction_summary")
        self.assertIn("sum(item.total_amount)", body)
        self.assertIn("item.lab_id=p_lab_id", body)
        self.assertIn("payment.lab_id=p_lab_id", body)
        self.assertIn("distinct on (payment.payment_id)", body)
        self.assertIn("v_purchases-v_paid", body.replace(" ", ""))

    def test_archived_history_is_readable_but_new_payment_is_blocked(self):
        for name in ("list_lab_transactions", "get_lab_transaction_summary", "list_lab_payments"):
            self.assertNotIn("and is_active", self.body(name))
        self.assertIn("where id=p_lab_id and is_active", self.body("create_lab_payment"))

    def test_hardened_rpc_and_table_privileges(self):
        self.assertIn("alter table public.lab_payments enable row level security", self.normalized)
        self.assertIn("revoke all on table public.lab_payments from public,anon,authenticated", self.normalized)
        for name in ("list_lab_transactions", "get_lab_transaction_summary", "list_lab_payments",
                     "create_lab_payment", "correct_lab_payment"):
            body = self.body(name)
            self.assertIn("security definer", body)
            self.assertIn("set search_path = pg_catalog, pg_temp", body)
            self.assertIn("security.lab_actor()", body)
        self.assertIn("acl_entry.grantee=0", self.verify)
        self.assertNotIn("has_function_privilege('public'", self.verify)

    def test_medical_report_isolation(self):
        for forbidden in ("alter table public.clinical_reports", "create or replace function public.finalize_clinical_report",
                          "create or replace function public.get_patient_clinical_reports"):
            self.assertNotIn(forbidden, self.normalized)
        self.assertIn("medical report function consumes lab transactions", self.verify)
        self.assertIn("verification successful: lab transactions foundation is contained and medically isolated", self.verify)


if __name__ == "__main__":
    unittest.main()
