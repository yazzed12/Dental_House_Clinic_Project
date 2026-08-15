from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
PREFLIGHT = (ROOT / 'migrations/023_consultation_history_lab_snapshots_preflight.sql').read_text()
MIGRATION = (ROOT / 'migrations/023_consultation_history_lab_snapshots.sql').read_text()
VERIFY = (ROOT / 'migrations/023_consultation_history_lab_snapshots_verify.sql').read_text()


def normalized(value):
    return re.sub(r'\s+', ' ', value.lower())


def test_preflight_is_read_only_and_reports_required_lab_history_assumptions():
    sql = normalized(PREFLIGHT)
    for marker in (
        'public.list_doctor_consultation_history()',
        'security.list_doctor_consultation_history_base()',
        'consultationswithlabnote', 'consultationlabitems',
        'brokenconsultationreferences', 'nullorblanksnapshots',
        'duplicateconsultationproducts', 'invalidquantities', 'invalidmoney',
        'clinicalreportlabcolumns', 'reportfunctionsreferencinglabobjects',
        'preflight clean:', 'preflight conflict:',
    ):
        assert marker in sql
    executable = re.sub(r'--[^\n]*', '', sql)
    assert not re.search(r'\b(insert|update|delete|alter|create|drop|grant|revoke|truncate)\b', executable)


def test_migration_replaces_only_contained_history_projection():
    sql = normalized(MIGRATION)
    assert 'security.list_doctor_consultation_history_base()' in sql
    assert "'labnote', consultation.lab_note" in sql
    assert "'labitems', coalesce(lab_snapshot.items, '[]'::jsonb)" in sql
    assert 'lab_item.consultation_id=consultation.id' in sql
    for source in (
        'lab_item.lab_name_snapshot', 'lab_item.product_name_snapshot',
        'lab_item.unit_price_snapshot', 'lab_item.quantity', 'lab_item.total_amount',
    ):
        assert source in sql
    assert 'public.labs ' not in sql
    assert 'public.lab_products ' not in sql
    assert 'current_price' not in sql
    for preserved in (
        "'clinicalfindings'", "'reportsnapshot'", "'snapshotversion'",
        "'reviewedat'", "'finalizedat'", 'order by item.ordinality',
    ):
        assert preserved in sql
    assert 'security definer' in sql
    assert 'set search_path = pg_catalog, pg_temp' in sql
    assert 'revoke all on function public.list_doctor_consultation_history() from public' in sql
    assert 'revoke execute on function public.list_doctor_consultation_history() from anon' in sql
    assert 'grant execute on function public.list_doctor_consultation_history() to authenticated' in sql
    mutation_body = re.sub(r'--[^\n]*', '', sql)
    assert not re.search(r'\b(insert|update|delete|alter table|create table|drop table|truncate)\b', mutation_body)
    assert 'clinical_reports add' not in sql
    assert 'finalize_clinical_report' not in sql


def test_verifier_proves_snapshot_sources_acl_and_medical_isolation():
    sql = normalized(VERIFY)
    for marker in (
        "'labnote'", "'labitems'", 'lab_name_snapshot', 'product_name_snapshot',
        'unit_price_snapshot', 'quantity', 'total_amount', r"\[\]",
        "'reportsnapshot'", "'snapshotversion'", "'reviewedat'", "'finalizedat'",
        'aclexplode', 'acl_entry.grantee=0', "has_function_privilege('anon'",
        "has_function_privilege('authenticated'", 'consultation_lab_items', 'lab_note',
    ):
        assert marker in sql
    assert "has_function_privilege('public'" not in sql
    assert 'public.labs ' in sql and 'public.lab_products ' in sql and 'current_price' in sql
    assert sql.rstrip().endswith(
        "select 'verification successful: consultation history lab snapshots are contained and medically isolated' as result;"
    )


def test_money_values_remain_numeric_json_expressions():
    sql = normalized(MIGRATION)
    assert "'unitprice', lab_item.unit_price_snapshot" in sql
    assert "'totalamount', lab_item.total_amount" in sql
    assert 'security.lab_money' not in sql
    assert 'to_char(' not in sql
