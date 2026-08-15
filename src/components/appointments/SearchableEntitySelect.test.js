import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';

import { filterDoctorOptions, filterPatientOptions } from './selectorFilters.js';

const patients = [
  { id: 'patient-a', name: 'Nadia Hassan', phone: '01012345678' },
  { id: 'patient-b', name: 'Omar Ali', phone: '01198765432' },
];
const doctors = [
  { id: 'doctor-a', name: 'Dr. Sara Adel', specialization: 'Orthodontics' },
  { id: 'doctor-b', name: 'Dr. Karim Noor', specialization: 'Oral Surgery' },
];

test('patient search matches name case-insensitively and optional phone', () => {
  assert.deepEqual(filterPatientOptions(patients, 'NADIA').map(item => item.id), ['patient-a']);
  assert.deepEqual(filterPatientOptions(patients, '011987').map(item => item.id), ['patient-b']);
});

test('Doctor search matches full name and specialization case-insensitively', () => {
  assert.deepEqual(filterDoctorOptions(doctors, 'KARIM').map(item => item.id), ['doctor-b']);
  assert.deepEqual(filterDoctorOptions(doctors, 'orthodontics').map(item => item.id), ['doctor-a']);
});

test('clearing search restores the original authoritative arrays without mutation', () => {
  assert.equal(filterPatientOptions(patients, ''), patients);
  assert.equal(filterDoctorOptions(doctors, '  '), doctors);
  assert.deepEqual(patients.map(item => item.id), ['patient-a', 'patient-b']);
  assert.deepEqual(doctors.map(item => item.id), ['doctor-a', 'doctor-b']);
});

test('typing is local and selecting retains authoritative UUID payload fields', async () => {
  const selector = await readFile(new URL('./SearchableEntitySelect.jsx', import.meta.url), 'utf8');
  const modal = await readFile(new URL('./AddModal.jsx', import.meta.url), 'utf8');
  assert.doesNotMatch(selector, /fetch\(|\.rpc\(|\.from\(/);
  assert.match(selector, /onChange\(option\.id\)/);
  assert.match(modal, /patient_id: selectedPatient\.id/);
  assert.match(modal, /doctor_id: selectedDoctor\.id/);
  assert.match(modal, /No matching patients/);
  assert.match(modal, /No matching doctors/);
  assert.match(modal, /Doctors unavailable/);
  assert.match(modal, /Patients unavailable/);
});
