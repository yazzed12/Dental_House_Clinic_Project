import React, { useState, useEffect } from 'react';
import { X, Calendar, Clock, User, FileText, CheckCircle, AlertCircle, Edit3, Save, Stethoscope, Search, Plus, Check } from 'lucide-react';
import { createAppointmentCondition, listAppointmentConditions } from '../services/clinicalReferenceApi.js';

const STATUSES = ['Pending', 'Confirmed', 'Completed', 'Cancelled', 'Missed'];
const TYPES = ['Consultation', 'Follow-up', 'Check-up', 'Urgent', 'Therapy', 'Surgery Prep'];

const STATUS_COLORS = {
  Confirmed: '#10b981', Pending: '#f59e0b',
  Completed: '#10b981', Cancelled: '#ef4444', Missed: '#6b7280',
};

/* ── Detail Modal ──────────────────────────────────────────── */
export function DetailModal({ appointment, patients, onClose, onEdit, onStatusChange }) {
  const patient = patients?.find(p => p.name === appointment.patient || p.id === appointment.patient_id);
  const statusColor = STATUS_COLORS[appointment.status] || '#6b7280';

  return (
    <div className="modal-overlay" onClick={onClose} style={{ position:'fixed',inset:0,zIndex:99999,display:'flex',alignItems:'center',justifyContent:'center',padding:20,backgroundColor:'rgba(0,0,0,0.45)',backdropFilter:'blur(3px)' }}>
      <div className="card animate-fadeIn" onClick={e=>e.stopPropagation()} style={{ maxWidth:520,width:'100%',padding:0,overflow:'hidden',borderRadius:16 }}>
        {/* Header */}
        <div style={{ padding:'20px 24px',borderBottom:'1px solid var(--clr-border)',display:'flex',alignItems:'center',justifyContent:'space-between' }}>
          <div style={{ display:'flex',alignItems:'center',gap:12 }}>
            <div style={{ width:40,height:40,borderRadius:10,background:'var(--clr-primary-light)',display:'grid',placeItems:'center' }}>
              <Stethoscope size={18} color="var(--clr-primary-dark)" />
            </div>
            <div>
              <h2 style={{ margin:0,fontSize:'1.1rem',fontWeight:800,color:'var(--clr-text)' }}>Appointment Details</h2>
              <p style={{ margin:0,fontSize:'0.75rem',color:'var(--clr-subtext)' }}>{appointment.displayId || '—'}</p>
            </div>
          </div>
          <button onClick={onClose} style={{ background:'none',border:'none',cursor:'pointer',color:'var(--clr-subtext)',padding:4 }}><X size={18}/></button>
        </div>

        {/* Body */}
        <div style={{ padding:'20px 24px',display:'flex',flexDirection:'column',gap:16 }}>
          {/* Patient Info */}
          <div style={{ display:'flex',alignItems:'center',gap:14,padding:14,background:'var(--clr-bg)',borderRadius:10,border:'1px solid var(--clr-border)' }}>
            <div className="avatar" style={{ width:44,height:44,fontSize:'0.85rem' }}>
              {(appointment.patient||'U').split(' ').map(n=>n[0]).join('').toUpperCase().slice(0,2)}
            </div>
            <div style={{ flex:1 }}>
              <div style={{ fontWeight:800,fontSize:'0.95rem',color:'var(--clr-text)' }}>{appointment.patient||'Unknown'}</div>
              <div style={{ fontSize:'0.78rem',color:'var(--clr-subtext)',marginTop:2 }}>
                {patient?.phone||'No phone'} {patient?.age ? `• Age ${patient.age}` : ''} {patient?.gender ? `• ${patient.gender}` : ''}
              </div>
            </div>
          </div>

          {/* Details Grid */}
          <div style={{ display:'grid',gridTemplateColumns:'1fr 1fr',gap:12 }}>
            {[
              { icon: Calendar, label:'Date', value: appointment.date||'—' },
              { icon: Clock, label:'Time', value: appointment.time||'—' },
              { icon: FileText, label:'Type', value: appointment.type||'—' },
              { icon: User, label:'Doctor', value: appointment.doctor||'—' },
            ].map(item => (
              <div key={item.label} style={{ padding:12,background:'var(--clr-bg)',borderRadius:8,border:'1px solid var(--clr-border)' }}>
                <div style={{ display:'flex',alignItems:'center',gap:6,fontSize:'0.68rem',color:'var(--clr-subtext)',fontWeight:700,textTransform:'uppercase',marginBottom:4 }}>
                  <item.icon size={12}/> {item.label}
                </div>
                <div style={{ fontSize:'0.88rem',fontWeight:700,color:'var(--clr-text)' }}>{item.value}</div>
              </div>
            ))}
          </div>

          {/* Visit Reason Banner */}
          <div style={{ padding:12,background:'var(--clr-primary-light)',borderRadius:8,border:'1px solid rgba(16,185,129,0.15)' }}>
            <div style={{ display:'flex',alignItems:'center',gap:6,fontSize:'0.68rem',color:'var(--clr-primary-dark)',fontWeight:700,textTransform:'uppercase',marginBottom:4 }}>
              <Stethoscope size={12}/> Visit Reason / Dental Condition
            </div>
            <div style={{ fontSize:'0.9rem',fontWeight:800,color:'var(--clr-primary-dark)' }}>{appointment.condition || 'Routine Checkup'}</div>
          </div>

          {/* Status */}
          <div style={{ padding:14,background:'var(--clr-bg)',borderRadius:10,border:'1px solid var(--clr-border)' }}>
            <div style={{ fontSize:'0.7rem',color:'var(--clr-subtext)',fontWeight:700,textTransform:'uppercase',marginBottom:8 }}>Status</div>
            <div style={{ display:'flex',flexWrap:'wrap',gap:6 }}>
              {STATUSES.map(s => (
                <button key={s} onClick={() => onStatusChange(appointment.id, s)}
                  style={{
                    padding:'6px 14px',borderRadius:999,fontSize:'0.75rem',fontWeight:700,cursor:'pointer',
                    border: appointment.status===s ? `2px solid ${STATUS_COLORS[s]||'#6b7280'}` : '1px solid var(--clr-border)',
                    background: appointment.status===s ? `${STATUS_COLORS[s]||'#6b7280'}18` : 'transparent',
                    color: appointment.status===s ? STATUS_COLORS[s]||'#6b7280' : 'var(--clr-subtext)',
                    transition:'all 0.15s',
                  }}>{s}</button>
              ))}
            </div>
          </div>

          {/* Notes */}
          {appointment.notes && (
            <div style={{ padding:12,background:'var(--clr-bg)',borderRadius:8,border:'1px solid var(--clr-border)' }}>
              <div style={{ fontSize:'0.7rem',color:'var(--clr-subtext)',fontWeight:700,textTransform:'uppercase',marginBottom:4 }}>Notes</div>
              <div style={{ fontSize:'0.84rem',color:'var(--clr-text)' }}>{appointment.notes}</div>
            </div>
          )}

          {/* Report placeholder */}
          <div style={{ padding:14,background:'var(--clr-bg)',borderRadius:10,border:'1px dashed var(--clr-border)',textAlign:'center' }}>
            <FileText size={20} style={{ color:'var(--clr-text-light)',marginBottom:4 }}/>
            <div style={{ fontSize:'0.8rem',color:'var(--clr-subtext)',fontWeight:600 }}>No clinical report linked yet</div>
            <div style={{ fontSize:'0.72rem',color:'var(--clr-text-light)',marginTop:2 }}>Reports are generated during consultations</div>
          </div>
        </div>

        {/* Footer */}
        <div style={{ padding:'14px 24px',borderTop:'1px solid var(--clr-border)',display:'flex',gap:10,justifyContent:'flex-end' }}>
          <button className="btn btn-secondary" onClick={onClose} style={{ fontSize:'0.82rem' }}>Close</button>
          <button className="btn btn-primary" onClick={() => { onClose(); onEdit(appointment); }} style={{ fontSize:'0.82rem',display:'flex',alignItems:'center',gap:6 }}>
            <Edit3 size={14}/> Edit
          </button>
        </div>
      </div>
    </div>
  );
}

/* ── Edit Modal ────────────────────────────────────────────── */
export function EditModal({ appointment, patients, doctors, onClose, onSave }) {
  const [form, setForm] = useState({
    date: appointment.date || '',
    time: appointment.time || '',
    type: appointment.type || 'Consultation',
    status: appointment.status || 'Pending',
    notes: appointment.notes || '',
    patient: appointment.patient || '',
    condition: appointment.condition || 'Routine Checkup',
  });
  const [saving, setSaving] = useState(false);
  const [feedback, setFeedback] = useState(null);

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (!form.date || !form.time) {
      setFeedback({ type:'error', msg:'Date and time are required.' });
      return;
    }
    setSaving(true);
    setFeedback(null);
    try {
      await onSave(appointment.id, form);
      setFeedback({ type:'success', msg:'Appointment updated!' });
      setTimeout(onClose, 800);
    } catch {
      setFeedback({ type:'error', msg:'Failed to save changes.' });
    } finally {
      setSaving(false);
    }
  };

  const set = (k,v) => setForm(p => ({ ...p, [k]: v }));

  return (
    <div className="modal-overlay" onClick={onClose} style={{ position:'fixed',inset:0,zIndex:99999,display:'flex',alignItems:'center',justifyContent:'center',padding:20,backgroundColor:'rgba(0,0,0,0.45)',backdropFilter:'blur(3px)' }}>
      <form className="card animate-fadeIn" onClick={e=>e.stopPropagation()} onSubmit={handleSubmit} style={{ maxWidth:480,width:'100%',padding:0,overflow:'hidden',borderRadius:16 }}>
        {/* Header */}
        <div style={{ padding:'20px 24px',borderBottom:'1px solid var(--clr-border)',display:'flex',alignItems:'center',justifyContent:'space-between' }}>
          <div style={{ display:'flex',alignItems:'center',gap:10 }}>
            <div style={{ width:36,height:36,borderRadius:8,background:'rgba(139,92,246,0.1)',display:'grid',placeItems:'center' }}>
              <Edit3 size={16} color="#8b5cf6"/>
            </div>
            <h2 style={{ margin:0,fontSize:'1.05rem',fontWeight:800,color:'var(--clr-text)' }}>Edit Appointment</h2>
          </div>
          <button type="button" onClick={onClose} style={{ background:'none',border:'none',cursor:'pointer',color:'var(--clr-subtext)' }}><X size={18}/></button>
        </div>

        {/* Body */}
        <div style={{ padding:'20px 24px',display:'flex',flexDirection:'column',gap:14 }}>
          {feedback && (
            <div style={{ padding:'10px 14px',borderRadius:8,fontSize:'0.82rem',fontWeight:600,display:'flex',alignItems:'center',gap:8,
              background: feedback.type==='success' ? 'var(--clr-primary-light)' : 'rgba(239,68,68,0.08)',
              color: feedback.type==='success' ? 'var(--clr-primary-dark)' : '#dc2626',
              border: `1px solid ${feedback.type==='success' ? 'rgba(16,185,129,0.2)' : 'rgba(239,68,68,0.15)'}`,
            }}>
              {feedback.type==='success' ? <CheckCircle size={14}/> : <AlertCircle size={14}/>}
              {feedback.msg}
            </div>
          )}

          <div className="form-group">
            <label className="form-label">Patient</label>
            <input className="form-input" value={form.patient} disabled style={{ opacity:0.6 }}/>
          </div>

          <div style={{ display:'grid',gridTemplateColumns:'1fr 1fr',gap:12 }}>
            <div className="form-group">
              <label className="form-label">Date</label>
              <input className="form-input" type="date" required value={form.date} onChange={e=>set('date',e.target.value)}/>
            </div>
            <div className="form-group">
              <label className="form-label">Time</label>
              <input className="form-input" type="time" required value={form.time} onChange={e=>set('time',e.target.value)}/>
            </div>
          </div>

          <div style={{ display:'grid',gridTemplateColumns:'1fr 1fr',gap:12 }}>
            <div className="form-group">
              <label className="form-label">Type</label>
              <select className="form-select" value={form.type} onChange={e=>set('type',e.target.value)} style={{ width:'100%' }}>
                {TYPES.map(t => <option key={t}>{t}</option>)}
              </select>
            </div>
            <div className="form-group">
              <label className="form-label">Status</label>
              <select className="form-select" value={form.status} onChange={e=>set('status',e.target.value)} style={{ width:'100%' }}>
                {STATUSES.map(s => <option key={s}>{s}</option>)}
              </select>
            </div>
          </div>

          <div className="form-group">
            <label className="form-label">Visit Reason / Dental Condition</label>
            <ConditionSelect value={form.condition} onChange={val => set('condition', val)} />
          </div>

          <div className="form-group">
            <label className="form-label">Notes</label>
            <textarea className="form-input" rows={3} placeholder="Optional notes..." value={form.notes} onChange={e=>set('notes',e.target.value)} style={{ resize:'vertical',minHeight:60 }}/>
          </div>
        </div>

        {/* Footer */}
        <div style={{ padding:'14px 24px',borderTop:'1px solid var(--clr-border)',display:'flex',gap:10,justifyContent:'flex-end' }}>
          <button type="button" className="btn btn-secondary" onClick={onClose}>Cancel</button>
          <button type="submit" className="btn btn-primary" disabled={saving} style={{ display:'flex',alignItems:'center',gap:6 }}>
            <Save size={14}/> {saving ? 'Saving…' : 'Save Changes'}
          </button>
        </div>
      </form>
    </div>
  );
}

export function ConditionSelect({ value, onChange }) {
  const [conditions, setConditions] = useState([]);
  const [search, setSearch] = useState('');
  const [isOpen, setIsOpen] = useState(false);
  const [promptCustom, setPromptCustom] = useState(null);

  const defaults = [
    'Routine Checkup', 'Dental Pain', 'Tooth Sensitivity', 'Swelling',
    'Bleeding Gums', 'Tooth Mobility', 'Fractured Tooth', 'Tooth Decay',
    'Root Canal Treatment', 'Crown Placement', 'Extraction Consultation',
    'Orthodontic Consultation', 'Gum Infection', 'Wisdom Tooth Pain',
    'Follow-up Visit', 'Cosmetic Dentistry', 'Teeth Cleaning',
    'Implant Consultation', 'Emergency Visit', 'Other'
  ];

  useEffect(() => {
    listAppointmentConditions()
      .then(data => {
        const fetchedNames = data.map(c => c.name);
        const unique = Array.from(new Set([...defaults, ...fetchedNames]));
        setConditions(unique);
      })
      .catch(err => {
        console.error("Error fetching conditions:", err);
        setConditions(defaults);
      });
  }, []);

  const handleSelect = (name) => {
    onChange(name);
    setIsOpen(false);
    setSearch('');
  };

  const handleCreateCustom = (name) => {
    if (!name.trim()) return;
    const cleanName = name.trim();
    setPromptCustom({ name: cleanName });
  };

  const confirmCustom = async (saveGlobally) => {
    const name = promptCustom.name;
    setPromptCustom(null);
    if (saveGlobally) {
      try {
        const added = await createAppointmentCondition(name);
        setConditions(prev => Array.from(new Set([...prev, added.name])));
      } catch (err) {
        console.error("Error saving global condition:", err);
      }
    }
    onChange(name);
    setIsOpen(false);
    setSearch('');
  };

  const filtered = conditions.filter(c => c.toLowerCase().includes(search.toLowerCase()));

  return (
    <div style={{ position: 'relative' }}>
      <div 
        onClick={() => setIsOpen(!isOpen)}
        style={{
          padding: '8px 12px',
          border: '1px solid var(--clr-border)',
          borderRadius: 8,
          background: 'var(--clr-card)',
          fontSize: '0.85rem',
          cursor: 'pointer',
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center'
        }}
      >
        <span>{value || 'Select a reason / condition...'}</span>
        <span style={{ fontSize: '0.7rem', color: 'var(--clr-subtext)' }}>▼</span>
      </div>

      {isOpen && (
        <div style={{
          position: 'absolute',
          top: '100%',
          left: 0,
          right: 0,
          zIndex: 999999,
          background: 'var(--clr-card)',
          border: '1px solid var(--clr-border)',
          borderRadius: 8,
          boxShadow: '0 4px 12px rgba(0,0,0,0.1)',
          marginTop: 4,
          padding: 8,
          display: 'flex',
          flexDirection: 'column',
          gap: 6,
          maxHeight: 220,
          overflowY: 'auto'
        }}>
          <div style={{ position: 'relative', display: 'flex', alignItems: 'center' }} onClick={e => e.stopPropagation()}>
            <Search size={13} style={{ position: 'absolute', left: 8, color: 'var(--clr-subtext)' }} />
            <input 
              className="form-input"
              value={search}
              onChange={e => setSearch(e.target.value)}
              placeholder="Search or add custom reason..."
              style={{ paddingLeft: 26, fontSize: '0.78rem', margin: 0, height: 30 }}
            />
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: 2, overflowY: 'auto', flex: 1 }}>
            {filtered.map(c => (
              <div 
                key={c}
                onClick={() => handleSelect(c)}
                style={{
                  padding: '6px 10px',
                  borderRadius: 6,
                  cursor: 'pointer',
                  fontSize: '0.82rem',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'space-between',
                  background: value === c ? 'var(--clr-primary-light)' : 'transparent',
                  color: value === c ? 'var(--clr-primary-dark)' : 'var(--clr-text)'
                }}
                onMouseEnter={e => {
                  if (value !== c) e.currentTarget.style.background = 'var(--clr-bg)';
                }}
                onMouseLeave={e => {
                  if (value !== c) e.currentTarget.style.background = 'transparent';
                }}
              >
                <span>{c}</span>
                {value === c && <Check size={12} />}
              </div>
            ))}

            {search.trim() && !conditions.some(c => c.toLowerCase() === search.trim().toLowerCase()) && (
              <div 
                onClick={() => handleCreateCustom(search)}
                style={{
                  padding: '6px 10px',
                  borderRadius: 6,
                  cursor: 'pointer',
                  fontSize: '0.82rem',
                  background: 'var(--clr-primary-light)',
                  color: 'var(--clr-primary)',
                  display: 'flex',
                  alignItems: 'center',
                  gap: 6,
                  fontWeight: 600
                }}
              >
                <Plus size={12} /> Add "{search.trim()}"
              </div>
            )}
          </div>
        </div>
      )}

      {promptCustom && (
        <div 
          onClick={e => e.stopPropagation()}
          style={{
            position: 'fixed',
            inset: 0,
            zIndex: 9999999,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            backgroundColor: 'rgba(0,0,0,0.4)',
            backdropFilter: 'blur(2px)'
          }}
        >
          <div className="card animate-fadeIn" style={{ maxWidth: 360, width: '100%', padding: 20, textAlign: 'center', borderRadius: 12 }}>
            <h4 style={{ margin: 0, fontSize: '0.95rem', fontWeight: 800 }}>Save condition globally?</h4>
            <p style={{ fontSize: '0.8rem', color: 'var(--clr-subtext)', margin: '8px 0 16px' }}>
              Do you want to save "{promptCustom.name}" for future appointments?
            </p>
            <div style={{ display: 'flex', gap: 10, justifyContent: 'center' }}>
              <button 
                type="button" 
                className="btn btn-secondary btn-sm" 
                onClick={() => confirmCustom(false)}
                style={{ fontSize: '0.78rem' }}
              >
                No, use once
              </button>
              <button 
                type="button" 
                className="btn btn-primary btn-sm" 
                onClick={() => confirmCustom(true)}
                style={{ fontSize: '0.78rem' }}
              >
                Yes, save globally
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
