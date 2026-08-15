import { useState, useEffect } from 'react';
import Layout from '../components/Layout';
import { useData } from '../context/DataContext';
import {
  Search, Plus, X, Edit, Trash2, Lock, User, Mail, Phone, Users, CheckCircle, AlertCircle
} from 'lucide-react';

const STATUS_DOT = {
  online:  { color: '#10b981', label: 'On Duty' },
  away:    { color: '#f59e0b', label: 'Away'    },
  offline: { color: '#64748b', label: 'Off Duty' },
};

/* ── Unified Staff Form Modal ──────────────────────────────── */
function StaffFormModal({ staff, onClose, role = 'receptionist' }) {
  const { addStaff, updateStaff } = useData();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState(false);
  
  const isEdit = !!staff;
  const accentColor = '#10b981'; // Clinic Green for Receptionists
  
  const [formData, setFormData] = useState({
    username: staff?.username || '',
    password: '',
    full_name: staff?.name || '',
    email: staff?.email || '',
    personal_email: staff?.personal_email || '',
    phone: staff?.phone || '',
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
        role: staff.role || role
      });
    } else {
      setFormData({
        username: '', password: '', full_name: '', email: '', personal_email: '', phone: '', role: role
      });
    }
  }, [staff, role]);

  const handleSubmit = async (e) => {
    e.preventDefault();
    setLoading(true);
    setError('');
    
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
    if (isEdit && !payload.password) delete payload.password;

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
      setError(res.error || `Failed to ${isEdit ? 'update' : 'add'} receptionist`);
      setLoading(false);
    }
  };

  return (
    <div className="modal-overlay" onClick={onClose}>
      <form className="modal animate-scaleIn" onClick={e => e.stopPropagation()} onSubmit={handleSubmit} style={{ maxWidth: 500, padding: 0, overflow: 'hidden' }}>
        <div style={{ padding: '24px 32px', background: accentColor, color: 'white' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
             <h2 style={{ margin: 0, fontSize: '1.25rem', fontWeight: 800 }}>
               {isEdit ? 'Edit' : 'Add'} Receptionist
             </h2>
             <button type="button" onClick={onClose} style={{ background: 'none', border: 'none', color: 'white', cursor: 'pointer', opacity: 0.8 }}><X size={20}/></button>
          </div>
          <p style={{ margin: '4px 0 0', opacity: 0.9, fontSize: '0.85rem' }}>
            {isEdit ? 'Update front-desk staff details.' : 'Register a new receptionist for clinic operations.'}
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
              <CheckCircle size={18} /> Receptionist {isEdit ? 'updated' : 'added'} successfully!
            </div>
          )}

          <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
            <div className="form-group">
              <label className="form-label" style={{ fontWeight: 700, color: 'var(--clr-text-muted)' }}>Full Name</label>
              <div style={{ position: 'relative' }}>
                <User size={16} style={{ position: 'absolute', left: 14, top: '50%', transform: 'translateY(-50%)', color: accentColor }} />
                <input className="form-input" style={{ paddingLeft: 42 }} placeholder="Receptionist Name" required 
                  value={formData.full_name} onChange={e => setFormData({...formData, full_name: e.target.value})} />
              </div>
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 20 }}>
              <div className="form-group">
                <label className="form-label" style={{ fontWeight: 700, color: 'var(--clr-text-muted)' }}>Username</label>
                <input className="form-input" placeholder="rec_user" required 
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
                  <Lock size={16} style={{ position: 'absolute', left: 14, top: '50%', transform: 'translateY(-50%)', color: accentColor }} />
                  <input className="form-input" style={{ paddingLeft: 42 }} type="password" placeholder="••••••••" required={!isEdit}
                    value={formData.password} onChange={e => setFormData({...formData, password: e.target.value})} />
                </div>
              </div>
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 20 }}>
              <div className="form-group">
                <label className="form-label" style={{ fontWeight: 700, color: 'var(--clr-text-muted)' }}>Clinic Email (used for login)</label>
                <div style={{ position: 'relative' }}>
                  <Mail size={16} style={{ position: 'absolute', left: 14, top: '50%', transform: 'translateY(-50%)', color: accentColor }} />
                  <input className="form-input" style={{ paddingLeft: 42, fontWeight: 600 }} type="email" placeholder={`username@${formData.role}.com`}
                    value={formData.email} onChange={e => setFormData({...formData, email: e.target.value})} />
                </div>
              </div>
              <div className="form-group">
                <label className="form-label" style={{ fontWeight: 700, color: 'var(--clr-text-muted)' }}>Personal Email (used for recovery)</label>
                <div style={{ position: 'relative' }}>
                  <Mail size={16} style={{ position: 'absolute', left: 14, top: '50%', transform: 'translateY(-50%)', color: accentColor }} />
                  <input className="form-input" style={{ paddingLeft: 42 }} type="email" placeholder="personal@example.com" required 
                    value={formData.personal_email} onChange={e => setFormData({...formData, personal_email: e.target.value})} />
                </div>
              </div>
            </div>

            <div className="form-group">
              <label className="form-label" style={{ fontWeight: 700, color: 'var(--clr-text-muted)' }}>Phone Number</label>
              <div style={{ position: 'relative' }}>
                <Phone size={16} style={{ position: 'absolute', left: 14, top: '50%', transform: 'translateY(-50%)', color: accentColor }} />
                <input className="form-input" style={{ paddingLeft: 42 }} placeholder="+1 234..." 
                  value={formData.phone} onChange={e => setFormData({...formData, phone: e.target.value})} />
              </div>
            </div>
          </div>

          <div style={{ display: 'flex', gap: 16, marginTop: 40 }}>
            <button type="submit" className="btn btn-primary" style={{ flex: 1, padding: '14px', borderRadius: 12, fontWeight: 700, background: accentColor, borderColor: accentColor }} disabled={loading || success}>
              {loading ? 'Processing...' : isEdit ? 'Save Changes' : 'Add Receptionist'}
            </button>
            <button type="button" className="btn btn-ghost" onClick={onClose} style={{ padding: '14px 24px', borderRadius: 12, fontWeight: 700 }}>Cancel</button>
          </div>
        </div>
      </form>
    </div>
  );
}

function ReceptionistCard({ staff, onEdit, onDelete }) {
  const initials = staff.name.split(' ').map(n => n[0]).join('').toUpperCase().slice(0, 2);
  const s = STATUS_DOT[staff.status] || STATUS_DOT.online;
  const accentColor = '#10b981';
  
  return (
    <div className="card hover-scale" style={{ padding: 24, borderRadius: 20, border: '1px solid var(--clr-border)', position: 'relative', overflow: 'hidden' }}>
      <div style={{ position: 'absolute', top: 0, left: 0, width: '100%', height: 4, background: accentColor }} />
      
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 20 }}>
        <div className="avatar-wrap">
          <div className="avatar" style={{ width: 56, height: 56, fontSize: '1.25rem', background: accentColor, fontWeight: 800 }}>{initials}</div>
          <span className="status-dot" style={{ background: s.color, bottom: 2, right: 2, border: '3px solid white', width: 14, height: 14 }} />
        </div>
        <div style={{ display: 'flex', gap: 6 }}>
           <button className="icon-btn" onClick={() => onEdit(staff)} title="Edit Profile" style={{ background: '#f8fafc', color: '#64748b' }}>
             <Edit size={16} />
           </button>
           <button className="icon-btn" onClick={() => onDelete(staff)} title="Deactivate" style={{ background: '#fef2f2', color: '#ef4444' }}>
             <Trash2 size={16} />
           </button>
        </div>
      </div>

      <div style={{ marginBottom: 16 }}>
        <div style={{ fontWeight: 800, fontSize: '1.1rem', color: 'var(--clr-text)', marginBottom: 2 }}>{staff.name}</div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <span className="badge" style={{ background: 'rgba(16, 185, 129, 0.1)', color: accentColor, fontSize: '0.7rem', fontWeight: 700, textTransform: 'uppercase' }}>Receptionist</span>
          <span style={{ fontSize: '0.8rem', color: 'var(--clr-text-muted)', fontWeight: 600 }}>Front Desk</span>
        </div>
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 10, padding: '16px 0', borderTop: '1px solid #f1f5f9' }}>
         <div style={{ display: 'flex', alignItems: 'center', gap: 10, fontSize: '0.85rem', color: 'var(--clr-text-muted)' }} title="Clinic Email">
            <Mail size={14} style={{ color: accentColor }} /> {staff.email}
         </div>
         {staff.personal_email && (
           <div style={{ display: 'flex', alignItems: 'center', gap: 10, fontSize: '0.85rem', color: 'var(--clr-text-muted)' }} title="Personal Email">
              <Mail size={14} style={{ color: '#94a3b8' }} /> {staff.personal_email}
           </div>
         )}
         <div style={{ display: 'flex', alignItems: 'center', gap: 10, fontSize: '0.85rem', color: 'var(--clr-text-muted)' }}>
            <Phone size={14} style={{ color: accentColor }} /> {staff.phone || 'No phone'}
         </div>
      </div>
    </div>
  );
}

export default function Receptionists() {
  const { receptionists, deleteStaff } = useData();
  const [search, setSearch]   = useState('');
  const [editingStaff, setEditingStaff] = useState(null);
  const [showAdd, setShowAdd] = useState(false);

  const filtered = receptionists.filter(r => 
    r.name.toLowerCase().includes(search.toLowerCase()) ||
    r.email.toLowerCase().includes(search.toLowerCase())
  );

  const handleDelete = async (staff) => {
    if (window.confirm(`Are you sure you want to deactivate ${staff.name}?`)) {
      await deleteStaff(staff.id);
    }
  };

  return (
    <Layout pageTitle="Receptionist Management" pageSubtitle={`${receptionists.length} administrative staff registered`}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 16, marginBottom: 40, flexWrap: 'wrap' }}>
        <div style={{ position: 'relative', flex: 1, minWidth: 300 }}>
          <Search size={18} style={{ position: 'absolute', left: 16, top: '50%', transform: 'translateY(-50%)', color: 'var(--clr-text-muted)' }} />
          <input className="form-input" style={{ paddingLeft: 48, borderRadius: 14, height: 48, border: '1px solid var(--clr-border)' }}
            placeholder="Search by name or email..." value={search} onChange={e => setSearch(e.target.value)} />
        </div>
        <button className="btn btn-primary" onClick={() => setShowAdd(true)} style={{ height: 48, padding: '0 24px', borderRadius: 14, fontWeight: 700, display: 'flex', alignItems: 'center', gap: 10, background: '#10b981', borderColor: '#10b981' }}>
          <Plus size={20} /> Add New Receptionist
        </button>
      </div>

      {filtered.length === 0 ? (
        <div className="card" style={{ textAlign: 'center', padding: '80px 40px', borderRadius: 24 }}>
           <div style={{ width: 80, height: 80, background: '#f8fafc', borderRadius: '50%', display: 'grid', placeItems: 'center', margin: '0 auto 24px' }}>
              <Users size={40} style={{ color: '#cbd5e1' }} />
           </div>
           <h3 style={{ fontSize: '1.25rem', fontWeight: 800, marginBottom: 8 }}>No Receptionists Found</h3>
           <p style={{ color: 'var(--clr-text-muted)', maxWidth: 300, margin: '0 auto' }}>
             We couldn't find any receptionists matching "{search}".
           </p>
        </div>
      ) : (
        <div className="grid-3 stagger animate-fadeIn">
          {filtered.map(staff => (
            <ReceptionistCard key={staff.id} staff={staff} onEdit={setEditingStaff} onDelete={handleDelete} />
          ))}
        </div>
      )}

      {(showAdd || editingStaff) && (
        <StaffFormModal 
          staff={editingStaff} 
          role="receptionist" 
          onClose={() => { setShowAdd(false); setEditingStaff(null); }} 
        />
      )}
    </Layout>
  );
}
