import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';

const [dashboard,component,context,service,migration]=await Promise.all([
  readFile(new URL('../pages/Doctor/DoctorDashboard.jsx',import.meta.url),'utf8'),
  readFile(new URL('./UpcomingConsultations.jsx',import.meta.url),'utf8'),
  readFile(new URL('../context/DataContext.jsx',import.meta.url),'utf8'),
  readFile(new URL('../services/appointmentApi.js',import.meta.url),'utf8'),
  readFile(new URL('../../backend/migrations/029_doctor_today_dashboard_ownership.sql',import.meta.url),'utf8'),
]);

test('Doctor dashboard consumes the Supabase appointment RPC through one context path',()=>{
  assert.match(dashboard,/<UpcomingConsultations \/>/);
  assert.match(component,/const \{ appointments, appointmentsLoading, appointmentsError/);
  assert.match(context,/appointmentApi\.listAppointments\(\)/);
  assert.match(service,/rpc\('get_appointments'\)/);
  const supabase=service.split("if (provider !== 'supabase')")[1];
  assert.doesNotMatch(supabase,/FastAPI|clinic_token|\/api\/appointments|\/appointments\/today|fetch\s*\(/);
});

test('Doctor ownership remains server-side while existing Today semantics stay local',()=>{
  assert.match(migration,/appointment\.doctor_id = v_actor_id/);
  assert.doesNotMatch(component,/filter\([^\n]*(doctor_id|doctorId)/);
  assert.match(component,/new Date\(\)\.toISOString\(\)\.split\('T'\)\[0\]/);
  assert.match(component,/a\.date === todayStr/);
});

test('loading and RPC failures cannot masquerade as an empty Doctor schedule',()=>{
  assert.match(component,/appointmentsLoading \? \(/);
  assert.match(component,/appointmentsError \? \(/);
  assert.match(component,/role="status"/);
  assert.match(component,/role="alert"/);
});
