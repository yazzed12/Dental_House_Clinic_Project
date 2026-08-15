from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
MIGRATION = ROOT / "backend" / "migrations" / "010_appointments_supabase_vertical_slice.sql"


class AppointmentsSqlContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.normalized = " ".join(cls.sql.lower().split())

    def test_read_contract_uses_auth_identity_and_safe_projection(self):
        self.assertIn("caller.supabase_user_id = auth.uid()", self.normalized)
        self.assertIn("caller.is_active = true", self.normalized)
        self.assertIn("caller.approved_at is not null", self.normalized)
        read_contract = self.normalized.split("create or replace function public.get_appointments()", 1)[1].split("create or replace function public.create_appointment", 1)[0]
        returns_table = read_contract.split("returns table (", 1)[1].split(") language plpgsql", 1)[0]
        self.assertIn('"date" date', returns_table)
        self.assertIn('"time" text', returns_table)
        self.assertIn('"type" text', returns_table)
        self.assertIn('"status" text', returns_table)
        self.assertIn('"condition" text', returns_table)
        self.assertNotIn(" time text", returns_table.replace('"time" text', ''))
        for forbidden in ("personal_email", "hashed_password", "password", "supabase_user_id uuid"):
            self.assertNotIn(forbidden, read_contract)

    def test_create_persists_uuid_patient_and_eligible_doctor(self):
        self.assertIn("p_patient_id uuid", self.normalized)
        self.assertIn("p_doctor_id uuid", self.normalized)
        self.assertIn("doctor.id = p_doctor_id", self.normalized)
        self.assertIn("doctor.role = 'doctor'", self.normalized)
        self.assertIn("doctor.is_active = true", self.normalized)
        self.assertIn("doctor.approved_at is not null", self.normalized)
        self.assertIn("doctor.supabase_user_id is not null", self.normalized)
        insert = self.normalized.split("insert into public.appointments (", 1)[1].split(") values (", 1)[0]
        self.assertIn("patient_id", insert)
        self.assertIn("doctor_id", insert)
        self.assertIn("security.normalize_appointment_type(p_type)::public.appointment_type", self.normalized)
        self.assertIn("security.normalize_appointment_status(p_status)::public.appointment_status", self.normalized)

    def test_domain_validation_and_role_contracts_are_server_authoritative(self):
        self.assertIn("v_caller_role not in ('doctor', 'receptionist', 'admin')", self.normalized)
        self.assertIn("v_caller_role not in ('doctor', 'admin')", self.normalized)
        self.assertIn("patient not found", self.normalized)
        self.assertIn("invalid appointment time", self.normalized)
        self.assertIn("unsupported appointment update field", self.normalized)
        self.assertIn("p_appointment_id is null or appointment.id = p_appointment_id", self.normalized)

    def test_status_contract_matches_production_enum_exactly(self):
        normalizer = self.normalized.split("create or replace function security.normalize_appointment_status", 1)[1].split("create or replace function security.appointment_projection", 1)[0]
        self.assertIn("v_status not in ('pending', 'confirmed', 'completed', 'cancelled', 'no_show')", normalizer)
        for unsupported in ("'arrived'", "'scheduled'", "'in_progress'"):
            self.assertNotIn(unsupported, normalizer)
        self.assertIn("set status = 'pending'", self.normalized)
        self.assertNotIn("set status = 'arrived'", self.normalized)
        self.assertNotIn("alter type appointment_status", self.normalized)

    def test_status_side_effects_and_controlled_delete_are_preserved(self):
        self.assertIn("insert into public.notifications", self.normalized)
        self.assertIn("'patient arrived'", self.normalized)
        self.assertIn("insert into public.logs", self.normalized)
        self.assertIn("appointment has clinical history and cannot be deleted", self.normalized)
        self.assertNotIn("grant delete on table public.appointments", self.normalized)

    def test_rls_and_minimum_privileges_are_fail_closed(self):
        self.assertIn("alter table public.appointments enable row level security", self.normalized)
        self.assertIn('drop policy if exists "allow clinic staff to manage appointments" on public.appointments', self.normalized)
        self.assertIn("revoke all on table public.appointments from anon", self.normalized)
        self.assertIn("revoke all on table public.appointments from authenticated", self.normalized)
        for name in (
            "get_appointments()",
            "create_appointment(uuid, uuid, date, text, text, text, text, text)",
            "update_appointment(uuid, jsonb)",
            "update_appointment_status(uuid, text)",
            "mark_appointment_arrived(uuid)",
            "finish_appointment_by_patient(uuid, uuid)",
            "delete_appointment(uuid)",
        ):
            self.assertIn(f"revoke all on function public.{name} from public", self.normalized)
            self.assertIn(f"revoke execute on function public.{name} from anon", self.normalized)
            self.assertIn(f"grant execute on function public.{name} to authenticated", self.normalized)
        self.assertNotIn("grant select on table public.users", self.normalized)


if __name__ == "__main__":
    unittest.main()
