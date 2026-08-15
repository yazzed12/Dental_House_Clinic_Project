from hashlib import sha256
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MIG = ROOT / "backend" / "migrations"
M031_PATH = MIG / "031_admin_destructive_operations.sql"
MAIN = (MIG / "032_format_clinic_include_lab_catalog.sql").read_text().lower()
PRE = (MIG / "032_format_clinic_include_lab_catalog_preflight.sql").read_text().lower()
VERIFY = (MIG / "032_format_clinic_include_lab_catalog_verify.sql").read_text().lower()

FORMAT_TABLES = {
    "notifications", "financial_payment_allocations", "financial_charge_adjustments",
    "financial_payment_records", "consultation_procedures", "lab_payments",
    "consultation_lab_items", "clinical_reports", "patient_dental_state", "records",
    "logs", "consultations", "appointments", "patients", "lab_products", "labs",
}
PRESERVED = {
    "users", "clinic_settings", "clinic_procedures", "symptoms", "appointment_conditions",
}


def format_body():
    return MAIN.split("create or replace function public.format_clinic_data()", 1)[1].split("revoke all", 1)[0]


def test_migration_031_is_byte_for_byte_unchanged():
    assert sha256(M031_PATH.read_bytes()).hexdigest() == "d7033b94caf895d6836d3990810546bd32509a28de4c7581f2576da0f8ca7291"


def test_migration_032_replaces_only_format_and_preserves_hardening():
    body = format_body()
    assert MAIN.count("create or replace function") == 1
    assert body.count("truncate table") == 1
    assert "cascade" not in body
    assert "security definer" in body
    assert "set search_path=pg_catalog,pg_temp" in body
    assert "security.admin_user_actor()" in body
    assert "pg_advisory_xact_lock" in body
    for table in FORMAT_TABLES:
        assert f"public.{table}" in body
    for table in PRESERVED:
        assert f"public.{table}" not in body
    assert "auth.users" not in body
    assert "delete from" not in body and "update public.users" not in body


def test_account_management_and_other_architectures_are_not_touched():
    forbidden = (
        "prepare_admin_account_deletion", "finalize_admin_account_deletion",
        "create_admin_managed_staff", "admin-create-user", "deletion_status",
        "patient_dental_state doctor", "notification_recipient_actor",
        "consultation_history", "today_dashboard",
    )
    for token in forbidden:
        assert token not in MAIN
    assert "alter table" not in MAIN
    assert "create table" not in MAIN
    assert "drop " not in MAIN
    assert "create policy" not in MAIN
    assert "create trigger" not in MAIN


def test_lab_schema_and_doctor_only_authorization_remain_untouched():
    lab_foundation = (MIG / "022_lab_management_foundation.sql").read_text().lower()
    assert "security.lab_actor()" in lab_foundation
    assert "app_user.role in ('doctor', 'admin')" in lab_foundation
    assert "create table public.labs" in lab_foundation
    assert "create table public.lab_products" in lab_foundation
    assert "security.lab_actor" not in MAIN
    assert "drop" not in MAIN


def test_preflight_is_read_only_and_reports_fk_conflicts_and_counts():
    for mutation in ("alter table", "create function", "truncate table", "delete from", "update public", "insert into"):
        assert mutation not in PRE
    assert "format.current_definition" in PRE
    assert "format.current_truncate_statement" in PRE
    assert "format.lab_catalog_counts" in PRE
    assert "format.lab_catalog_foreign_keys" in PRE
    assert "format.unapproved_fk_children" in PRE
    assert "current schema'" in PRE
    assert "clean: migration 032 lab catalog format expansion matches current schema" in PRE


def test_acl_and_verifier_contracts_are_preserved():
    assert "revoke all on function public.format_clinic_data() from public" in MAIN
    assert "revoke execute on function public.format_clinic_data() from anon" in MAIN
    assert "grant execute on function public.format_clinic_data() to authenticated" in MAIN
    assert "regexp_replace" in VERIFY
    assert "has_function_privilege" in VERIFY
    assert "security.admin_user_actor()" in VERIFY
    assert "security.lab_actor()" in VERIFY
    assert "verification successful: clinic format clears lab data while preserving the system" in VERIFY
