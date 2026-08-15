const normalized = value => String(value || '').trim().toLocaleLowerCase();

export const filterPatientOptions = (patients, query) => {
  const needle = normalized(query);
  if (!needle) return patients;
  return patients.filter(patient =>
    normalized(patient.name).includes(needle) || normalized(patient.phone).includes(needle));
};

export const filterDoctorOptions = (doctors, query) => {
  const needle = normalized(query);
  if (!needle) return doctors;
  return doctors.filter(doctor =>
    normalized(doctor.name).includes(needle) || normalized(doctor.specialization).includes(needle));
};
