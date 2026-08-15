import { apiRequest } from './httpClient.js';
import { readRuntimeConfig } from '../config/runtime.js';
import { getSupabaseClient } from '../lib/supabaseClient.js';

const STATUS_LABELS = {
  pending: 'Pending',
  confirmed: 'Confirmed',
  completed: 'Completed',
  cancelled: 'Cancelled',
  no_show: 'Missed',
};

const STATUS_VALUES = {
  pending: 'pending',
  confirmed: 'confirmed',
  completed: 'completed',
  cancelled: 'cancelled',
  missed: 'no_show',
  no_show: 'no_show',
};

const statusForRpc = (status = 'pending') => {
  const value = STATUS_VALUES[String(status).trim().toLowerCase()];
  if (!value) throw new Error('Unsupported appointment status');
  return value;
};

const TYPE_LABELS = {
  normal: 'Check-up',
  urgent: 'Urgent',
  follow_up: 'Follow-up',
  consultation: 'Consultation',
};

const mapAppointment = (appointment) => {
  if (!appointment) return null;
  return {
    id: appointment.id,
    patient_id: appointment.patient_id,
    patient: appointment.patient,
    doctor_id: appointment.doctor_id,
    doctor: appointment.doctor,
    date: appointment.date,
    time: appointment.time,
    type: TYPE_LABELS[appointment.type] || appointment.type,
    status: STATUS_LABELS[appointment.status] || appointment.status,
    condition: appointment.condition,
    notes: appointment.notes || '',
  };
};

const throwRpcError = (error, fallback) => {
  if (!error) return;
  if (error.code === '42501') throw new Error('Insufficient permissions');
  if (error.code === 'P0002') throw new Error(error.message || 'Appointment not found');
  if (error.code === '23503') throw new Error(error.message || 'Appointment has clinical history');
  if (error.code === '22007' || error.code === '22023') throw new Error(error.message || 'Invalid appointment data');
  throw new Error(error.message || fallback);
};

const resultRow = (data) => Array.isArray(data) ? data[0] : data;

export function createAppointmentService({
  provider = readRuntimeConfig().authProvider,
  supabaseClient,
  legacyRequest = apiRequest,
} = {}) {
  if (provider === 'legacy') {
    return {
      listAppointments: () => legacyRequest('/appointments'),
      createAppointment: (appointment) => legacyRequest('/appointments', { method: 'POST', body: appointment }),
      updateAppointment: (id, updates) => legacyRequest(`/appointments/${id}`, { method: 'PUT', body: updates }),
      updateAppointmentStatus: (id, status) => legacyRequest(`/appointments/${id}/status`, { method: 'PUT', body: { status } }),
      markAppointmentArrived: (id) => legacyRequest(`/appointments/${id}/status`, { method: 'PUT', body: { status: 'Arrived' } }),
      deleteAppointment: (id) => legacyRequest(`/appointments/${id}`, { method: 'DELETE' }),
      finishAppointmentByPatient: (patientId) => legacyRequest(`/appointments/finish-by-patient/${patientId}`, { method: 'POST' }),
    };
  }
  if (provider !== 'supabase') {
    throw new Error(`Unsupported Auth provider: ${provider}`);
  }

  const client = () => supabaseClient || getSupabaseClient();
  return {
    async listAppointments() {
      const { data, error } = await client().rpc('get_appointments');
      if (error) throwRpcError(error, 'Failed to fetch appointments');
      return (data || []).map(mapAppointment);
    },
    async createAppointment(appointment) {
      const { data, error } = await client().rpc('create_appointment', {
        p_patient_id: appointment.patient_id,
        p_doctor_id: appointment.doctor_id,
        p_date: appointment.date,
        p_time: appointment.time,
        p_type: appointment.type,
        p_condition: appointment.condition,
        p_status: statusForRpc(appointment.status),
        p_notes: appointment.notes || '',
      });
      if (error) throwRpcError(error, 'Failed to create appointment');
      return mapAppointment(resultRow(data));
    },
    async updateAppointment(id, updates) {
      const allowedFields = ['date', 'time', 'type', 'status', 'condition', 'notes'];
      const safeUpdates = Object.fromEntries(
        allowedFields.filter((field) => updates[field] !== undefined)
          .map((field) => [field, updates[field]]),
      );
      if (safeUpdates.status !== undefined) safeUpdates.status = statusForRpc(safeUpdates.status);
      const { data, error } = await client().rpc('update_appointment', {
        p_appointment_id: id,
        p_updates: safeUpdates,
      });
      if (error) throwRpcError(error, 'Failed to update appointment');
      return mapAppointment(resultRow(data));
    },
    async updateAppointmentStatus(id, status) {
      const { data, error } = await client().rpc('update_appointment_status', {
        p_appointment_id: id,
        p_status: statusForRpc(status),
      });
      if (error) throwRpcError(error, 'Failed to update appointment status');
      return mapAppointment(resultRow(data));
    },
    async markAppointmentArrived(id) {
      const { data, error } = await client().rpc('mark_appointment_arrived', {
        p_appointment_id: id,
      });
      if (error) throwRpcError(error, 'Failed to mark appointment arrival');
      return mapAppointment(resultRow(data));
    },
    async deleteAppointment(id) {
      const { data, error } = await client().rpc('delete_appointment', {
        p_appointment_id: id,
      });
      if (error) throwRpcError(error, 'Failed to delete appointment');
      return resultRow(data);
    },
    async finishAppointmentByPatient(patientId, appointmentId = null) {
      const { data, error } = await client().rpc('finish_appointment_by_patient', {
        p_patient_id: patientId,
        p_appointment_id: appointmentId,
      });
      if (error) throwRpcError(error, 'Failed to finish appointment');
      return resultRow(data);
    },
  };
}

const appointmentService = createAppointmentService();

export const listAppointments = appointmentService.listAppointments;
export const createAppointment = appointmentService.createAppointment;
export const updateAppointment = appointmentService.updateAppointment;
export const updateAppointmentStatus = appointmentService.updateAppointmentStatus;
export const markAppointmentArrived = appointmentService.markAppointmentArrived;
export const deleteAppointment = appointmentService.deleteAppointment;
export const finishAppointmentByPatient = appointmentService.finishAppointmentByPatient;
