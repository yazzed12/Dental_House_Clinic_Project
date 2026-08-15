import React, { useState } from 'react';
import { Calendar, CheckCircle, Clock, Plus, Search, UserPlus, Loader2 } from 'lucide-react';
import Layout from '../../components/Layout';
import { useData } from '../../context/DataContext';
import { NewPatientModal } from '../../components/PatientModals';
import AddModal from '../../components/appointments/AddModal';

export default function ReceptionDashboard() {
  const { appointments, addPatient, markAppointmentArrived } = useData();
  const [showAddPatient, setShowAddPatient] = useState(false);
  const [showBookAppt, setShowBookAppt] = useState(false);
  const [arrivingIds, setArrivingIds] = useState(new Set());
  const [arrivedIds, setArrivedIds] = useState(new Set());
  const [toast, setToast] = useState(null);

  const todayStr = new Date().toISOString().split('T')[0];
  const todayAppts = appointments.filter((appointment) => appointment.date === todayStr);
  const pendingCount = todayAppts.filter(a => a.status === 'Pending').length;
  const arrivedCount = todayAppts.filter(a => arrivedIds.has(a.id)).length;
  const activeCount = todayAppts.filter(a => ['Confirmed', 'Completed'].includes(a.status)).length;

  const showToast = (msg, type = 'success') => {
    setToast({ msg, type });
    setTimeout(() => setToast(null), 3000);
  };

  const handleArrived = async (id) => {
    setArrivingIds(prev => new Set([...prev, id]));
    try {
      await markAppointmentArrived(id);
      setArrivedIds(prev => new Set([...prev, id]));
      showToast('Patient marked as Arrived. Doctor notified.', 'success');
    } catch (err) {
      showToast('Failed to update status.', 'error');
    } finally {
      setArrivingIds(prev => {
        const next = new Set(prev);
        next.delete(id);
        return next;
      });
    }
  };

  const handleSavePatient = async (data) => {
    const result = await addPatient(data);
    if (result) {
      showToast('Patient added successfully');
      return result;
    }
    return null;
  };

  return (
    <Layout pageTitle="Reception Desk" pageSubtitle="Appointment schedule and front desk actions.">
      <div className="page-stack animate-fadeIn">
        {/* Toast */}
        {toast && (
          <div style={{ position: 'fixed', bottom: 24, left: '50%', transform: 'translateX(-50%)', background: toast.type === 'error' ? '#dc2626' : '#1e293b', color: '#fff', padding: '10px 22px', borderRadius: 20, boxShadow: '0 8px 20px rgba(0,0,0,0.2)', zIndex: 2000, display: 'flex', alignItems: 'center', gap: 8, fontSize: '0.88rem', fontWeight: 600 }}>
            <CheckCircle size={15} /> {toast.msg}
          </div>
        )}

        <section className="section-header">
          <div className="search-box">
            <Search size={16} />
            <input className="search-box-field" type="text" placeholder="Quick find patient..." />
          </div>
          <div style={{ display: 'flex', gap: 10 }}>
            <button className="clinic-btn clinic-btn-outline" onClick={() => setShowAddPatient(true)}><UserPlus size={18} /> Add Patient</button>
            <button className="clinic-btn clinic-btn-primary" onClick={() => setShowBookAppt(true)}><Plus size={18} /> Book Appointment</button>
          </div>
        </section>

        <section className="metric-grid-3">
          <div className="card stat-card">
            <div className="stat-icon"><Clock size={22} /></div>
            <div><div className="stat-value">{pendingCount}</div><div className="stat-label">Pending Approvals</div></div>
          </div>
          <div className="card stat-card">
            <div className="stat-icon"><UserPlus size={22} color="var(--clr-primary)" /></div>
            <div><div className="stat-value">{arrivedCount}</div><div className="stat-label">Patients Arrived</div></div>
          </div>
          <div className="card">
            <p className="section-kicker">Daily Capacity</p>
            <p className="section-subtitle">{activeCount} visits today so far.</p>
            <div style={{ marginTop: 8, height: 6, background: 'var(--clr-bg)', borderRadius: 3, overflow: 'hidden' }}>
              <div style={{ width: `${Math.min((activeCount / 20) * 100, 100)}%`, height: '100%', background: 'var(--clr-primary)' }} />
            </div>
          </div>
        </section>

        <section className="card">
          <div className="section-header">
            <div>
              <h3 className="section-title"><Calendar size={18} color="var(--clr-primary-dark)" /> Today's Schedule</h3>
              <p className="section-subtitle">Confirmed and waiting appointments.</p>
            </div>
          </div>
          <div className="table-wrap">
            <table className="table">
              <thead>
                <tr>
                  <th>Time</th>
                  <th>Patient</th>
                  <th>Specialist</th>
                  <th>Status</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {todayAppts.length === 0 ? (
                  <tr><td colSpan={5} style={{ textAlign: 'center', padding: '40px', color: 'var(--clr-subtext)' }}>No appointments for today.</td></tr>
                ) : todayAppts.map((appointment) => (
                  <tr key={appointment.id}>
                    <td><strong>{appointment.time}</strong></td>
                    <td>{appointment.patient}</td>
                    <td className="muted">{appointment.doctor}</td>
                    <td>
                      {arrivedIds.has(appointment.id) ? (
                        <span className="badge badge-success"><CheckCircle size={12} /> Arrived</span>
                      ) : appointment.status === 'Confirmed' ? (
                        <span className="badge badge-primary"><CheckCircle size={12} /> {appointment.status}</span>
                      ) : (
                        <span className="badge badge-warning"><Clock size={12} /> {appointment.status}</span>
                      )}
                    </td>
                    <td>
                      <div className="row-actions">
                        <button 
                          className="clinic-btn clinic-btn-primary btn-sm" 
                          disabled={arrivedIds.has(appointment.id) || arrivingIds.has(appointment.id)}
                          onClick={() => handleArrived(appointment.id)}
                        >
                          {arrivingIds.has(appointment.id) ? <Loader2 size={14} className="animate-spin" /> : 'Arrived'}
                        </button>
                        <button className="clinic-btn clinic-btn-outline btn-sm">Reschedule</button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      </div>

      {showAddPatient && <NewPatientModal onClose={() => setShowAddPatient(false)} onSave={handleSavePatient} />}
      {showBookAppt && <AddModal onClose={() => setShowBookAppt(false)} />}
    </Layout>
  );
}
