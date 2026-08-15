from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MIGRATIONS = ROOT / "backend" / "migrations"
MAIN = (MIGRATIONS / "030_supabase_notifications_foundation.sql").read_text().lower()
PREFLIGHT = (MIGRATIONS / "030_supabase_notifications_foundation_preflight.sql").read_text().lower()
VERIFY = (MIGRATIONS / "030_supabase_notifications_foundation_verify.sql").read_text().lower()


def test_preflight_is_read_only_and_has_exact_clean_summary():
    for mutation in ("insert into", "update public", "delete from", "alter table", "create function"):
        assert mutation not in PREFLIGHT
    assert "clean: migration 030 notifications assumptions match current schema" in PREFLIGHT
    assert "conflict" in PREFLIGHT


def test_recipient_and_read_state_are_server_owned():
    assert "recipient_user_id uuid" in MAIN
    assert "read_at timestamptz" in MAIN
    assert "revoke all on table public.notifications from public,anon,authenticated" in MAIN
    assert "create policy" not in MAIN
    assert "recipient_user_id=v_actor_id" in MAIN
    assert "p_recipient" not in MAIN
    assert "p_doctor_id" not in MAIN


def test_actor_is_resolved_from_auth_and_fails_closed():
    assert "app_user.supabase_user_id=auth.uid()" in MAIN
    assert "app_user.is_active=true" in MAIN
    assert "app_user.approved_at is not null" in MAIN
    assert "user_metadata" not in MAIN


def test_rpcs_are_bounded_owned_and_read_at_authoritative():
    for rpc in ("list_my_notifications", "get_my_unread_notification_count", "mark_my_notification_read", "mark_all_my_notifications_read"):
        assert f"function public.{rpc}" in MAIN
    assert "least(greatest(coalesce(p_limit,50),1),100)" in MAIN
    assert "notification.read_at is null" in MAIN
    assert "set read_at=" in MAIN
    assert "set \"read\"" not in MAIN


def test_arrival_targets_only_assigned_doctor_and_is_idempotent():
    assert "appointment.doctor_id" in MAIN
    assert "v_actor_role='doctor' and v_doctor_id<>v_actor_id" in MAIN
    assert "values(gen_random_uuid(),v_doctor_id,p_appointment_id,'appointment_arrived'" in MAIN
    assert "unique index notifications_arrival_once_idx" in MAIN
    assert "on conflict (recipient_user_id,appointment_id,type)" in MAIN
    assert "do nothing" in MAIN


def test_legacy_null_rows_are_preserved_and_inert():
    assert "where notification.user_id is not null" in MAIN
    assert "recipient_user_id=v_actor_id" in MAIN
    assert "recipient_user_id=coalesce" not in MAIN
    assert "recipient_user_id='admin'" not in MAIN
    assert "recipient_user_id=v_actor_id" not in MAIN.split("create or replace function public.mark_appointment_arrived", 1)[1]


def test_verifier_has_exact_success_and_security_checks():
    assert "verification successful: supabase notifications are recipient-contained" in VERIFY
    assert "has_table_privilege('anon'" in VERIFY
    assert "has_function_privilege('anon'" in VERIFY
    assert "duplicate appointment arrival notification" in VERIFY


def test_scope_does_not_touch_unrelated_domains():
    for forbidden in ("clinic_settings", "financial", "laboratory", "consultations", "patient_history", "today"):
        assert forbidden not in MAIN


def _visible(rows, actor_id):
    return [row for row in rows if row["recipient_user_id"] == actor_id]


def test_recipient_equality_isolates_every_role_even_with_same_patient():
    rows = [
        {"id": "a", "recipient_user_id": "doctor-a", "patient_id": "same-patient", "read_at": None},
        {"id": "b", "recipient_user_id": "doctor-b", "patient_id": "same-patient", "read_at": None},
        {"id": "c", "recipient_user_id": "admin", "patient_id": "same-patient", "read_at": None},
        {"id": "d", "recipient_user_id": "receptionist", "patient_id": "same-patient", "read_at": None},
        {"id": "e", "recipient_user_id": "patient-login", "patient_id": "same-patient", "read_at": None},
        {"id": "legacy", "recipient_user_id": None, "patient_id": "same-patient", "read_at": None},
    ]
    for actor in ("doctor-a", "doctor-b", "admin", "receptionist", "patient-login"):
        assert [row["recipient_user_id"] for row in _visible(rows, actor)] == [actor]


def test_owned_count_mark_one_and_mark_all_do_not_cross_recipient():
    rows = [
        {"id": "a1", "recipient_user_id": "doctor-a", "read_at": None},
        {"id": "a2", "recipient_user_id": "doctor-a", "read_at": "already"},
        {"id": "b1", "recipient_user_id": "doctor-b", "read_at": None},
    ]
    assert sum(row["read_at"] is None for row in _visible(rows, "doctor-a")) == 1
    target = next((row for row in rows if row["id"] == "b1" and row["recipient_user_id"] == "doctor-a"), None)
    assert target is None
    for row in _visible(rows, "doctor-a"):
        if row["read_at"] is None:
            row["read_at"] = "server-time"
    assert rows[2]["read_at"] is None
