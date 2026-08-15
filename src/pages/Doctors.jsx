import { useState, useEffect } from 'react';
import Layout from '../components/Layout';
import { useData } from '../context/DataContext';
import {
  Users, Clock, Award, Phone, Mail,
  Plus, Search, X, Edit, Trash2, Lock, User, CheckCircle, AlertCircle, Stethoscope
} from 'lucide-react';

const STATUS_DOT = {
  online:  { color: '#10b981', label: 'On Duty' },
  away:    { color: '#f59e0b', label: 'Away'    },
  offline: { color: '#64748b', label: 'Off Duty' },
};

/* ── Unified Staff Form Modal ──────────────────────────────── */
function StaffFormModal({ staff, onClose, role = 'doctor' }) {
  const { addStaff, updateStaff } = useData();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState(false);
  
  const isEdit = !!staff;
  
  const [formData, setFormData] = useState({
    username: staff?.username || '',
    password: '',
    full_name: staff?.name || '',
    email: staff?.email || '',
    personal_email: staff?.personal_email || '',
    phone: staff?.phone || '',
    specialization: staff?.specialization || '',
    role: staff?.role || role
  });

  useEffect(() => {
    if (staff) {
      setFormData({
        username: staff.username || '',
        password: '',
        full_name: staff.name || '',
        email: staff.email || '',
        personal_email: staff.personal_email || '',
        phone: staff.phone || '',
        specialization: staff.specialization || '',
        role: staff.role || role
      });
    } else {
      setFormData({
        username: '', password: '', full_name: '', email: '', personal_email: '', phone: '', specialization: '', role: role
      });
    }
  }, [staff, role]);

  const handleSubmit = async (e) => {
    e.preventDefault();
    setLoading(true);
    setError('');
    
    // Simple Validation
    if (!formData.full_name || !formData.username || !formData.personal_email) {
      setError('Please fill in all required fields.');
      setLoading(false);
      return;
    }

    if (!isEdit && !formData.password) {
      setError('Password is required for new accounts.');
      setLoading(false);
      return;
    }

    const payload = { ...formData };
    payload.email = (formData.email || '').trim().toLowerCase();
    if (!payload.email) {
      payload.email = formData.username.trim().toLowerCase() + '@' + role + '.com';
    }
    if (isEdit && !payload.password) delete payload.password; // Don't send empty password on edit
    if (role === 'receptionist') delete payload.specialization;

    let res;
    if (isEdit) {
      res = await updateStaff(staff.id, payload);
    } else {
      res = await addStaff(payload);
    }

    if (res.success) {
      setSuccess(true);
      setTimeout(() => {
        onClose();
      }, 1500);
    } else {
      setError(res.error || `Failed to ${isEdit ? 'update' : 'add'} staff member`);
      setLoading(false);
    }
  };

  return (
    <div className="modal-overlay" onClick={onClose}>
      <form className="modal animate-scaleIn" onClick={e => e.stopPropagation()} onSubmit={handleSubmit} style={{ maxWidth: 500, padding: 0, overflow: 'hidden' }}>
        <div style={{ padding: '24px 32px', background: 'var(--clr-primary)', color: 'white' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
             <h2 style={{ margin: 0, fontSize: '1.25rem', fontWeight: 800 }}>
               {isEdit ? 'Edit' : 'Add'} {role === 'doctor' ? 'Doctor' : 'Receptionist'}
             </h2>
             <button type="button" onClick={onClose} style={{ background: 'none', border: 'none', color: 'white', cursor: 'pointer', opacity: 0.8 }}><X size={20}/></button>
          </div>
          <p style={{ margin: '4px 0 0', opacity: 0.9, fontSize: '0.85rem' }}>
            {isEdit ? 'Update existing staff member details.' : 'Register a new member to the clinic system.'}
          </p>
        </div>

        <div style={{ padding: '32px' }}>
          {error && (
            <div style={{ padding: '12px 16px', background: '#fef2f2', border: '1px solid #fee2e2', color: '#b91c1c', borderRadius: 12, fontSize: '0.85rem', marginBottom: 24, display: 'flex', alignItems: 'center', gap: 10 }}>
              <AlertCircle size={18} /> {error}
            </div>
          )}

          {success && (
            <div style={{ padding: '12px 16px', background: '#f0fdf4', border: '1px solid #dcfce7', color: '#15803d', borderRadius: 12, fontSize: '0.85rem', marginBottom: 24, display: 'flex', alignItems: 'center', gap: 10 }}>
              <CheckCircle size={18} /> Staff member {isEdit ? 'updated' : 'added'} successfully!
            </div>
          )}

          <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
            <div className="form-group">
              <label className="form-label" style={{ fontWeight: 700, color: 'var(--clr-text-muted)' }}>Full Name</label>
              <div style={{ position: 'relative' }}>
                <User size={16} style={{ position: 'absolute', left: 14, top: '50%', transform: 'translateY(-50%)', color: 'var(--clr-primary)' }} />
                <input className="form-input" style={{ paddingLeft: 42 }} placeholder="Dr. Jane Smith" required 
                  value={formData.full_name} onChange={e => setFormData({...formData, full_name: e.target.value})} />
              </div>
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 20 }}>
              <div className="form-group">
                <label className="form-label" style={{ fontWeight: 700, color: 'var(--clr-text-muted)' }}>Username</label>
                <input className="form-input" placeholder="jsmith" required 
                  value={formData.username} onChange={e => {
                    const val = e.target.value;
                    setFormData(prev => {
                      const updated = { ...prev, username: val };
                      const oldGenerated = prev.username.trim() ? `${prev.username.trim().toLowerCase()}@${prev.role}.com` : '';
                      if (!prev.email || prev.email === oldGenerated || prev.email === `username@${prev.role}.com`) {
                        updated.email = val.trim() ? `${val.trim().toLowerCase()}@${prev.role}.com` : '';
                      }
                      return updated;
                    });
                  }} />
              </div>
              <div className="form-group">
                <label className="form-label" style={{ fontWeight: 700, color: 'var(--clr-text-muted)' }}>{isEdit ? 'New Password (Optional)' : 'Password'}</label>
                <div style={{ position: 'relative' }}>
                  <Lock size={16} style={{ position: 'absolute', left: 14, top: '50%', transform: 'translateY(-50%)', color: 'var(--clr-primary)' }} />
                  <input className="form-input" style={{ paddingLeft: 42 }} type="password" placeholder="••••••••" required={!isEdit}
                    value={formData.password} onChange={e => setFormData({...formData, password: e.target.value})} />
                </div>
              </div>
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 20 }}>
              <div className="form-group">
                <label className="form-label" style={{ fontWeight: 700, color: 'var(--clr-text-muted)' }}>Clinic Email (used for login)</label>
                <div style={{ position: 'relative' }}>
                  <Mail size={16} style={{ position: 'absolute', left: 14, top: '50%', transform: 'translateY(-50%)', color: 'var(--clr-primary)' }} />
                  <input className="form-input" style={{ paddingLeft: 42, fontWeight: 600 }} type="email" placeholder={`username@${formData.role}.com`}
                    value={formData.email} onChange={e => setFormData({...formData, email: e.target.value})} />
                </div>
              </div>
              <div className="form-group">
                <label className="form-label" style={{ fontWeight: 700, color: 'var(--clr-text-muted)' }}>Personal Email (used for recovery)</label>
                <div style={{ position: 'relative' }}>
                  <Mail size={16} style={{ position: 'absolute', left: 14, top: '50%', transform: 'translateY(-50%)', color: 'var(--clr-primary)' }} />
                  <input className="form-input" style={{ paddingLeft: 42 }} type="email" placeholder="personal@example.com" required 
                    value={formData.personal_email} onChange={e => setFormData({...formData, personal_email: e.target.value})} />
                </div>
              </div>
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 20 }}>
              <div className="form-group">
                <label className="form-label" style={{ fontWeight: 700, color: 'var(--clr-text-muted)' }}>Phone Number</label>
                <div style={{ position: 'relative' }}>
                  <Phone size={16} style={{ position: 'absolute', left: 14, top: '50%', transform: 'translateY(-50%)', color: 'var(--clr-primary)' }} />
                  <input className="form-input" style={{ paddingLeft: 42 }} placeholder="+1 234 567 890" 
                    value={formData.phone} onChange={e => setFormData({...formData, phone: e.target.value})} />
                </div>
              </div>
              {role === 'doctor' && (
                <div className="form-group">
                  <label className="form-label" style={{ fontWeight: 700, color: 'var(--clr-text-muted)' }}>Specialization</label>
                  <div style={{ position: 'relative' }}>
                    <Stethoscope size={16} style={{ position: 'absolute', left: 14, top: '50%', transform: 'translateY(-50%)', color: 'var(--clr-primary)' }} />
                    <input className="form-input" style={{ paddingLeft: 42 }} placeholder="e.g. Orthodontics, Periodontics" required 
                      value={formData.specialization} onChange={e => setFormData({...formData, specialization: e.target.value})} />
                  </div>
                </div>
              )}
            </div>
          </div>

          <div style={{ display: 'flex', gap: 16, marginTop: 40 }}>
            <button type="submit" className="btn btn-primary" style={{ flex: 1, padding: '14px', borderRadius: 12, fontWeight: 700 }} disabled={loading || success}>
              {loading ? 'Processing...' : isEdit ? 'Save Changes' : `Add ${role === 'doctor' ? 'Doctor' : 'Receptionist'}`}
            </button>
            <button type="button" className="btn btn-ghost" onClick={onClose} style={{ padding: '14px 24px', borderRadius: 12, fontWeight: 700 }}>Cancel</button>
          </div>
        </div>
      </form>
    </div>
  );
}

function DoctorCard({ doc, onEdit, onDelete }) {
  const initials = doc.name.split(' ').map(n => n[0]).join('').toUpperCase().slice(0, 2);
  const s = STATUS_DOT[doc.status] || STATUS_DOT.online;
  return (
    <div className="card hover-scale" style={{ padding: 24, borderRadius: 20, border: '1px solid var(--clr-border)', position: 'relative', overflow: 'hidden' }}>
      <div style={{ position: 'absolute', top: 0, left: 0, width: '100%', height: 4, background: 'var(--clr-primary)' }} />
      
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 20 }}>
        <div className="avatar-wrap">
          <div className="avatar" style={{ width: 56, height: 56, fontSize: '1.25rem', background: 'var(--clr-primary)', fontWeight: 800 }}>{initials}</div>
          <span className="status-dot" style={{ background: s.color, bottom: 2, right: 2, border: '3px solid white', width: 14, height: 14 }} />
        </div>
        <div style={{ display: 'flex', gap: 6 }}>
           <button className="icon-btn" onClick={() => onEdit(doc)} title="Edit Profile" style={{ background: '#f8fafc', color: '#64748b' }}>
             <Edit size={16} />
           </button>
           <button className="icon-btn" onClick={() => onDelete(doc)} title="Deactivate" style={{ background: '#fef2f2', color: '#ef4444' }}>
             <Trash2 size={16} />
           </button>
        </div>
      </div>

      <div style={{ marginBottom: 16 }}>
        <div style={{ fontWeight: 800, fontSize: '1.1rem', color: 'var(--clr-text)', marginBottom: 2 }}>{doc.name}</div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <span className="badge" style={{ background: 'rgba(59, 130, 246, 0.1)', color: '#3b82f6', fontSize: '0.7rem', fontWeight: 700, textTransform: 'uppercase' }}>Doctor</span>
          <span style={{ fontSize: '0.8rem', color: 'var(--clr-text-muted)', fontWeight: 600 }}>{doc.specialization || 'Dentist'}</span>
        </div>
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 10, padding: '16px 0', borderTop: '1px solid #f1f5f9' }}>
         <div style={{ display: 'flex', alignItems: 'center', gap: 10, fontSize: '0.85rem', color: 'var(--clr-text-muted)' }} title="Clinic Email">
            <Mail size={14} style={{ color: 'var(--clr-primary)' }} /> {doc.email}
         </div>
         {doc.personal_email && (
           <div style={{ display: 'flex', alignItems: 'center', gap: 10, fontSize: '0.85rem', color: 'var(--clr-text-muted)' }} title="Personal Email">
              <Mail size={14} style={{ color: '#94a3b8' }} /> {doc.personal_email}
           </div>
         )}
         <div style={{ display: 'flex', alignItems: 'center', gap: 10, fontSize: '0.85rem', color: 'var(--clr-text-muted)' }}>
            <Phone size={14} style={{ color: 'var(--clr-primary)' }} /> {doc.phone || 'No phone'}
         </div>
      </div>

      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: 16, paddingTop: 16, borderTop: '1px solid #f1f5f9' }}>
         <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
               <Users size={14} style={{ color: 'var(--clr-primary)' }} />
               <span style={{ fontWeight: 700, fontSize: '0.85rem' }}>{doc.patients || 0}</span>
            </div>
            <span style={{ fontSize: '0.75rem', color: 'var(--clr-text-muted)' }}>Patients</span>
         </div>
      </div>
    </div>
  );
}

export default function Doctors() {
  const { doctors, deleteStaff } = useData();
  const [search, setSearch]   = useState('');
  const [editingDoc, setEditingDoc] = useState(null);
  const [showAdd, setShowAdd] = useState(false);

  const filtered = doctors.filter(d => 
    d.name.toLowerCase().includes(search.toLowerCase()) ||
    (d.specialization && d.specialization.toLowerCase().includes(search.toLowerCase()))
  );

  const handleDelete = async (doc) => {
    if (window.confirm(`Are you sure you want to deactivate Dr. ${doc.name}?`)) {
      await deleteStaff(doc.id);
    }
  };

  return (
    <Layout pageTitle="Doctor Management" pageSubtitle={`${doctors.length} healthcare professionals registered`}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 16, marginBottom: 40, flexWrap: 'wrap' }}>
        <div style={{ position: 'relative', flex: 1, minWidth: 300 }}>
          <Search size={18} style={{ position: 'absolute', left: 16, top: '50%', transform: 'translateY(-50%)', color: 'var(--clr-text-muted)' }} />
          <input className="form-input" style={{ paddingLeft: 48, borderRadius: 14, height: 48, border: '1px solid var(--clr-border)' }}
            placeholder="Search by doctor name or specialization..." value={search} onChange={e => setSearch(e.target.value)} />
        </div>
        <button className="btn btn-primary" onClick={() => setShowAdd(true)} style={{ height: 48, padding: '0 24px', borderRadius: 14, fontWeight: 700, display: 'flex', alignItems: 'center', gap: 10 }}>
          <Plus size={20} /> Add New Doctor
        </button>
      </div>

      {filtered.length === 0 ? (
        <div className="card" style={{ textAlign: 'center', padding: '80px 40px', borderRadius: 24 }}>
           <div style={{ width: 80, height: 80, background: '#f8fafc', borderRadius: '50%', display: 'grid', placeItems: 'center', margin: '0 auto 24px' }}>
              <Users size={40} style={{ color: '#cbd5e1' }} />
           </div>
           <h3 style={{ fontSize: '1.25rem', fontWeight: 800, marginBottom: 8 }}>No Doctors Found</h3>
           <p style={{ color: 'var(--clr-text-muted)', maxWidth: 300, margin: '0 auto' }}>
             We couldn't find any doctors matching "{search}". Try a different search term.
           </p>
        </div>
      ) : (
        <div className="grid-3 stagger animate-fadeIn">
          {filtered.map(doc => (
            <DoctorCard key={doc.id} doc={doc} onEdit={setEditingDoc} onDelete={handleDelete} />
          ))}
        </div>
      )}

      {(showAdd || editingDoc) && (
        <StaffFormModal 
          staff={editingDoc} 
          role="doctor" 
          onClose={() => { setShowAdd(false); setEditingDoc(null); }} 
        />
      )}
    </Layout>
  );
}
