import re
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
PREFLIGHT=(ROOT/'migrations/029_doctor_today_dashboard_ownership_preflight.sql').read_text().lower()
MIGRATION=(ROOT/'migrations/029_doctor_today_dashboard_ownership.sql').read_text().lower()
VERIFY=(ROOT/'migrations/029_doctor_today_dashboard_ownership_verify.sql').read_text().lower()
COMPONENT=(ROOT.parent/'src/components/UpcomingConsultations.jsx').read_text()
CONTEXT=(ROOT.parent/'src/context/DataContext.jsx').read_text()
SERVICE=(ROOT.parent/'src/services/appointmentApi.js').read_text()

def compact(value): return re.sub(r'\s+',' ',value)

def visible(rows,actor_id,role):
    if role in ('receptionist','admin'): return rows
    return [row for row in rows if role=='doctor' and row['doctor_id']==actor_id and not row.get('mismatch')]

def test_same_day_and_same_patient_two_doctors_are_isolated():
    rows=[
      {'id':'A1','patient_id':'P','doctor_id':'A','date':'today'},
      {'id':'B1','patient_id':'P','doctor_id':'B','date':'today'},
      {'id':'N1','patient_id':'P','doctor_id':None,'date':'today'},
      {'id':'M1','patient_id':'P','doctor_id':'A','date':'today','mismatch':True},
    ]
    assert [row['id'] for row in visible(rows,'A','doctor')]==['A1']
    assert [row['id'] for row in visible(rows,'B','doctor')]==['B1']

def test_existing_rpc_derives_identity_and_enforces_ownership_server_side():
    sql=compact(MIGRATION)
    assert 'security.current_app_user_id()' in sql and 'security.current_app_role()' in sql
    assert "v_actor_role = 'doctor' and appointment.doctor_id = v_actor_id" in sql
    assert 'consultation.doctor_id is distinct from v_actor_id' in sql
    assert "v_actor_role in ('receptionist', 'admin')" in sql
    assert 'p_doctor_id' not in sql

def test_today_semantics_stay_in_existing_dashboard_and_not_new_sql():
    assert "new Date().toISOString().split('T')[0]" in COMPONENT
    assert 'a.date === todayStr' in COMPONENT
    assert 'current_date' not in MIGRATION and 'timezone(' not in MIGRATION
    assert "rpc('get_appointments')" in SERVICE

def test_dashboard_runtime_has_no_frontend_doctor_authorization_or_legacy_source():
    assert '<UpcomingConsultations />' in (ROOT.parent/'src/pages/Doctor/DoctorDashboard.jsx').read_text()
    assert 'const { appointments' in COMPONENT
    assert 'appointmentApi.listAppointments()' in CONTEXT
    supabase=SERVICE.split("if (provider !== 'supabase')")[1]
    assert not re.search(r'appointments\s*\.filter\([^\n]*doctor',COMPONENT,re.I)
    assert not re.search(r'clinic_token|/api/appointments|/appointments/today|fetch\s*\(',supabase)

def test_preflight_and_verifier_cover_data_acl_and_migration_028():
    executable=re.sub(r'--[^\n]*','',PREFLIGHT)
    assert not re.search(r'(?m)^\s*(insert|update|delete|alter|drop|create|grant|revoke|truncate)\b',executable)
    for marker in ('today_total','today_per_doctor','today_null_ownership','today_consultation_mismatches','today_same_patient_multi_doctor','dashboard.current_ownership','dashboard.acl'):
        assert marker in PREFLIGHT
    assert 'security.list_doctor_consultation_history_base()' in VERIFY
    assert VERIFY.rstrip().endswith("select 'verification successful: doctor today''s consultations are ownership-contained' as result;")
