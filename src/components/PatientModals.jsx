import { useState, useMemo, useEffect } from 'react';
import { X, User, Calendar, Clock, FileText, Edit3, Save, Phone, Droplets, Activity, Stethoscope, ChevronRight, AlertCircle, CheckCircle, Eye } from 'lucide-react';
import { useAuth } from '../context/AuthContext';
import { fetchConsultationHistory } from '../services/consultationApi';
import { downloadReportPdf, getPatientReports } from '../services/reportApi.js';
import FinalReportSnapshot from './consultation/FinalReportSnapshot.jsx';

/* ── Patient View Modal (tabbed) ───────────────────────────── */
export function PatientViewModal({ patient, appointments, records, onClose, onViewConsultation, onCreateAppointment }) {
  const { user } = useAuth();
  const [tab, setTab] = useState('overview');
  const [reportsList, setReportsList] = useState([]);
  const [loadingReports, setLoadingReports] = useState(false);
  const [reportsError, setReportsError] = useState('');
  const [reportsReload, setReportsReload] = useState(0);
  const [consultationHistory, setConsultationHistory] = useState([]);
  const [loadingConsultations, setLoadingConsultations] = useState(true);
  const [consultationsError, setConsultationsError] = useState('');
  const [selectedConsultation, setSelectedConsultation] = useState(null);

  const handleReportPdf = async (report, action) => {
    const previewWindow = action === 'view' ? window.open('', '_blank') : null;

    try {
      const { blob, headers } = await downloadReportPdf(report.id);
      const contentType = headers.get('content-type') || '';
      if (!contentType.toLowerCase().includes('application/pdf')) {
        throw new Error('The report response was not a PDF');
      }

      const objectUrl = URL.createObjectURL(blob);

      if (action === 'view') {
        if (previewWindow) {
          previewWindow.location.href = objectUrl;
        } else {
          window.open(objectUrl, '_blank', 'noopener,noreferrer');
        }
        window.setTimeout(() => URL.revokeObjectURL(objectUrl), 60000);
        return;
      }

      const disposition = headers.get('content-disposition') || '';
      const encodedFilename = disposition.match(/filename\*=UTF-8''([^;]+)/i)?.[1];
      const plainFilename = disposition.match(/filename="?([^";]+)"?/i)?.[1];
      const safePatientName = (patient.name || 'Patient').replace(/[^a-z0-9 _-]/gi, '').trim();
      const fallbackFilename = `Clinical_Report_${safePatientName || 'Patient'}_${report.tooth_id || 'General'}.pdf`;
      const filename = encodedFilename
        ? decodeURIComponent(encodedFilename)
        : plainFilename || fallbackFilename;

      const link = document.createElement('a');
      link.href = objectUrl;
      link.download = filename;
      document.body.appendChild(link);
      link.click();
      link.remove();
      window.setTimeout(() => URL.revokeObjectURL(objectUrl), 0);
    } catch (error) {
      if (previewWindow) previewWindow.close();
      console.error('Error downloading report PDF:', error);
    }
  };

  useEffect(() => {
    let active = true;
    const timer = setTimeout(() => {
      if (!patient.id || !active) return;
      setLoadingReports(true);
      setReportsError('');
      getPatientReports(patient.id)
      .then(data => {
        if (active) setReportsList(Array.isArray(data) ? data : []);
      })
      .catch(err => {
        console.error("Error fetching patient reports:", err);
        if (active) setReportsError(err.message || 'Clinical reports could not be loaded.');
      })
      .finally(() => {
        if (active) setLoadingReports(false);
      });
    }, 0);
    return () => {
      active = false;
      clearTimeout(timer);
    };
  }, [patient.id, reportsReload]);

  useEffect(() => {
    let active = true;
    if (!patient.id || (user?.role !== 'doctor' && user?.role !== 'admin')) return undefined;
    setConsultationHistory([]);
    setConsultationsError('');
    setLoadingConsultations(true);
    fetchConsultationHistory(patient.id)
      .then(data => {
        if (active) setConsultationHistory(Array.isArray(data) ? data : []);
      })
      .catch(error => {
        console.error('Error fetching consultation history:', error);
        if (active) setConsultationsError(error.message || 'Consultation history could not be loaded.');
      })
      .finally(() => {
        if (active) setLoadingConsultations(false);
      });
    return () => { active = false; };
  }, [patient.id, user?.id, user?.role]);

  const patientAppts = useMemo(() =>
    (appointments || []).filter(a => a.patient_id === patient.id || a.patient === patient.name)
      .sort((a, b) => (b.date || '').localeCompare(a.date || '')),
    [appointments, patient]);

  const patientRecords = useMemo(() =>
    (records || []).filter(r => r.patient_id === patient.id),
    [records, patient]);

  const completedAppts = patientAppts.filter(a => a.status === 'Completed');

  const initials = patient.name ? patient.name.split(' ').map(n => n[0]).join('').toUpperCase().slice(0, 2) : 'P';

  const tabs = [
    { id: 'overview', label: 'Overview' },
    { id: 'appointments', label: `Appointments (${patientAppts.length})` },
  ];

  if (user?.role === 'doctor' || user?.role === 'admin') {
    tabs.splice(1, 0, { id: 'consultations', label: `Consultations (${consultationHistory.length})` });
    tabs.splice(2, 0, { id: 'reports', label: `Reports (${reportsList.length})` });
  }

  return (
    <div className="modal-overlay" onClick={onClose} style={{ position:'fixed',inset:0,zIndex:99999,display:'flex',alignItems:'center',justifyContent:'center',padding:20,backgroundColor:'rgba(0,0,0,0.45)',backdropFilter:'blur(3px)' }}>
      <div className="card animate-fadeIn" onClick={e=>e.stopPropagation()} style={{ maxWidth:640,width:'100%',maxHeight:'85vh',padding:0,overflow:'hidden',borderRadius:16,display:'flex',flexDirection:'column' }}>
        {/* Header */}
        <div style={{ padding:'20px 24px',borderBottom:'1px solid var(--clr-border)',display:'flex',alignItems:'center',justifyContent:'space-between',flexShrink:0 }}>
          <div style={{ display:'flex',alignItems:'center',gap:14 }}>
            <div className="avatar" style={{ width:48,height:48,fontSize:'1rem' }}>{initials}</div>
            <div>
              <h2 style={{ margin:0,fontSize:'1.1rem',fontWeight:800,color:'var(--clr-text)' }}>{patient.name}</h2>
              <p style={{ margin:0,fontSize:'0.78rem',color:'var(--clr-subtext)' }}>{patient.displayId || '—'} • {patient.gender || 'Unknown'} • {patient.age ? `${patient.age}y` : 'Age N/A'}</p>
            </div>
          </div>
          <div style={{ display:'flex',alignItems:'center',gap:8 }}>
            <span className={`badge ${patient.status === 'Active' ? 'badge-success' : 'badge-warning'}`}>{patient.status || 'Active'}</span>
            <button onClick={onClose} style={{ background:'none',border:'none',cursor:'pointer',color:'var(--clr-subtext)' }}><X size={18}/></button>
          </div>
        </div>

        {/* Tabs */}
        <div style={{ display:'flex',borderBottom:'1px solid var(--clr-border)',padding:'0 24px',flexShrink:0 }}>
          {tabs.map(t => (
            <button key={t.id} onClick={()=>setTab(t.id)} style={{
              padding:'10px 16px',border:'none',borderBottom: tab===t.id ? '2px solid var(--clr-primary)' : '2px solid transparent',
              background:'transparent',color: tab===t.id ? 'var(--clr-primary)' : 'var(--clr-subtext)',
              fontSize:'0.78rem',fontWeight:700,cursor:'pointer',transition:'all 0.15s',
            }}>{t.label}</button>
          ))}
        </div>

        {/* Tab Content */}
        <div style={{ flex:1,overflow:'auto',padding:'20px 24px' }}>

          {/* Overview Tab */}
          {tab === 'overview' && (
            <div style={{ display:'flex',flexDirection:'column',gap:14 }}>
              <div style={{ display:'grid',gridTemplateColumns:'1fr 1fr',gap:10 }}>
                {[
                  { icon: Phone, label:'Phone', value: patient.phone || 'N/A' },
                  { icon: Droplets, label:'Blood Type', value: patient.bloodType || 'Unknown' },
                  { icon: Calendar, label:'Last Visit', value: patient.lastVisit || 'Never' },
                  { icon: User, label:'Gender', value: patient.gender || 'Unknown' },
                ].map(item => (
                  <div key={item.label} style={{ padding:12,background:'var(--clr-bg)',borderRadius:8,border:'1px solid var(--clr-border)' }}>
                    <div style={{ display:'flex',alignItems:'center',gap:6,fontSize:'0.68rem',color:'var(--clr-subtext)',fontWeight:700,textTransform:'uppercase',marginBottom:4 }}>
                      <item.icon size={12}/> {item.label}
                    </div>
                    <div style={{ fontSize:'0.88rem',fontWeight:700,color:'var(--clr-text)' }}>{item.value}</div>
                  </div>
                ))}
              </div>
              {/* Quick stats */}
              <div style={{ display:'grid',gridTemplateColumns:'1fr 1fr 1fr',gap:10 }}>
                <div style={{ padding:12,background:'var(--clr-bg)',borderRadius:8,textAlign:'center',border:'1px solid var(--clr-border)' }}>
                  <div style={{ fontSize:'1.3rem',fontWeight:900,color:'var(--clr-primary)' }}>{patientAppts.length}</div>
                  <div style={{ fontSize:'0.7rem',color:'var(--clr-subtext)',fontWeight:700 }}>Appointments</div>
                </div>
                <div style={{ padding:12,background:'var(--clr-bg)',borderRadius:8,textAlign:'center',border:'1px solid var(--clr-border)' }}>
                  <div style={{ fontSize:'1.3rem',fontWeight:900,color:'var(--clr-primary)' }}>{completedAppts.length}</div>
                  <div style={{ fontSize:'0.7rem',color:'var(--clr-subtext)',fontWeight:700 }}>Consultations</div>
                </div>
                <div style={{ padding:12,background:'var(--clr-bg)',borderRadius:8,textAlign:'center',border:'1px solid var(--clr-border)' }}>
                  <div style={{ fontSize:'1.3rem',fontWeight:900,color:'var(--clr-primary)' }}>{reportsList.length}</div>
                  <div style={{ fontSize:'0.7rem',color:'var(--clr-subtext)',fontWeight:700 }}>Reports</div>
                </div>
              </div>
              {/* Actions */}
              <div style={{ display:'flex',gap:10,marginTop:6 }}>
                {(user?.role === 'doctor' || user?.role === 'admin') && (
                  <button className="btn btn-primary btn-sm" onClick={()=>onViewConsultation(patient)} style={{ flex:1,display:'flex',alignItems:'center',justifyContent:'center',gap:6 }}>
                    <Stethoscope size={14}/> View Consultation
                  </button>
                )}
                <button className="btn btn-secondary btn-sm" onClick={()=>{onClose();onCreateAppointment&&onCreateAppointment(patient);}} style={{ flex:1,display:'flex',alignItems:'center',justifyContent:'center',gap:6 }}>
                  <Calendar size={14}/> Book Appointment
                </button>
              </div>
            </div>
          )}

          {/* Consultations Tab */}
          {tab === 'consultations' && (
            <div style={{ display:'flex',flexDirection:'column',gap:10 }}>
              {loadingConsultations ? (
                <div style={{ padding:'30px 20px',textAlign:'center',color:'var(--clr-subtext)',fontSize:'0.82rem',fontWeight:700 }}>Loading consultation history...</div>
              ) : consultationsError ? (
                <div style={{ padding:'30px 20px',textAlign:'center',color:'var(--clr-danger)',fontSize:'0.82rem',fontWeight:700 }}>{consultationsError}</div>
              ) : consultationHistory.length === 0 ? (
                <EmptyState icon={Stethoscope} text="No completed consultations yet"/>
              ) : consultationHistory.map(consultation => (
                <div key={consultation.consultationId} style={{ padding:14,background:'var(--clr-bg)',borderRadius:10,border:'1px solid var(--clr-border)',display:'flex',alignItems:'center',justifyContent:'space-between',gap:12 }}>
                  <div>
                    <div style={{ fontWeight:700,fontSize:'0.88rem',color:'var(--clr-text)' }}>Clinical Consultation</div>
                    <div style={{ display:'flex',alignItems:'center',gap:10,marginTop:4,fontSize:'0.76rem',color:'var(--clr-subtext)' }}>
                      <span style={{ display:'flex',alignItems:'center',gap:4 }}><Calendar size={11}/> {consultation.createdAt ? new Date(consultation.createdAt).toLocaleDateString() : 'Date unavailable'}</span>
                      <span>Version {consultation.version}</span>
                    </div>
                    {consultation.sessionNote && <div style={{ marginTop:6,fontSize:'0.74rem',color:'var(--clr-text)',maxWidth:360,overflow:'hidden',textOverflow:'ellipsis',whiteSpace:'nowrap' }}>{consultation.sessionNote}</div>}
                  </div>
                  <div style={{ display:'flex',alignItems:'center',gap:8 }}>
                    <button className="btn btn-sm" onClick={()=>onViewConsultation(patient, consultation)} style={{ padding:'5px 10px',fontSize:'0.72rem',display:'flex',alignItems:'center',gap:4,background:'transparent',border:'1px solid var(--clr-border)',color:'var(--clr-text)' }}>
                      <Eye size={12}/> View
                    </button>
                  </div>
                </div>
              ))}
            </div>
          )}

          {/* Reports Tab */}
          {tab === 'reports' && (
            <div style={{ display:'flex',flexDirection:'column',gap:12 }}>
              {loadingReports ? (
                <div style={{ padding:'30px 20px',textAlign:'center',color:'var(--clr-subtext)',fontSize:'0.82rem',fontWeight:700 }}>
                  Loading clinical reports...
                </div>
              ) : reportsError ? (
                <div style={{ padding:'30px 20px',textAlign:'center',color:'var(--clr-danger)',fontSize:'0.82rem',fontWeight:700 }}>
                  <div>{reportsError}</div>
                  <button className="btn btn-secondary btn-sm" onClick={() => setReportsReload(value => value + 1)} style={{ marginTop: 10 }}>Retry</button>
                </div>
              ) : reportsList.length === 0 ? (
                <EmptyState icon={FileText} text="No clinical reports found for this patient"/>
              ) : reportsList.map(r => (
                <div key={r.id} style={{ 
                  padding: 16, 
                  background: 'var(--clr-bg)', 
                  borderRadius: 12, 
                  border: '1px solid var(--clr-border)',
                  display: 'flex', 
                  flexDirection: 'column', 
                  gap: 10,
                  transition: 'box-shadow 0.15s ease'
                }}>
                  {/* Title & Badge */}
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                      <FileText size={16} color="var(--clr-primary)" />
                      <span style={{ fontWeight: 800, fontSize: '0.88rem', color: 'var(--clr-text)' }}>
                        Clinical Consultation Report
                      </span>
                    </div>
                    <span style={{ 
                      fontSize: '0.68rem', 
                      fontWeight: 700, 
                      padding: '3px 8px', 
                      borderRadius: 6, 
                      background: '#E0F2FE', 
                      color: '#0369A1', 
                      display: 'flex', 
                      alignItems: 'center', 
                      gap: 4 
                    }}>
                      PDF Document
                    </span>
                  </div>

                  {r.reportSnapshot ? (
                    <FinalReportSnapshot snapshot={r.reportSnapshot} />
                  ) : <>
                  {/* Legacy details block */}
                  <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '8px 16px', fontSize: '0.78rem', color: 'var(--slate-600)' }}>
                    <div>
                      <strong>Doctor:</strong> <span style={{ color: 'var(--clr-text)' }}>Dr. {r.doctor || 'Unknown'}</span>
                    </div>
                    <div>
                      <strong>Tooth ID:</strong> <span style={{ color: 'var(--clr-text)' }}>{r.tooth_id ? `Tooth #${r.tooth_id}` : 'General'}</span>
                    </div>
                    <div>
                      <strong>Condition:</strong> <span style={{ color: 'var(--clr-text)' }}>{r.tooth_status || 'N/A'}</span>
                    </div>
                    <div>
                      <strong>Date:</strong> <span style={{ color: 'var(--clr-text)' }}>{r.created_at ? new Date(r.created_at).toLocaleDateString() : 'N/A'}</span>
                    </div>
                  </div>

                  {/* Summary / Findings */}
                  {r.final_medical_report && (
                    <div style={{ 
                      padding: '8px 12px', 
                      background: 'var(--clr-bg)', 
                      borderRadius: 8, 
                      borderLeft: '3px solid var(--clr-primary)', 
                      fontSize: '0.76rem', 
                      color: 'var(--clr-text)',
                      lineHeight: 1.4,
                      border: '1px solid var(--clr-border)',
                      borderLeftColor: 'var(--clr-primary)'
                    }}>
                      <strong>Findings Excerpt:</strong> {r.final_medical_report.length > 150 ? r.final_medical_report.substring(0, 150) + "..." : r.final_medical_report}
                    </div>
                  )}
                  </>}

                  {/* Divider */}
                  <div style={{ borderBottom: '1px solid var(--clr-border)', margin: '4px 0' }}></div>

                  {/* Actions */}
                  {!r.reportSnapshot && <div style={{ display: 'flex', gap: 8, justifyContent: 'flex-end' }}>
                    <button 
                      onClick={() => handleReportPdf(r, 'view')}
                      className="btn btn-secondary btn-sm"
                      style={{ 
                        padding: '6px 12px', 
                        fontSize: '0.74rem', 
                        display: 'flex', 
                        alignItems: 'center', 
                        gap: 6 
                      }}
                    >
                      <Eye size={12}/> View Report
                    </button>
                    <button
                      type="button"
                      onClick={() => handleReportPdf(r, 'download')}
                      className="btn btn-primary btn-sm"
                      style={{ 
                        padding: '6px 12px', 
                        fontSize: '0.74rem', 
                        display: 'flex', 
                        alignItems: 'center', 
                        gap: 6,
                        textDecoration: 'none',
                        color: '#fff'
                      }}
                    >
                      <Save size={12}/> Download Report
                    </button>
                  </div>}
                </div>
              ))}
            </div>
          )}

          {/* Appointments Tab */}
          {tab === 'appointments' && (
            <div style={{ display:'flex',flexDirection:'column',gap:10 }}>
              {patientAppts.length === 0 ? (
                <EmptyState icon={Calendar} text="No appointments found"/>
              ) : patientAppts.map(a => (
                <div key={a.id} style={{ padding:14,background:'var(--clr-bg)',borderRadius:10,border:'1px solid var(--clr-border)',display:'flex',alignItems:'center',justifyContent:'space-between' }}>
                  <div>
                    <div style={{ fontWeight:700,fontSize:'0.88rem',color:'var(--clr-text)' }}>{a.type || 'Appointment'}</div>
                    <div style={{ display:'flex',alignItems:'center',gap:10,marginTop:4,fontSize:'0.76rem',color:'var(--clr-subtext)' }}>
                      <span style={{ display:'flex',alignItems:'center',gap:4 }}><Calendar size={11}/> {a.date}</span>
                      <span style={{ display:'flex',alignItems:'center',gap:4 }}><Clock size={11}/> {a.time}</span>
                    </div>
                  </div>
                  <span className={`badge ${a.status==='Completed'?'badge-success':a.status==='Cancelled'?'badge-danger':'badge-warning'}`} style={{ fontSize:'0.68rem' }}>{a.status}</span>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
      {selectedConsultation && (
        <div onClick={()=>setSelectedConsultation(null)} style={{ position:'fixed',inset:0,zIndex:100000,display:'flex',alignItems:'center',justifyContent:'center',padding:20,background:'rgba(15,23,42,0.62)',backdropFilter:'blur(4px)' }}>
          <div className="card animate-fadeIn" onClick={event=>event.stopPropagation()} style={{ width:'100%',maxWidth:720,maxHeight:'85vh',overflow:'auto',padding:0,borderRadius:16 }}>
            <div style={{ padding:'18px 22px',borderBottom:'1px solid var(--clr-border)',display:'flex',justifyContent:'space-between',alignItems:'center',position:'sticky',top:0,background:'var(--clr-card)',zIndex:1 }}>
              <div>
                <h2 style={{ margin:0,fontSize:'1.05rem',fontWeight:800 }}>Historical Consultation</h2>
                <p style={{ margin:'3px 0 0',fontSize:'0.74rem',color:'var(--clr-subtext)' }}>{selectedConsultation.createdAt ? new Date(selectedConsultation.createdAt).toLocaleString() : 'Date unavailable'}</p>
              </div>
              <button onClick={()=>setSelectedConsultation(null)} style={{ border:'none',background:'transparent',cursor:'pointer',color:'var(--clr-subtext)' }}><X size={18}/></button>
            </div>
            <div style={{ padding:22,display:'flex',flexDirection:'column',gap:18 }}>
              {Array.isArray(selectedConsultation.clinicalFindings) && (
                <section>
                  <h3 style={{ margin:'0 0 8px',fontSize:'0.82rem',fontWeight:800 }}>Clinical Findings</h3>
                  {selectedConsultation.clinicalFindings.length === 0 ? (
                    <div style={{ color:'var(--clr-subtext)',fontSize:'.82rem' }}>No tooth findings were recorded.</div>
                  ) : selectedConsultation.clinicalFindings.map(finding => (
                    <div key={finding.toothId} style={{ padding:12,marginBottom:8,borderRadius:10,background:'var(--clr-bg)',border:'1px solid var(--clr-border)',fontSize:'.8rem' }}>
                      <strong>Tooth {finding.toothId}</strong>
                      <div>Status: {finding.toothStatus}</div>
                      <div>Symptoms: {finding.symptoms?.length ? finding.symptoms.join(', ') : 'None'}</div>
                      <div>Tooth Note: {finding.toothNote || 'None'}</div>
                    </div>
                  ))}
                </section>
              )}
              {selectedConsultation.clinicalFindings == null && selectedConsultation.symptoms?.length > 0 && (
                <section>
                  <h3 style={{ margin:'0 0 8px',fontSize:'0.82rem',fontWeight:800 }}>Legacy Consultation Symptoms</h3>
                  <div style={{ color:'var(--clr-subtext)',fontSize:'.82rem' }}>{selectedConsultation.symptoms.join(', ')}</div>
                </section>
              )}
              <section>
                <h3 style={{ margin:'0 0 8px',fontSize:'0.82rem',fontWeight:800 }}>Consultation Note</h3>
                <div style={{ padding:14,borderRadius:10,background:'var(--clr-primary-light)',borderLeft:'4px solid var(--clr-primary)',whiteSpace:'pre-wrap',fontSize:'0.82rem',lineHeight:1.6 }}>
                  {selectedConsultation.sessionNote || 'No consultation note was recorded.'}
                </div>
              </section>
              <section>
                <h3 style={{ margin:'0 0 8px',fontSize:'0.82rem',fontWeight:800 }}>Complete Dental State</h3>
                <pre style={{ margin:0,padding:14,borderRadius:10,background:'var(--clr-bg)',border:'1px solid var(--clr-border)',fontSize:'0.72rem',lineHeight:1.5,overflow:'auto',whiteSpace:'pre-wrap',color:'var(--clr-text)' }}>
                  {JSON.stringify(selectedConsultation.toothData || {}, null, 2)}
                </pre>
              </section>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function EmptyState({ icon: Icon, text }) {
  return (
    <div style={{ padding:'40px 20px',textAlign:'center' }}>
      <Icon size={28} style={{ color:'var(--clr-text-light)',marginBottom:8 }}/>
      <div style={{ fontSize:'0.86rem',color:'var(--clr-subtext)',fontWeight:600 }}>{text}</div>
    </div>
  );
}

/* ── New Patient Modal ─────────────────────────────────────── */
export function NewPatientModal({ onClose, onSave }) {
  const [form, setForm] = useState({ name:'', phone:'', age:'', gender:'Male', status:'Active', notes:'', bloodType:'Unknown' });
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const set = (k,v) => setForm(p=>({...p,[k]:v}));

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (!form.name.trim()) { setError('Patient name is required.'); return; }
    setSaving(true); setError('');
    try {
      const result = await onSave({
        name: form.name.trim(),
        phone: form.phone.trim() || null,
        age: form.age ? parseInt(form.age) : null,
        gender: form.gender,
        status: form.status,
        blood_type: form.bloodType || 'Unknown',
        bloodType: form.bloodType || 'Unknown'
      });
      if (result) onClose(result);
      else setError('Failed to save patient.');
    } catch { setError('An error occurred.'); }
    finally { setSaving(false); }
  };

  return (
    <div className="modal-overlay" onClick={()=>onClose(null)} style={{ position:'fixed',inset:0,zIndex:99999,display:'flex',alignItems:'center',justifyContent:'center',padding:20,backgroundColor:'rgba(0,0,0,0.45)',backdropFilter:'blur(3px)' }}>
      <form className="card animate-fadeIn" onClick={e=>e.stopPropagation()} onSubmit={handleSubmit} style={{ maxWidth:480,width:'100%',padding:0,overflow:'hidden',borderRadius:16 }}>
        <div style={{ padding:'20px 24px',borderBottom:'1px solid var(--clr-border)',display:'flex',alignItems:'center',justifyContent:'space-between' }}>
          <div style={{ display:'flex',alignItems:'center',gap:10 }}>
            <div style={{ width:36,height:36,borderRadius:8,background:'var(--clr-primary-light)',display:'grid',placeItems:'center' }}>
              <User size={16} color="var(--clr-primary-dark)"/>
            </div>
            <h2 style={{ margin:0,fontSize:'1.05rem',fontWeight:800 }}>New Patient</h2>
          </div>
          <button type="button" onClick={()=>onClose(null)} style={{ background:'none',border:'none',cursor:'pointer',color:'var(--clr-subtext)' }}><X size={18}/></button>
        </div>
        <div style={{ padding:'20px 24px',display:'flex',flexDirection:'column',gap:14 }}>
          {error && (
            <div style={{ padding:'8px 12px',borderRadius:8,fontSize:'0.8rem',fontWeight:600,background:'rgba(239,68,68,0.08)',color:'#dc2626',border:'1px solid rgba(239,68,68,0.15)',display:'flex',alignItems:'center',gap:6 }}>
              <AlertCircle size={14}/> {error}
            </div>
          )}
          <div className="form-group"><label className="form-label">Full Name *</label>
            <input className="form-input" required placeholder="e.g. Ahmed Al-Rashid" value={form.name} onChange={e=>set('name',e.target.value)}/>
          </div>
          <div style={{ display:'grid',gridTemplateColumns:'1fr 1fr',gap:12 }}>
            <div className="form-group"><label className="form-label">Phone</label>
              <input className="form-input" placeholder="+966..." value={form.phone} onChange={e=>set('phone',e.target.value)}/>
            </div>
            <div className="form-group"><label className="form-label">Age</label>
              <input className="form-input" type="number" min="0" max="150" placeholder="30" value={form.age} onChange={e=>set('age',e.target.value)}/>
            </div>
          </div>
          <div style={{ display:'grid',gridTemplateColumns:'1fr 1fr',gap:12 }}>
            <div className="form-group"><label className="form-label">Gender</label>
              <select className="form-select" value={form.gender} onChange={e=>set('gender',e.target.value)} style={{ width:'100%' }}>
                <option>Male</option><option>Female</option><option>Other</option><option>Unknown</option>
              </select>
            </div>
            <div className="form-group"><label className="form-label">Blood Type</label>
              <select className="form-select" value={form.bloodType} onChange={e=>set('bloodType',e.target.value)} style={{ width:'100%' }}>
                {['Unknown', 'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'].map(bt => (
                  <option key={bt} value={bt}>{bt}</option>
                ))}
              </select>
            </div>
          </div>
          <div className="form-group"><label className="form-label">Status</label>
            <select className="form-select" value={form.status} onChange={e=>set('status',e.target.value)} style={{ width:'100%' }}>
              <option>Active</option><option>Inactive</option><option>Critical</option>
            </select>
          </div>
        </div>
        <div style={{ padding:'14px 24px',borderTop:'1px solid var(--clr-border)',display:'flex',gap:10,justifyContent:'flex-end' }}>
          <button type="button" className="btn btn-secondary" onClick={()=>onClose(null)}>Cancel</button>
          <button type="submit" className="btn btn-primary" disabled={saving} style={{ display:'flex',alignItems:'center',gap:6 }}>
            <Save size={14}/> {saving ? 'Saving…' : 'Add Patient'}
          </button>
        </div>
      </form>
    </div>
  );
}

/* ── Filter Panel ──────────────────────────────────────────── */
export function FilterPanel({ filters, onChange, onReset }) {
  const set = (k,v) => onChange({ ...filters, [k]: v });

  return (
    <div className="card animate-fadeIn" style={{ padding:16,display:'flex',flexDirection:'column',gap:12 }}>
      <div style={{ display:'flex',alignItems:'center',justifyContent:'space-between' }}>
        <span style={{ fontSize:'0.78rem',fontWeight:800,color:'var(--clr-text)',textTransform:'uppercase' }}>Filters</span>
        <button onClick={onReset} style={{ background:'none',border:'none',cursor:'pointer',color:'var(--clr-primary)',fontSize:'0.72rem',fontWeight:700 }}>Reset</button>
      </div>
      <div className="form-group"><label className="form-label" style={{ fontSize:'0.72rem' }}>Status</label>
        <select className="form-select" value={filters.status} onChange={e=>set('status',e.target.value)} style={{ width:'100%',fontSize:'0.82rem' }}>
          <option value="">All</option><option>Active</option><option>Inactive</option><option>Critical</option>
        </select>
      </div>
      <div className="form-group"><label className="form-label" style={{ fontSize:'0.72rem' }}>Gender</label>
        <select className="form-select" value={filters.gender} onChange={e=>set('gender',e.target.value)} style={{ width:'100%',fontSize:'0.82rem' }}>
          <option value="">All</option><option>Male</option><option>Female</option>
        </select>
      </div>
      <div className="form-group"><label className="form-label" style={{ fontSize:'0.72rem' }}>Has Records</label>
        <select className="form-select" value={filters.hasRecords} onChange={e=>set('hasRecords',e.target.value)} style={{ width:'100%',fontSize:'0.82rem' }}>
          <option value="">All</option><option value="yes">With Reports</option><option value="no">No Reports</option>
        </select>
      </div>
    </div>
  );
}

/* ── Edit Patient Modal ─────────────────────────────────────── */
export function EditPatientModal({ patient, onClose, onSave, role }) {
  const [form, setForm] = useState({
    name: patient.name || '',
    phone: patient.phone || '',
    age: patient.age || '',
    gender: patient.gender || 'Male',
    status: patient.status || 'Active',
    bloodType: patient.bloodType || patient.blood_type || 'Unknown'
  });
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const set = (k, v) => setForm(p => ({ ...p, [k]: v }));

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (!form.name.trim()) { setError('Patient name is required.'); return; }
    setSaving(true); setError('');
    try {
      const updates = {
        name: form.name.trim(),
        phone: form.phone.trim() || null,
        age: form.age ? parseInt(form.age) : null,
        gender: form.gender,
        status: form.status,
        blood_type: form.bloodType || 'Unknown',
        bloodType: form.bloodType || 'Unknown'
      };

      const result = await onSave(patient.id, updates);
      if (result) onClose(result);
      else setError('Failed to update patient.');
    } catch (err) {
      setError('An error occurred.');
    } finally {
      setSaving(false);
    }
  };

  const isReceptionist = role === 'receptionist';

  return (
    <div className="modal-overlay" onClick={() => onClose(null)} style={{ position: 'fixed', inset: 0, zIndex: 99999, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 20, backgroundColor: 'rgba(0,0,0,0.45)', backdropFilter: 'blur(3px)' }}>
      <form className="card animate-fadeIn" onClick={e => e.stopPropagation()} onSubmit={handleSubmit} style={{ maxWidth: 480, width: '100%', padding: 0, overflow: 'hidden', borderRadius: 16 }}>
        <div style={{ padding: '20px 24px', borderBottom: '1px solid var(--clr-border)', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <div style={{ width: 36, height: 36, borderRadius: 8, background: 'var(--clr-primary-light)', display: 'grid', placeItems: 'center' }}>
              <User size={16} color="var(--clr-primary-dark)" />
            </div>
            <h2 style={{ margin: 0, fontSize: '1.05rem', fontWeight: 800 }}>Edit Patient</h2>
          </div>
          <button type="button" onClick={() => onClose(null)} style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--clr-subtext)' }}><X size={18} /></button>
        </div>
        <div style={{ padding: '20px 24px', display: 'flex', flexDirection: 'column', gap: 14 }}>
          {error && (
            <div style={{ padding: '8px 12px', borderRadius: 8, fontSize: '0.8rem', fontWeight: 600, background: 'rgba(239,68,68,0.08)', color: '#dc2626', border: '1px solid rgba(239,68,68,0.15)', display: 'flex', alignItems: 'center', gap: 6 }}>
              <AlertCircle size={14} /> {error}
            </div>
          )}
          <div className="form-group"><label className="form-label">Full Name *</label>
            <input className="form-input" required placeholder="e.g. Ahmed Al-Rashid" value={form.name} onChange={e => set('name', e.target.value)} />
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
            <div className="form-group"><label className="form-label">Phone</label>
              <input className="form-input" placeholder="+966..." value={form.phone} onChange={e => set('phone', e.target.value)} />
            </div>
            <div className="form-group"><label className="form-label">Age</label>
              <input className="form-input" type="number" min="0" max="150" placeholder="30" value={form.age} onChange={e => set('age', e.target.value)} />
            </div>
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
            <div className="form-group"><label className="form-label">Gender</label>
              <select className="form-select" value={form.gender} onChange={e => set('gender', e.target.value)} style={{ width: '100%' }}>
                <option>Male</option><option>Female</option><option>Other</option><option>Unknown</option>
              </select>
            </div>
            <div className="form-group"><label className="form-label">Blood Type</label>
              <select className="form-select" value={form.bloodType} onChange={e => set('bloodType', e.target.value)} style={{ width: '100%' }}>
                {['Unknown', 'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'].map(bt => (
                  <option key={bt} value={bt}>{bt}</option>
                ))}
              </select>
            </div>
          </div>
          <div className="form-group"><label className="form-label">Status</label>
            <select className="form-select" value={form.status} onChange={e => set('status', e.target.value)} style={{ width: '100%' }}>
              <option>Active</option><option>Inactive</option><option>Critical</option>
            </select>
          </div>
        </div>
        <div style={{ padding: '14px 24px', borderTop: '1px solid var(--clr-border)', display: 'flex', gap: 10, justifyContent: 'flex-end' }}>
          <button type="button" className="btn btn-secondary" onClick={() => onClose(null)}>Cancel</button>
          <button type="submit" className="btn btn-primary" disabled={saving} style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <Save size={14} /> {saving ? 'Saving…' : 'Save Changes'}
          </button>
        </div>
      </form>
    </div>
  );
}
