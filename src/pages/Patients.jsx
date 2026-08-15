import { useState } from 'react';
import Layout from '../components/Layout';
import { useData } from '../context/DataContext';
import { Search, Plus, Eye, Edit, Trash2, User, X, ChevronDown } from 'lucide-react';

const STATUS_COLORS = {
  Active:    'badge badge-success',
  Recovered: 'badge badge-cyan',
  Critical:  'badge badge-danger',
};

const BLOOD_COLORS = {
  'A+': '#3b82f6', 'A-': '#60a5fa',
  'B+': '#8b5cf6', 'B-': '#a78bfa',
  'AB+': '#10b981','AB-': '#34d399',
  'O+': '#f59e0b', 'O-': '#fbbf24',
};

/* ── Add Patient Modal ────────────────────────────────────── */
function AddPatientModal({ onClose }) {
  const { addPatient, doctors } = useData();
  const [formData, setFormData] = useState({
    name: '', age: '', gender: 'M', bloodType: 'O+',
    phone: '', doctor: doctors[0]?.name || '',
    status: 'Active',
    lastVisit: new Date().toISOString().split('T')[0],
    nextVisit: '—'
  });

  const handleSubmit = (e) => {
    e.preventDefault();
    addPatient(formData);
    onClose();
  };

  return (
    <div className="modal-overlay" onClick={onClose}>
      <form className="modal" onClick={e => e.stopPropagation()} onSubmit={handleSubmit} style={{ maxWidth: 500 }}>
        <div className="modal-header">
          <h2 className="modal-title">Register New Patient</h2>
          <button type="button" className="modal-close" onClick={onClose}><X size={14} /></button>
        </div>

        <div className="grid-2" style={{ gap: 12, marginBottom: 16 }}>
          <div className="form-group" style={{ gridColumn: 'span 2' }}>
            <label className="form-label">Full Name</label>
            <input 
              className="form-input" placeholder="e.g. John Smith" required 
              value={formData.name} onChange={e => setFormData({...formData, name: e.target.value})}
            />
          </div>
          <div className="form-group">
            <label className="form-label">Age</label>
            <input 
              type="number" className="form-input" required 
              value={formData.age} onChange={e => setFormData({...formData, age: e.target.value})}
            />
          </div>
          <div className="form-group">
            <label className="form-label">Gender</label>
            <select 
              className="form-select"
              value={formData.gender} onChange={e => setFormData({...formData, gender: e.target.value})}
            >
              <option value="M">Male</option>
              <option value="F">Female</option>
            </select>
          </div>
          <div className="form-group">
            <label className="form-label">Blood Type</label>
            <select 
              className="form-select"
              value={formData.bloodType} onChange={e => setFormData({...formData, bloodType: e.target.value})}
            >
              {Object.keys(BLOOD_COLORS).map(b => <option key={b}>{b}</option>)}
            </select>
          </div>
          <div className="form-group">
            <label className="form-label">Phone</label>
            <input 
              className="form-input" placeholder="+1 555-0000" required 
              value={formData.phone} onChange={e => setFormData({...formData, phone: e.target.value})}
            />
          </div>
          <div className="form-group" style={{ gridColumn: 'span 2' }}>
            <label className="form-label">Assigned Doctor</label>
            <select 
              className="form-select"
              value={formData.doctor} onChange={e => setFormData({...formData, doctor: e.target.value})}
            >
              {doctors.map(d => <option key={d.id}>{d.name}</option>)}
            </select>
          </div>
          </div>
        </div>

        <div style={{ display: 'flex', gap: 10 }}>
          <button type="submit" className="btn btn-primary" style={{ flex: 1 }}>Register Patient</button>
          <button type="button" className="btn btn-ghost" onClick={onClose}>Cancel</button>
        </div>
      </form>
    </div>
  );
}

function PatientModal({ patient, onClose }) {
  if (!patient) return null;
  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal" onClick={e => e.stopPropagation()}>
        <div className="modal-header">
          <h2 className="modal-title">Patient Details</h2>
          <button className="modal-close" onClick={onClose}><X size={14} /></button>
        </div>

        {/* Profile */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 16, marginBottom: 'var(--sp-lg)', padding: '16px 20px', background: 'var(--clr-surface-2)', borderRadius: 'var(--r-lg)', border: '1px solid var(--clr-border)' }}>
          <div className="avatar" style={{ width: 56, height: 56, fontSize: '1.1rem', flexShrink: 0 }}>{patient.avatar}</div>
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: '1.1rem', fontWeight: 700, color: 'var(--clr-text-primary)' }}>{patient.name}</div>
            <div style={{ fontSize: '0.8rem', color: 'var(--clr-text-muted)' }}>{patient.gender === 'F' ? 'Female' : 'Male'} · {patient.age} years · {patient.phone}</div>
          </div>
          <div style={{ textAlign: 'center' }}>
            <div style={{ width: 36, height: 36, borderRadius: 'var(--r-sm)', background: `${BLOOD_COLORS[patient.bloodType] || '#94a3b8'}22`, display: 'flex', alignItems: 'center', justifyContent: 'center', border: `1px solid ${BLOOD_COLORS[patient.bloodType] || '#94a3b8'}44` }}>
              <span style={{ fontSize: '0.75rem', fontWeight: 800, color: BLOOD_COLORS[patient.bloodType] || '#94a3b8' }}>{patient.bloodType || 'N/A'}</span>
            </div>
            <div style={{ fontSize: '0.6rem', color: 'var(--clr-text-muted)', marginTop: 2 }}>Blood</div>
          </div>
        </div>

        {/* Details Grid */}
        <div className="grid-2" style={{ gap: 12, marginBottom: 16 }}>
          {[
            { label: 'Assigned Doctor', value: patient.doctor },
            { label: 'Blood Type',      value: patient.bloodType || 'Unknown' },
            { label: 'Status',          value: patient.status, badge: true },
            { label: 'Last Visit',      value: patient.lastVisit },
            { label: 'Next Visit',      value: patient.nextVisit },
            { label: 'Phone',           value: patient.phone },
          ].map(({ label, value, badge }) => (
            <div key={label} style={{ padding: '10px 14px', background: 'var(--clr-surface-2)', borderRadius: 'var(--r-md)', border: '1px solid var(--clr-border)' }}>
              <div style={{ fontSize: '0.68rem', color: 'var(--clr-text-muted)', fontWeight: 600, textTransform: 'uppercase', letterSpacing: '0.06em', marginBottom: 4 }}>{label}</div>
              {badge
                ? <span className={STATUS_COLORS[value]}>{value}</span>
                : <div style={{ fontSize: '0.85rem', fontWeight: 600, color: 'var(--clr-text-primary)' }}>{value}</div>
              }
            </div>
          ))}
        </div>

        <div style={{ display: 'flex', gap: 10, marginTop: 'var(--sp-md)' }}>
          <button className="btn btn-primary" style={{ flex: 1 }}><Edit size={14} /> Edit Record</button>
          <button className="btn btn-ghost" onClick={onClose}>Close</button>
        </div>
      </div>
    </div>
  );
}

export default function Patients() {
  const { patients } = useData();
  const [search, setSearch] = useState('');
  const [filter, setFilter] = useState('All');
  const [selected, setSelected] = useState(null);
  const [showAdd, setShowAdd] = useState(false);

  const filtered = patients.filter(p => {
    const matchSearch = (p.name?.toLowerCase() || '').includes(search.toLowerCase()) ||
      (p.doctor?.toLowerCase() || '').includes(search.toLowerCase());
    const matchFilter = filter === 'All' || p.status === filter;
    return matchSearch && matchFilter;
  });

  return (
    <Layout pageTitle="Patients" pageSubtitle={`${patients.length} registered patients`}>
      {/* Header Controls */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 'var(--sp-xl)', flexWrap: 'wrap' }}>
        {/* Search */}
        <div style={{ position: 'relative', flex: 1, minWidth: 220 }}>
          <Search size={15} style={{ position: 'absolute', left: 12, top: '50%', transform: 'translateY(-50%)', color: 'var(--clr-text-muted)' }} />
          <input
            className="form-input"
            style={{ paddingLeft: 38, borderRadius: 'var(--r-full)' }}
            placeholder="Search patients…"
            value={search}
            onChange={e => setSearch(e.target.value)}
          />
        </div>

        {/* Status Filter */}
        <div style={{ display: 'flex', gap: 6 }}>
          {['All', 'Active', 'Critical', 'Recovered'].map(s => (
            <button
              key={s}
              className={`btn btn-sm ${filter === s ? 'btn-primary' : 'btn-secondary'}`}
              onClick={() => setFilter(s)}
            >
              {s}
            </button>
          ))}
        </div>

        <button className="btn btn-primary" onClick={() => setShowAdd(true)}>
          <Plus size={15} /> Add Patient
        </button>
      </div>

      {/* Summary Cards */}
      <div className="grid-4 stagger animate-fadeIn" style={{ marginBottom: 'var(--sp-xl)' }}>
        {[
          { label: 'Total',     value: patients.length,                                     color: '#3b82f6' },
          { label: 'Active',    value: patients.filter(p => p.status === 'Active').length,    color: '#10b981' },
          { label: 'Critical',  value: patients.filter(p => p.status === 'Critical').length,  color: '#ef4444' },
          { label: 'Recovered', value: patients.filter(p => p.status === 'Recovered').length, color: '#06b6d4' },
        ].map(({ label, value, color }) => (
          <div key={label} className="card" style={{ padding: '16px 20px', textAlign: 'center' }}>
            <div style={{ fontSize: '1.8rem', fontWeight: 800, color }}>{value}</div>
            <div style={{ fontSize: '0.75rem', color: 'var(--clr-text-muted)', fontWeight: 600, textTransform: 'uppercase', letterSpacing: '0.06em' }}>{label}</div>
          </div>
        ))}
      </div>

      {/* Table */}
      <div className="card animate-fadeIn" style={{ padding: 0, overflow: 'hidden', animationDelay: '150ms' }}>
        <div className="table-wrapper" style={{ borderRadius: 0, border: 'none' }}>
          <table>
            <thead>
              <tr>
                <th>Patient</th>
                <th>Age / Gender</th>
                <th>Blood</th>
                <th>Assigned Doctor</th>
                <th>Status</th>
                <th>Next Visit</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {filtered.map(p => (
                <tr key={p.id}>
                  <td>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                      <div className="avatar" style={{ width: 32, height: 32, fontSize: '0.7rem', flexShrink: 0 }}>{p.avatar}</div>
                      <span style={{ fontWeight: 600, color: 'var(--clr-text-primary)' }}>{p.name}</span>
                    </div>
                  </td>
                  <td>{p.age} / {p.gender === 'F' ? 'Female' : 'Male'}</td>
                  <td>
                    <span style={{
                      padding: '2px 8px', borderRadius: 'var(--r-sm)',
                      background: `${BLOOD_COLORS[p.bloodType] || '#94a3b8'}22`,
                      color: BLOOD_COLORS[p.bloodType] || '#94a3b8',
                      fontSize: '0.75rem', fontWeight: 700,
                      border: `1px solid ${BLOOD_COLORS[p.bloodType] || '#94a3b8'}44`,
                    }}>
                      {p.bloodType || 'Unknown'}
                    </span>
                  </td>
                  <td>{p.doctor}</td>
                  <td><span className={STATUS_COLORS[p.status]}>{p.status}</span></td>
                  <td style={{ fontFamily: 'var(--font-mono)', fontSize: '0.8rem' }}>{p.nextVisit}</td>
                  <td>
                    <div style={{ display: 'flex', gap: 6 }}>
                      <button className="icon-btn" style={{ width: 30, height: 30 }} title="View" onClick={() => setSelected(p)}>
                        <Eye size={14} />
                      </button>
                      <button className="icon-btn" style={{ width: 30, height: 30 }} title="Edit">
                        <Edit size={14} />
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
              {filtered.length === 0 && (
                <tr>
                  <td colSpan={8} style={{ textAlign: 'center', padding: 40, color: 'var(--clr-text-muted)' }}>
                    <User size={32} style={{ marginBottom: 8, opacity: 0.3 }} /><br />
                    No patients found
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>

      {selected && <PatientModal patient={selected} onClose={() => setSelected(null)} />}
      {showAdd && <AddPatientModal onClose={() => setShowAdd(false)} />}
    </Layout>
  );
}
