from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
MIGRATION_010 = ROOT / "backend" / "migrations" / "010_appointments_supabase_vertical_slice.sql"
MIGRATION_011 = ROOT / "backend" / "migrations" / "011_appointments_enum_cast_hotfix.sql"


def normalized(path: Path) -> str:
    return " ".join(path.read_text(encoding="utf-8").lower().split())


class AppointmentEnumCastHotfixTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.migration_010 = normalized(MIGRATION_010)
        cls.migration_011 = normalized(MIGRATION_011)

    def test_clean_install_and_hotfix_create_paths_cast_both_enums(self):
        for sql in (self.migration_010, self.migration_011):
            self.assertIn(
                "security.normalize_appointment_type(p_type)::public.appointment_type",
                sql,
            )
            self.assertIn(
                "security.normalize_appointment_status(p_status)::public.appointment_status",
                sql,
            )

    def test_clean_install_and_hotfix_update_case_branches_are_enum_typed(self):
        for sql in (self.migration_010, self.migration_011):
            self.assertIn(
                "security.normalize_appointment_type(p_updates ->> 'type')::public.appointment_type",
                sql,
            )
            self.assertIn(
                "security.normalize_appointment_status(p_updates ->> 'status')::public.appointment_status",
                sql,
            )
            self.assertIn("else appointment.type end", sql)
            self.assertIn("else appointment.status end", sql)
            self.assertIn("set status = v_new_status::public.appointment_status", sql)

    def test_normalizers_still_define_the_verified_allowed_values(self):
        type_normalizer = self.migration_010.split(
            "create or replace function security.normalize_appointment_type", 1
        )[1].split(
            "create or replace function security.normalize_appointment_status", 1
        )[0]
        status_normalizer = self.migration_010.split(
            "create or replace function security.normalize_appointment_status", 1
        )[1].split(
            "create or replace function security.appointment_projection", 1
        )[0]
        for value in ("normal", "urgent", "follow_up", "consultation"):
            self.assertIn(f"'{value}'", type_normalizer)
        self.assertIn(
            "('pending', 'confirmed', 'completed', 'cancelled', 'no_show')",
            status_normalizer,
        )
        for unsupported in ("'arrived'", "'scheduled'", "'in_progress'"):
            self.assertNotIn(unsupported, status_normalizer)

    def test_arrived_action_and_enum_definitions_are_unchanged(self):
        self.assertIn("set status = 'pending'", self.migration_010)
        self.assertNotIn("set status = 'arrived'", self.migration_010)
        for sql in (self.migration_010, self.migration_011):
            self.assertNotIn("alter type", sql)
            self.assertNotIn("add value", sql)

    def test_011_is_narrow_and_replaces_only_affected_rpcs(self):
        self.assertIn("create or replace function public.create_appointment", self.migration_011)
        self.assertIn("create or replace function public.update_appointment(", self.migration_011)
        self.assertIn("create or replace function public.update_appointment_status", self.migration_011)
        self.assertNotIn("create or replace function public.get_appointments", self.migration_011)
        self.assertNotIn("create or replace function public.mark_appointment_arrived", self.migration_011)
        self.assertNotIn("alter table", self.migration_011)
        self.assertNotIn("create policy", self.migration_011)


if __name__ == "__main__":
    unittest.main()
