from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
PREFLIGHT = (ROOT / 'migrations/021_consultation_history_report_snapshot_preflight.sql').read_text()
MIGRATION = (ROOT / 'migrations/021_consultation_history_report_snapshot.sql').read_text()
VERIFY = (ROOT / 'migrations/021_consultation_history_report_snapshot_verify.sql').read_text()


def normalized(value):
    return re.sub(r'\s+', ' ', value.lower())


def test_preflight_is_read_only_and_checks_required_production_assumptions():
    sql = normalized(PREFLIGHT)
    assert 'report_only_rows' in sql
    assert 'snapshotsmissingnarrative' in sql
    for value in ('report_snapshot', 'snapshot_version', 'reviewed_at', 'finalized_at'):
        assert value in sql
    assert 'pg_get_functiondef' in sql
    assert 'aclexplode' in sql and 'grantee=0' in sql
    assert not re.search(r'\b(insert|update|delete|alter|create|drop|grant|revoke)\b', re.sub(r'--.*', '', sql))


def test_migration_only_projects_contained_report_snapshot_metadata():
    sql = normalized(MIGRATION)
    assert 'security.list_doctor_consultation_history_base()' in sql
    assert 'report.id = nullif(item.value' in sql and 'reportid' in sql
    for key in ("'reportsnapshot'", "'snapshotversion'", "'reviewedat'", "'finalizedat'"):
        assert key in sql
    assert 'security definer' in sql
    assert 'set search_path = pg_catalog, pg_temp' in sql
    assert 'revoke all on function public.list_doctor_consultation_history() from public' in sql
    assert 'grant execute on function public.list_doctor_consultation_history() to authenticated' in sql
    assert not re.search(r'\b(insert|update|delete|alter table|backfill)\b', re.sub(r'--.*', '', sql))
    assert 'create or replace function public.get_patient_clinical_reports' not in sql


def test_verifier_checks_contract_containment_and_postgres17_public_acl():
    sql = normalized(VERIFY)
    assert 'security.list_doctor_consultation_history_base()' in sql
    assert 'report.id = nullif(item.value' in sql and 'reportid' in sql
    assert 'aclexplode' in sql and 'acl_entry.grantee=0' in sql
    assert "has_function_privilege('public'" not in sql
    assert "has_function_privilege('anon'" in sql
    assert "has_function_privilege('authenticated'" in sql
    assert 'search_path=pg_catalog, pg_temp' in sql
    for value in ('report.report_snapshot', 'report.snapshot_version', 'report.reviewed_at', 'report.finalized_at'):
        assert value in sql
