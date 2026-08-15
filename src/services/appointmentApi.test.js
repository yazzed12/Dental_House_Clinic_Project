import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import { createAppointmentService } from './appointmentApi.js';

function createSupabaseMock(responses = {}) {
  const calls = [];
  return {
    calls,
    async rpc(name, args) {
      calls.push({ name, args });
      return responses[name] || { data: { status: 'success' }, error: null };
    },
  };
}

test('Supabase appointment list uses the safe projection RPC and maps display data', async () => {
  const client = createSupabaseMock({
    get_appointments: {
      data: [{
        id: 'appointment-1', patient_id: 'patient-1', patient: 'Patient One',
        doctor_id: 'doctor-1', doctor: 'Doctor One', date: '2026-08-25',
        time: '09:30', type: 'follow_up', status: 'no_show',
        condition: 'Review', notes: 'Bring x-rays',
      }],
      error: null,
    },
  });
  const legacyCalls = [];
  const service = createAppointmentService({
    provider: 'supabase',
    supabaseClient: client,
    legacyRequest: async (...args) => legacyCalls.push(args),
  });

  assert.deepEqual(await service.listAppointments(), [{
    id: 'appointment-1', patient_id: 'patient-1', patient: 'Patient One',
    doctor_id: 'doctor-1', doctor: 'Doctor One', date: '2026-08-25',
    time: '09:30', type: 'Follow-up', status: 'Missed',
    condition: 'Review', notes: 'Bring x-rays',
  }]);
  assert.deepEqual(client.calls, [{ name: 'get_appointments', args: undefined }]);
  assert.deepEqual(legacyCalls, []);
});

test('Supabase create sends authoritative patient and Doctor UUIDs', async () => {
  const client = createSupabaseMock({
    create_appointment: {
      data: {
        id: 'appointment-1', patient_id: 'patient-uuid', patient: 'Patient',
        doctor_id: 'doctor-uuid', doctor: 'Doctor', date: '2026-08-25',
        time: '09:30', type: 'consultation', status: 'pending',
        condition: 'Review', notes: '',
      },
      error: null,
    },
  });
  const service = createAppointmentService({ provider: 'supabase', supabaseClient: client });
  const created = await service.createAppointment({
    patient_id: 'patient-uuid', doctor_id: 'doctor-uuid', date: '2026-08-25',
    time: '09:30', type: 'Consultation', condition: 'Review',
  });

  assert.equal(created.patient_id, 'patient-uuid');
  assert.equal(created.doctor_id, 'doctor-uuid');
  assert.deepEqual(client.calls[0], {
    name: 'create_appointment',
    args: {
      p_patient_id: 'patient-uuid', p_doctor_id: 'doctor-uuid',
      p_date: '2026-08-25', p_time: '09:30', p_type: 'Consultation',
      p_condition: 'Review', p_status: 'pending', p_notes: '',
    },
  });
});

test('Supabase update/status/delete/finish use controlled RPCs', async () => {
  const client = createSupabaseMock();
  const service = createAppointmentService({ provider: 'supabase', supabaseClient: client });
  await service.updateAppointment('appointment-1', { time: '10:00', patient: 'ignored', doctor_id: 'ignored' });
  await service.updateAppointmentStatus('appointment-1', 'Completed');
  await service.markAppointmentArrived('appointment-1');
  await service.deleteAppointment('appointment-1');
  await service.finishAppointmentByPatient('patient-1', 'appointment-1');

  assert.deepEqual(client.calls, [
    { name: 'update_appointment', args: { p_appointment_id: 'appointment-1', p_updates: { time: '10:00' } } },
    { name: 'update_appointment_status', args: { p_appointment_id: 'appointment-1', p_status: 'completed' } },
    { name: 'mark_appointment_arrived', args: { p_appointment_id: 'appointment-1' } },
    { name: 'delete_appointment', args: { p_appointment_id: 'appointment-1' } },
    { name: 'finish_appointment_by_patient', args: { p_patient_id: 'patient-1', p_appointment_id: 'appointment-1' } },
  ]);
});

test('Supabase appointment errors remain distinct from valid empty results', async () => {
  const emptyService = createAppointmentService({
    provider: 'supabase',
    supabaseClient: createSupabaseMock({ get_appointments: { data: [], error: null } }),
  });
  assert.deepEqual(await emptyService.listAppointments(), []);

  const failedService = createAppointmentService({
    provider: 'supabase',
    supabaseClient: createSupabaseMock({ get_appointments: { data: null, error: { code: '42501' } } }),
  });
  await assert.rejects(failedService.listAppointments(), /Insufficient permissions/);
});

test('legacy appointment behavior remains rollback-compatible', async () => {
  const calls = [];
  const service = createAppointmentService({
    provider: 'legacy',
    legacyRequest: async (...args) => {
      calls.push(args);
      return { ok: true };
    },
  });
  await service.listAppointments();
  await service.createAppointment({ patient_id: 'patient-1' });
  await service.updateAppointment('appointment-1', { time: '10:00' });
  await service.updateAppointmentStatus('appointment-1', 'Completed');
  await service.markAppointmentArrived('appointment-1');
  await service.deleteAppointment('appointment-1');
  await service.finishAppointmentByPatient('patient-1');
  assert.deepEqual(calls.map(([path]) => path), [
    '/appointments', '/appointments', '/appointments/appointment-1',
    '/appointments/appointment-1/status', '/appointments/appointment-1/status', '/appointments/appointment-1',
    '/appointments/finish-by-patient/patient-1',
  ]);
});

test('Supabase status mutations accept only the production appointment enum set', async () => {
  const client = createSupabaseMock();
  const service = createAppointmentService({ provider: 'supabase', supabaseClient: client });
  for (const status of ['pending', 'confirmed', 'completed', 'cancelled', 'no_show', 'Missed']) {
    await service.updateAppointmentStatus('appointment-1', status);
  }
  for (const status of ['arrived', 'scheduled', 'in_progress', 'unknown']) {
    await assert.rejects(service.updateAppointmentStatus('appointment-1', status), /Unsupported appointment status/);
  }
  assert.deepEqual(
    client.calls.map(({ args }) => args.p_status),
    ['pending', 'confirmed', 'completed', 'cancelled', 'no_show', 'no_show'],
  );
});

test('appointment Supabase transport and AddModal have no name-based identity or clinic token dependency', async () => {
  const service = await readFile(new URL('./appointmentApi.js', import.meta.url), 'utf8');
  const modal = await readFile(new URL('../components/appointments/AddModal.jsx', import.meta.url), 'utf8');
  const reception = await readFile(new URL('../pages/Receptionist/ReceptionDashboard.jsx', import.meta.url), 'utf8');
  assert.match(service, /rpc\('create_appointment'/);
  assert.doesNotMatch(service, /clinic_token/);
  assert.doesNotMatch(service, /\.from\(['"]appointments['"]\)/);
  assert.match(modal, /doctor_id: selectedDoctor\.id/);
  assert.match(modal, /patient_id: selectedPatient\.id/);
  assert.match(modal, /onChange=\{doctorId => setFormData/);
  assert.match(modal, /onChange=\{patientId => setFormData/);
  assert.match(reception, /await markAppointmentArrived\(id\)/);
  assert.doesNotMatch(reception, /updateAppointmentStatus\(id, ['"]Arrived['"]\)/);
});
