from hashlib import sha256
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MIG = ROOT / "backend" / "migrations"
MAIN = (MIG / "033_admin_deleted_account_projection.sql").read_text().lower()
PRE = (MIG / "033_admin_deleted_account_projection_preflight.sql").read_text().lower()
VERIFY = (MIG / "033_admin_deleted_account_projection_verify.sql").read_text().lower()


def section(start, end):
    return MAIN.split(start, 1)[1].split(end, 1)[0]


def test_applied_destructive_migrations_are_unchanged():
    expected = {
        "031_admin_destructive_operations.sql": "d7033b94caf895d6836d3990810546bd32509a28de4c7581f2576da0f8ca7291",
        "032_format_clinic_include_lab_catalog.sql": "17555fd6231e56289cf4c088b6aa9877294a876a864dc51514d73c3d64a539e1",
    }
    for name, digest in expected.items():
        assert sha256((MIG / name).read_bytes()).hexdigest() == digest


def test_list_excludes_deleted_but_projects_pending_state_and_preserves_filters():
    body = section("create or replace function public.list_admin_users", "create or replace function public.get_admin_user")
    assert "u.deletion_status<>'deleted'" in body
    assert "'deletionstatus',u.deletion_status" in body
    assert "'deletedat',u.deleted_at" in body
    for value in ("p_search", "p_role", "p_is_active", "security.admin_user_actor()"):
        assert value in body
    assert "supabase_user_id" in body  # used only to return the safe isLinked boolean
    assert "'supabaseuserid'" not in body and "'personalemail'" not in body


def test_detail_hides_deleted_and_update_locks_every_non_active_deletion_state():
    detail = section("create or replace function public.get_admin_user", "create or replace function public.update_admin_user")
    update = section("create or replace function public.update_admin_user", "revoke all on function public.list_admin_users")
    assert "u.deletion_status<>'deleted'" in detail
    assert "'deletionstatus',u.deletion_status" in detail
    assert "v_target.deletion_status<>'active'" in update
    assert "admin_user_deletion_state_locked" in update
    assert "for update" in update


def test_migration_scope_does_not_touch_destructive_or_cross_feature_functions():
    for forbidden in (
        "prepare_admin_account_deletion", "finalize_admin_account_deletion", "format_clinic_data",
        "create_admin_managed_staff", "security.lab_actor", "notification_actor",
        "list_doctor_consultation_history", "get_appointments", "delete from public.users",
    ):
        assert forbidden not in MAIN
    assert MAIN.count("create or replace function") == 3
    assert "drop " not in MAIN and "alter table" not in MAIN and "create policy" not in MAIN


def test_preflight_is_read_only_and_verifier_has_exact_contract():
    for mutation in ("alter table", "create function", "delete from", "update public", "insert into", "truncate table"):
        assert mutation not in PRE
    for expected in ("deletion_state_counts", "pending_rows", "deleted_rows", "current_list_definition", "rpc_acls", "frontend.expected_projection"):
        assert expected in PRE
    assert "clean: migration 033 admin deleted-account projection matches current schema" in PRE
    assert "regexp_replace" in VERIFY
    assert "verification successful: admin deleted-account projection is safely contained" in VERIFY
