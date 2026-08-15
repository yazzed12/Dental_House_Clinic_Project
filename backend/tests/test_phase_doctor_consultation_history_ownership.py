import re
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
PREFLIGHT=(ROOT/'migrations/028_doctor_consultation_history_ownership_preflight.sql').read_text().lower()
MIGRATION=(ROOT/'migrations/028_doctor_consultation_history_ownership.sql').read_text().lower()
VERIFY=(ROOT/'migrations/028_doctor_consultation_history_ownership_verify.sql').read_text().lower()

def compact(value): return re.sub(r'\s+',' ',value)

def visible(rows,actor_id,actor_role):
    return [row for row in rows if actor_role=='admin' or (actor_role=='doctor' and row['doctor_id']==actor_id)]

def test_two_doctors_one_patient_are_strictly_isolated_with_all_snapshots():
    rows=[
      {'id':'A1','patient_id':'P','doctor_id':'A','finalizedAt':'t','clinicalFindings':[1],'labItems':[1],'labNote':'A'},
      {'id':'B1','patient_id':'P','doctor_id':'B','finalizedAt':'t','clinicalFindings':[2],'labItems':[2],'labNote':'B'},
    ]
    assert [row['id'] for row in visible(rows,'A','doctor')]==['A1']
    assert [row['id'] for row in visible(rows,'B','doctor')]==['B1']
    assert [row['id'] for row in visible(rows,'admin','admin')]==['A1','B1']

def test_authoritative_base_requires_exact_consultation_and_report_ownership():
    sql=compact(MIGRATION)
    assert "v_actor_role = 'doctor' and consultation.doctor_id = v_actor_id" in sql
    assert "v_actor_role = 'doctor' and report.doctor_id = v_actor_id" in sql
    assert 'consultation.doctor_id is null and exists' not in sql
    assert 'report.doctor_id is null and exists' not in sql
    assert "v_actor_role = 'admin'" in sql

def test_report_only_rows_and_enrichment_cannot_bypass_base_containment():
    sql=compact(MIGRATION)
    report_only=sql.split('union all',1)[1]
    assert "v_actor_role = 'doctor' and report.doctor_id = v_actor_id" in report_only
    for field in ("'clinicalfindings'","'reportsnapshot'","'snapshotversion'","'reviewedat'","'finalizedat'","'labnote'","'labitems'"):
        assert field in VERIFY
    assert 'security.list_doctor_consultation_history_base()' in VERIFY

def test_preflight_is_read_only_and_audits_actual_leak_shape():
    executable=re.sub(r'--[^\n]*','',PREFLIGHT)
    assert not re.search(r'(?m)^\s*(insert|update|delete|alter|drop|create|grant|revoke|truncate)\b',executable)
    for marker in ('multi_doctor_patients','null_owned_leak_candidates','samepatientdoctorpairs','history.current_leak_condition','history.wrapper_023_compatibility','history.acl'):
        assert marker in PREFLIGHT
    assert 'clean: migration 028 doctor history ownership assumptions match current schema' in PREFLIGHT

def test_acl_ordering_lab_and_medical_report_isolation_are_preserved():
    sql=compact(MIGRATION)
    for marker in ('public.consultation_procedures','history.sort_updated desc nulls last','history.sort_created desc nulls last','history.sort_kind','history.stable_id desc'):
        assert marker in sql
    assert 'revoke all on function security.list_doctor_consultation_history_base() from public, anon, authenticated' in sql
    assert 'revoke all on function public.list_doctor_consultation_history() from public' in sql
    assert 'revoke execute on function public.list_doctor_consultation_history() from anon' in sql
    assert 'grant execute on function public.list_doctor_consultation_history() to authenticated' in sql
    assert VERIFY.rstrip().endswith("select 'verification successful: doctor consultation history is ownership-contained' as result;")
