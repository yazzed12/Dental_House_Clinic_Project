const COMPLETED_STATUSES = new Set(['complete', 'completed', 'finished']);

export const isCompletedAppointmentStatus = (status) => (
  COMPLETED_STATUSES.has(String(status || '').trim().toLowerCase())
);

export const markFinishedAppointment = (
  appointments,
  { patientId, appointmentId, today },
) => {
  const patientKey = String(patientId);
  const appointmentKey = appointmentId == null ? null : String(appointmentId);
  let fallbackApplied = false;

  return appointments.map((appointment) => {
    const exactAppointment = appointmentKey !== null
      && String(appointment.id) === appointmentKey;
    const patientFallback = appointmentKey === null
      && !fallbackApplied
      && String(appointment.patient_id) === patientKey
      && appointment.date === today
      && !isCompletedAppointmentStatus(appointment.status);

    if (!exactAppointment && !patientFallback) return appointment;
    fallbackApplied = true;
    return { ...appointment, status: 'completed' };
  });
};
