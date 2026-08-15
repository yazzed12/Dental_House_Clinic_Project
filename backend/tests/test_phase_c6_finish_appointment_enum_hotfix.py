from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
MIGRATION_010 = ROOT / "backend" / "migrations" / "010_appointments_supabase_vertical_slice.sql"
MIGRATION_015 = ROOT / "backend" / "migrations" / "015_finish_appointment_status_enum_hotfix.sql"
VERIFY_015 = ROOT / "backend" / "migrations" / "015_finish_appointment_status_enum_hotfix_verify.sql"


def normalized(path):
    return " ".join(path.read_text(encoding="utf-8").lower().split())


def finish_body(sql):
    return sql.split(
        "create or replace function public.finish_appointment_by_patient", 1
    )[1].split("$function$;", 1)[0]


class FinishAppointmentEnumHotfixTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = finish_body(normalized(MIGRATION_010))
        cls.hotfix_sql = normalized(MIGRATION_015)
        cls.hotfix = finish_body(cls.hotfix_sql)
        cls.verify = normalized(VERIFY_015)

    def test_clean_install_and_hotfix_accept_only_active_statuses(self):
        for body in (self.source, self.hotfix):
            self.assertIn("appointment.status::text in ('pending', 'confirmed')", body)
            self.assertNotIn("lower(appointment.status)", body)
            self.assertNotIn("'finished'", body)
            for inactive in ("completed", "cancelled", "no_show"):
                self.assertNotIn(f"'{inactive}'", body.split("order by", 1)[0])

    def test_finish_behavior_and_containment_are_preserved(self):
        for marker in (
            "v_caller_role not in ('doctor', 'admin')",
            "appointment.patient_id = p_patient_id",
            "p_appointment_id is null or appointment.id = p_appointment_id",
            "appointment.date = current_date",
            "appointment.doctor_id is not null",
            "v_caller_role = 'admin'",
            "appointment.doctor_id = v_caller_id",
            "order by appointment.appointment_time nulls last, appointment.time, appointment.id",
            "for update",
            "set status = 'completed'",
            "insert into public.logs",
            "jsonb_build_object('status', 'success', 'appointment_id', v_appointment_id)",
        ):
            self.assertIn(marker, self.hotfix)

    def test_hotfix_is_narrow_and_does_not_mutate_enum(self):
        self.assertEqual(self.hotfix_sql.count("create or replace function"), 1)
        self.assertNotIn("alter type", self.hotfix_sql)
        self.assertNotIn("add value", self.hotfix_sql)
        self.assertNotIn("create type", self.hotfix_sql)
        self.assertIn("revoke all on function public.finish_appointment_by_patient", self.hotfix_sql)
        self.assertIn("grant execute on function public.finish_appointment_by_patient", self.hotfix_sql)

    def test_verifier_checks_predicate_enum_contract_and_privileges(self):
        self.assertIn("appointment.status::text in (''pending'', ''confirmed'')", self.verify)
        self.assertIn("array['pending', 'confirmed', 'completed', 'cancelled', 'no_show']", self.verify)
        self.assertIn("information_schema.routine_privileges", self.verify)
        self.assertIn("grantee in ('public', 'anon')", self.verify)
        self.assertIn("grantee = 'authenticated'", self.verify)

    def test_doctor_admin_and_null_owner_contract_is_explicit(self):
        for body in (self.source, self.hotfix):
            self.assertIn("appointment.doctor_id is not null", body)
            self.assertIn("v_caller_role = 'admin' or appointment.doctor_id = v_caller_id", body)


if __name__ == "__main__":
    unittest.main()
