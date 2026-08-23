import { getSupabaseClient } from '../lib/supabaseClient.js';

const mapFromDb = (p) => {
  if (!p) return null;
  return {
    id: p.id,
    displayId: p.display_id,
    name: p.name,
    age: p.age,
    phone: p.phone,
    gender: p.gender,
    status: p.status,
    condition: p.condition,
    lastVisit: p.last_visit,
    bloodType: p.blood_type,
  };
};

const mapToDb = (p) => {
  if (!p) return {};
  const payload = {};
  if (p.name !== undefined) payload.name = p.name;
  if (p.age !== undefined) payload.age = p.age;
  if (p.phone !== undefined) payload.phone = p.phone;
  if (p.gender !== undefined) payload.gender = p.gender;
  if (p.status !== undefined) payload.status = p.status;
  if (p.condition !== undefined) payload.condition = p.condition;
  if (p.lastVisit !== undefined) payload.last_visit = p.lastVisit;
  if (p.bloodType !== undefined) payload.blood_type = p.bloodType;
  return payload;
};

const handleSupabaseError = (error, defaultMessage) => {
  if (!error) return;
  if (error.code === '42501' || error.message?.includes('permission')) {
    throw new Error('Insufficient permissions');
  }
  if (error.code === 'P0002' || error.code === 'PGRST116' || error.message?.includes('not found')) {
    throw new Error('Patient not found');
  }
  if (error.code === '23505' || error.message?.includes('duplicate')) {
    throw new Error('Duplicate patient record');
  }
  throw new Error(error.message || defaultMessage);
};

export const listPatients = async (client = getSupabaseClient()) => {
  const { data, error } = await client
    .from('patients')
    .select()
    .neq('status', 'Archived');
  if (error) handleSupabaseError(error, 'Failed to fetch patients');
  return (data || []).map(mapFromDb);
};

export const getPatient = async (id, client = getSupabaseClient()) => {
  const { data, error } = await client
    .from('patients')
    .select()
    .eq('id', id)
    .single();
  if (error) handleSupabaseError(error, 'Patient not found');
  return mapFromDb(data);
};

export const createPatient = async (patient, client = getSupabaseClient()) => {
  const { data, error } = await client
    .from('patients')
    .insert([mapToDb(patient)])
    .select()
    .single();
  if (error) handleSupabaseError(error, 'Failed to create patient');
  return mapFromDb(data);
};

export const updatePatient = async (id, updates, client = getSupabaseClient()) => {
  const { data, error } = await client
    .from('patients')
    .update(mapToDb(updates))
    .eq('id', id)
    .select()
    .single();
  if (error) handleSupabaseError(error, 'Failed to update patient');
  return {
    status: 'success',
    patient: mapFromDb(data),
  };
};

export const deletePatient = async (id, client = getSupabaseClient()) => {
  const { data, error } = await client.rpc('safe_delete_patient', { p_patient_id: id });
  if (error) handleSupabaseError(error, 'Failed to delete patient');
  return data;
};
