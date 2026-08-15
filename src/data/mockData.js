// =============================================
//   SMART MEDICAL CLINIC — MOCK DATA
// =============================================

export const doctors = [
  { id: 1, name: 'DR Yehia El-ameir', specialty: 'Cardiologist', avatar: 'SM', status: 'online', patients: 142, rating: 4.9, experience: '12 yrs', color: '#3b82f6', schedule: 'Mon–Fri' },
  { id: 2, name: 'Dr. James Okafor',   specialty: 'Neurologist',   avatar: 'JO', status: 'online', patients: 98,  rating: 4.8, experience: '9 yrs',  color: '#8b5cf6', schedule: 'Tue–Sat' },
  { id: 3, name: 'Dr. Lena Fischer',   specialty: 'Dermatologist', avatar: 'LF', status: 'away',   patients: 115, rating: 4.7, experience: '7 yrs',  color: '#14b8a6', schedule: 'Mon–Thu' },
  { id: 4, name: 'Dr. Carlos Vega',    specialty: 'Orthopedist',   avatar: 'CV', status: 'offline',patients: 87,  rating: 4.6, experience: '15 yrs', color: '#f59e0b', schedule: 'Wed–Sun' },
  { id: 5, name: 'Dr. Amara Nwosu',    specialty: 'Pediatrician',  avatar: 'AN', status: 'online', patients: 203, rating: 5.0, experience: '11 yrs', color: '#10b981', schedule: 'Mon–Fri' },
  { id: 6, name: 'Dr. Ryan Patel',     specialty: 'Psychiatrist',  avatar: 'RP', status: 'online', patients: 74,  rating: 4.7, experience: '6 yrs',  color: '#6366f1', schedule: 'Tue–Fri' },
];

export const patients = [
  { id: 1,  name: 'Eleanor Voss',    age: 54, gender: 'F', blood: 'A+',  phone: '+1 555-0101', doctor: 'DR Yehia El-ameir', condition: 'Hypertension',    status: 'Active',    lastVisit: '2026-04-18', nextVisit: '2026-04-30', avatar: 'EV' },
  { id: 2,  name: 'Marcus Cole',     age: 38, gender: 'M', blood: 'O-',  phone: '+1 555-0102', doctor: 'Dr. James Okafor',   condition: 'Migraine',         status: 'Active',    lastVisit: '2026-04-15', nextVisit: '2026-05-08', avatar: 'MC' },
  { id: 3,  name: 'Taraji Barnes',   age: 29, gender: 'F', blood: 'B+',  phone: '+1 555-0103', doctor: 'Dr. Lena Fischer',   condition: 'Eczema',           status: 'Recovered', lastVisit: '2026-04-10', nextVisit: '—',          avatar: 'TB' },
  { id: 4,  name: 'Oliver Grant',    age: 61, gender: 'M', blood: 'AB+', phone: '+1 555-0104', doctor: 'Dr. Carlos Vega',    condition: 'Knee Arthritis',   status: 'Critical',  lastVisit: '2026-04-20', nextVisit: '2026-04-25', avatar: 'OG' },
  { id: 5,  name: 'Priya Sharma',    age: 7,  gender: 'F', blood: 'A-',  phone: '+1 555-0105', doctor: 'Dr. Amara Nwosu',    condition: 'Asthma',           status: 'Active',    lastVisit: '2026-04-12', nextVisit: '2026-05-01', avatar: 'PS' },
  { id: 6,  name: 'Leo Kowalski',    age: 45, gender: 'M', blood: 'O+',  phone: '+1 555-0106', doctor: 'Dr. Ryan Patel',     condition: 'Anxiety Disorder', status: 'Active',    lastVisit: '2026-04-16', nextVisit: '2026-04-28', avatar: 'LK' },
  { id: 7,  name: 'Nina Johansson',  age: 33, gender: 'F', blood: 'B-',  phone: '+1 555-0107', doctor: 'DR Yehia El-ameir', condition: 'Arrhythmia',       status: 'Active',    lastVisit: '2026-04-19', nextVisit: '2026-05-05', avatar: 'NJ' },
  { id: 8,  name: 'Kwame Asante',    age: 50, gender: 'M', blood: 'O+',  phone: '+1 555-0108', doctor: 'Dr. Carlos Vega',    condition: 'Lumbar Disc',      status: 'Critical',  lastVisit: '2026-04-21', nextVisit: '2026-04-23', avatar: 'KA' },
  { id: 9,  name: 'Sofia Reyes',     age: 22, gender: 'F', blood: 'A+',  phone: '+1 555-0109', doctor: 'Dr. Lena Fischer',   condition: 'Psoriasis',        status: 'Active',    lastVisit: '2026-04-09', nextVisit: '2026-05-12', avatar: 'SR' },
  { id: 10, name: 'David Huang',     age: 67, gender: 'M', blood: 'AB-', phone: '+1 555-0110', doctor: 'Dr. James Okafor',   condition: 'Parkinson\'s',     status: 'Active',    lastVisit: '2026-04-14', nextVisit: '2026-04-29', avatar: 'DH' },
];

export const appointments = [
  { id: 1,  patient: 'Eleanor Voss',   doctor: 'DR Yehia El-ameir', type: 'Follow-up',  date: '2026-04-23', time: '09:00 AM', status: 'Confirmed', room: 'A-101' },
  { id: 2,  patient: 'Marcus Cole',    doctor: 'Dr. James Okafor',   type: 'Consultation',date: '2026-04-23', time: '10:30 AM', status: 'Confirmed', room: 'B-203' },
  { id: 3,  patient: 'Oliver Grant',   doctor: 'Dr. Carlos Vega',    type: 'Urgent',     date: '2026-04-23', time: '11:00 AM', status: 'Pending',   room: 'C-305' },
  { id: 4,  patient: 'Priya Sharma',   doctor: 'Dr. Amara Nwosu',    type: 'Check-up',   date: '2026-04-24', time: '08:30 AM', status: 'Confirmed', room: 'D-102' },
  { id: 5,  patient: 'Leo Kowalski',   doctor: 'Dr. Ryan Patel',     type: 'Therapy',    date: '2026-04-24', time: '02:00 PM', status: 'Confirmed', room: 'E-401' },
  { id: 6,  patient: 'Nina Johansson', doctor: 'DR Yehia El-ameir', type: 'ECG Test',   date: '2026-04-25', time: '09:30 AM', status: 'Pending',   room: 'A-102' },
  { id: 7,  patient: 'David Huang',    doctor: 'Dr. James Okafor',   type: 'MRI Review', date: '2026-04-25', time: '11:30 AM', status: 'Confirmed', room: 'B-204' },
  { id: 8,  patient: 'Sofia Reyes',    doctor: 'Dr. Lena Fischer',   type: 'Follow-up',  date: '2026-04-26', time: '03:00 PM', status: 'Cancelled', room: 'C-201' },
  { id: 9,  patient: 'Kwame Asante',   doctor: 'Dr. Carlos Vega',    type: 'Surgery Prep',date: '2026-04-26',time: '07:00 AM', status: 'Confirmed', room: 'OR-1' },
  { id: 10, patient: 'Taraji Barnes',  doctor: 'Dr. Lena Fischer',   type: 'Check-up',   date: '2026-04-28', time: '01:00 PM', status: 'Pending',   room: 'C-203' },
];

export const stats = {
  totalPatients:  { value: 1248, change: +12, label: 'Total Patients' },
  todayAppts:     { value: 34,   change: +5,  label: 'Today\'s Appointments' },
  activeDoctors:  { value: 18,   change: 0,   label: 'Active Doctors' },
  bedOccupancy:   { value: '76%',change: -3,  label: 'Bed Occupancy' },
  revenue:        { value: '$84.2K', change: +8, label: 'Monthly Revenue' },
};

export const weeklyAppointments = [
  { day: 'Mon', count: 42 },
  { day: 'Tue', count: 58 },
  { day: 'Wed', count: 35 },
  { day: 'Thu', count: 67 },
  { day: 'Fri', count: 51 },
  { day: 'Sat', count: 28 },
  { day: 'Sun', count: 14 },
];

export const patientsByDept = [
  { dept: 'Cardiology',   count: 312, color: '#3b82f6' },
  { dept: 'Neurology',    count: 198, color: '#8b5cf6' },
  { dept: 'Dermatology',  count: 167, color: '#14b8a6' },
  { dept: 'Orthopedics',  count: 204, color: '#f59e0b' },
  { dept: 'Pediatrics',   count: 289, color: '#10b981' },
  { dept: 'Psychiatry',   count: 78,  color: '#6366f1' },
];

export const notifications = [
  { id: 1, type: 'urgent',  text: 'Patient Oliver Grant needs urgent attention — Room C-305', time: '5m ago' },
  { id: 2, type: 'info',    text: 'Dr. Amara Nwosu has updated her schedule for next week', time: '18m ago' },
  { id: 3, type: 'success', text: 'Lab results ready for Marcus Cole', time: '32m ago' },
  { id: 4, type: 'warning', text: 'Medication stock for Ward B running low', time: '1h ago' },
  { id: 5, type: 'info',    text: '6 new appointment requests awaiting approval', time: '2h ago' },
];
