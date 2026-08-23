import React, { useState, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import { AlertCircle, Calendar, ChevronRight, Clock, Filter, Phone, Plus, Search, Stethoscope, User, X, Eye, Trash2, Droplets, Edit3, CreditCard, History } from 'lucide-react';
import Layout from '../../components/Layout';
import { useData } from '../../context/DataContext';
import { useAuth } from '../../context/AuthContext';
import { PatientViewModal, NewPatientModal, FilterPanel, EditPatientModal } from '../../components/PatientModals';
import { FinancialHistoryModal, OutstandingBalanceModal } from '../../components/FinanceModals';
import { getPatientFinancialHistory, getPatientFinancialSummaries } from '../../services/financeApi';
import { decimalToCents, formatMoney } from '../../config/money';
import { canUseFinance } from '../../services/financeView';

const DEFAULT_FILTERS = { status: '', gender: '', hasRecords: '' };

export default function PatientsPage() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const { patients, patientsLoading, patientsError, appointments, records, addPatient, deletePatient, updatePatient, refreshData } = useData();
  const [patientToRemove, setPatientToRemove] = useState(null);
  const [patientToEdit, setPatientToEdit] = useState(null);
  const [isDeleting, setIsDeleting] = useState(false);
  const [toast, setToast] = useState(null);
  const [financialSummaries, setFinancialSummaries] = useState({});
  const [financialHistory, setFinancialHistory] = useState(null);
  const [outstanding, setOutstanding] = useState(null);
  const canReadFinance = canUseFinance(user, 'finance.patient_history.read');

  React.useEffect(() => {
    let active = true;
    setFinancialSummaries({});
    if (canReadFinance) {
      getPatientFinancialSummaries()
        .then(result => { if (active) setFinancialSummaries(result); })
        .catch(error => { if (active) showToast(error.message, 'danger'); });
    }
    return () => { active = false; };
  }, [canReadFinance, user?.id]);
  const openFinancialHistory = async patient => {
    setFinancialHistory({ loading: true, patient });
    try { setFinancialHistory(await getPatientFinancialHistory(patient.id)); }
    catch (error) { showToast(error.message, 'danger'); setFinancialHistory(null); }
  };

  const showToast = (message, type = 'success') => {
    setToast({ message, type });
    setTimeout(() => setToast(null), 5000);
  };

  const handleRemovePatient = async () => {
    if (!patientToRemove) return;
    setIsDeleting(true);
    try {
      const res = await deletePatient(patientToRemove.id);
      if (res && res.success) {
        showToast(res.message || 'Patient removed successfully', 'success');
      } else {
        showToast(res ? res.error : 'Failed to remove patient', 'danger');
      }
    } catch {
      showToast('An unexpected error occurred', 'danger');
    } finally {
      setIsDeleting(false);
      setPatientToRemove(null);
    }
  };
  const [search, setSearch] = useState('');
  const [filters, setFilters] = useState(DEFAULT_FILTERS);
  const [showFilters, setShowFilters] = useState(false);
  const [showNewPatient, setShowNewPatient] = useState(false);
  const [viewPatient, setViewPatient] = useState(null);
  const [justAdded, setJustAdded] = useState(null);

  // Filtering logic
  const filtered = useMemo(() => {
    return patients.filter(p => {
      const q = search.toLowerCase();
      const matchSearch = !q || [p.name, p.phone, p.displayId, p.condition, p.gender, p.bloodType, p.lastVisit]
        .filter(Boolean).some(f => f.toLowerCase().includes(q));
      const matchStatus = !filters.status || p.status === filters.status;
      const matchGender = !filters.gender || p.gender === filters.gender;
      const matchRecords = !filters.hasRecords ||
        (filters.hasRecords === 'yes' && records.some(r => r.patient_id === p.id)) ||
        (filters.hasRecords === 'no' && !records.some(r => r.patient_id === p.id));
      return matchSearch && matchStatus && matchGender && matchRecords;
    });
  }, [patients, search, filters, records]);

  const activeFilterCount = Object.values(filters).filter(Boolean).length;

  const getPatientStats = (pid) => {
    const pAppts = appointments.filter(a => a.patient_id === pid || a.patient === patients.find(p=>p.id===pid)?.name);
    const pRecords = records.filter(r => r.patient_id === pid);
    return { appts: pAppts.length, records: pRecords.length };
  };

  const handleNewPatientClose = (newPatient) => {
    setShowNewPatient(false);
    if (newPatient) {
      setJustAdded(newPatient);
      setTimeout(() => setJustAdded(null), 5000);
    }
  };

  return (
    <Layout pageTitle="Patients" pageSubtitle="Clinical directory and consultation queue.">
      <div className="page-stack animate-fadeIn">

        {/* Top Controls */}
        <section className="section-header" style={{ display:'flex',alignItems:'center',justifyContent:'space-between',flexWrap:'wrap',gap:12 }}>
          <div style={{ position:'relative',flex:'1 1 260px',maxWidth:360 }}>
            <Search size={16} style={{ position:'absolute',left:14,top:'50%',transform:'translateY(-50%)',color:'var(--clr-text-light)' }}/>
            <input className="form-input" style={{ paddingLeft:38,width:'100%',margin:0 }}
              placeholder="Search name, phone, ID, condition..." value={search} onChange={e=>setSearch(e.target.value)}/>
            {search && <button onClick={()=>setSearch('')} style={{ position:'absolute',right:10,top:'50%',transform:'translateY(-50%)',background:'none',border:'none',cursor:'pointer',color:'var(--clr-text-light)' }}><X size={14}/></button>}
          </div>
          <div className="row-actions" style={{ gap:8 }}>
            <button className={`btn btn-sm ${showFilters || activeFilterCount ? 'btn-primary' : 'btn-secondary'}`}
              onClick={()=>setShowFilters(!showFilters)}
              style={{ display:'flex',alignItems:'center',gap:6 }}>
              <Filter size={14}/> Filters {activeFilterCount > 0 && `(${activeFilterCount})`}
            </button>
            <button className="btn btn-primary btn-sm" onClick={()=>setShowNewPatient(true)}
              style={{ display:'flex',alignItems:'center',gap:6 }}>
              <Plus size={14}/> New Patient
            </button>
          </div>
        </section>

        {/* Just-added toast */}
        {justAdded && (
          <div style={{ padding:'12px 18px',borderRadius:10,background:'var(--clr-primary-light)',border:'1px solid rgba(16,185,129,0.2)',display:'flex',alignItems:'center',justifyContent:'space-between' }}>
            <span style={{ fontSize:'0.84rem',fontWeight:700,color:'var(--clr-primary-dark)' }}>
              ✓ {justAdded.name} added successfully
            </span>
            <button className="btn btn-primary btn-sm" onClick={()=>{setJustAdded(null);navigate('/doctor/appointments');}}
              style={{ fontSize:'0.75rem',padding:'5px 12px' }}>
              <Calendar size={12}/> Book Appointment
            </button>
          </div>
        )}

        {/* Main Layout */}
        <div style={{ display:'grid',gridTemplateColumns: showFilters ? '220px 1fr' : '1fr',gap:16,alignItems:'start' }}>

          {/* Filter Sidebar */}
          {showFilters && <FilterPanel filters={filters} onChange={setFilters} onReset={()=>setFilters(DEFAULT_FILTERS)}/>}

          {/* Patient Grid */}
          <div>
            {/* Count */}
            <div style={{ fontSize:'0.78rem',color:'var(--clr-subtext)',fontWeight:700,marginBottom:12 }}>
              {filtered.length} patient{filtered.length !== 1 ? 's' : ''} found
              {(search || activeFilterCount > 0) && (
                <button onClick={()=>{setSearch('');setFilters(DEFAULT_FILTERS);}} style={{ marginLeft:8,background:'none',border:'none',color:'var(--clr-primary)',cursor:'pointer',fontSize:'0.72rem',fontWeight:700 }}>
                  Clear all
                </button>
              )}
            </div>

            {patientsLoading ? (
              <div className="card" role="status" style={{ padding:'48px 24px',textAlign:'center',color:'var(--clr-subtext)' }}>
                Loading patients…
              </div>
            ) : patientsError ? (
              <div className="card" role="alert" style={{ padding:'32px 24px',textAlign:'center' }}>
                <AlertCircle size={30} style={{ color:'var(--clr-danger)',marginBottom:10 }}/>
                <div style={{ fontSize:'0.95rem',fontWeight:800,color:'var(--clr-danger)',marginBottom:6 }}>Could not load patients</div>
                <div style={{ fontSize:'0.82rem',color:'var(--clr-subtext)',marginBottom:14 }}>{patientsError}</div>
                <button className="btn btn-secondary btn-sm" onClick={refreshData}>Retry</button>
              </div>
            ) : filtered.length === 0 ? (
              <div className="card" style={{ padding:'48px 24px',textAlign:'center' }}>
                <User size={32} style={{ color:'var(--clr-text-light)',marginBottom:10 }}/>
                <div style={{ fontSize:'0.95rem',fontWeight:800,color:'var(--clr-text)',marginBottom:4 }}>
                  {search || activeFilterCount ? 'No patients match your search' : 'No patients yet'}
                </div>
                <div style={{ fontSize:'0.82rem',color:'var(--clr-subtext)' }}>
                  {search || activeFilterCount ? 'Try adjusting your search or filters.' : 'Add your first patient to get started.'}
                </div>
              </div>
            ) : (
              <section className="responsive-card-grid">
                {filtered.map((patient) => {
                  const stats = getPatientStats(patient.id);
                  const initials = patient.name ? patient.name.split(' ').map(n=>n[0]).join('').toUpperCase().slice(0,2) : 'P';
                  const finance = financialSummaries[String(patient.id)];
                  return (
                    <article key={patient.id} className="card page-stack" style={{ gap:12,transition:'box-shadow 0.2s' }}>
                      {/* Header */}
                      <div style={{ display:'flex',alignItems:'center',justifyContent:'space-between' }}>
                        <div style={{ display:'flex',alignItems:'center',gap:10 }}>
                          <div className="avatar" style={{ width:38,height:38,fontSize:'0.78rem' }}>{initials}</div>
                          <div>
                            <h3 style={{ margin:0,fontSize:'0.92rem',fontWeight:800,color:'var(--clr-text)' }}>{patient.name}</h3>
                            <p style={{ margin:0,fontSize:'0.72rem',color:'var(--clr-subtext)' }}>{patient.displayId || '—'} • {patient.gender || 'Unknown'}</p>
                          </div>
                        </div>
                        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                          {(user?.role === 'doctor' || user?.role === 'admin' || user?.role === 'receptionist') && (
                            <button 
                              onClick={() => setPatientToEdit(patient)}
                              title="Edit Patient"
                              style={{
                                width: 26,
                                height: 26,
                                borderRadius: 6,
                                border: '1px solid rgba(16, 185, 129, 0.2)',
                                background: '#ECFDF5',
                                color: 'var(--clr-primary)',
                                display: 'flex',
                                alignItems: 'center',
                                justifyContent: 'center',
                                cursor: 'pointer',
                                transition: 'all 0.15s ease'
                              }}
                              onMouseOver={(e) => {
                                e.currentTarget.style.background = 'var(--clr-primary)';
                                e.currentTarget.style.color = '#FFFFFF';
                              }}
                              onMouseOut={(e) => {
                                e.currentTarget.style.background = '#ECFDF5';
                                e.currentTarget.style.color = 'var(--clr-primary)';
                              }}
                            >
                              <Edit3 size={13} />
                            </button>
                          )}
                          {(user?.role === 'doctor' || user?.role === 'admin') && (
                            <button 
                              onClick={() => setPatientToRemove(patient)}
                              title="Remove Patient"
                              style={{
                                width: 26,
                                height: 26,
                                borderRadius: 6,
                                border: '1px solid rgba(239, 68, 68, 0.2)',
                                background: '#FEF2F2',
                                color: 'var(--clr-danger)',
                                display: 'flex',
                                alignItems: 'center',
                                justifyContent: 'center',
                                cursor: 'pointer',
                                transition: 'all 0.15s ease'
                              }}
                              onMouseOver={(e) => {
                                e.currentTarget.style.background = 'var(--clr-danger)';
                                e.currentTarget.style.color = '#FFFFFF';
                              }}
                              onMouseOut={(e) => {
                                e.currentTarget.style.background = '#FEF2F2';
                                e.currentTarget.style.color = 'var(--clr-danger)';
                              }}
                            >
                              <Trash2 size={13} />
                            </button>
                          )}
                          <span className={`badge ${patient.status==='Active'?'badge-success':patient.status==='Critical'?'badge-danger':'badge-warning'}`} style={{ fontSize:'0.65rem' }}>
                            {patient.status || 'Active'}
                          </span>
                        </div>
                      </div>

                      {/* Info */}
                      <div style={{ display:'flex',flexDirection:'column',gap:6 }}>
                        <div style={{ display:'flex',alignItems:'center',gap:8,fontSize:'0.78rem',color:'var(--clr-subtext)' }}>
                          <Clock size={13}/> Age: <strong style={{ color:'var(--clr-text)' }}>{patient.age ? `${patient.age}y` : 'N/A'}</strong>
                        </div>
                        {patient.phone && (
                          <div style={{ display:'flex',alignItems:'center',gap:8,fontSize:'0.78rem',color:'var(--clr-subtext)' }}>
                            <Phone size={13}/> <strong style={{ color:'var(--clr-text)' }}>{patient.phone}</strong>
                          </div>
                        )}
                        <div style={{ display:'flex',alignItems:'center',gap:8,fontSize:'0.78rem',color:'var(--clr-subtext)' }}>
                          <Calendar size={13}/> Last: <strong style={{ color:'var(--clr-text)' }}>{patient.lastVisit || 'Never'}</strong>
                        </div>
                        <div style={{ display:'flex',alignItems:'center',gap:8,fontSize:'0.78rem',color:'var(--clr-subtext)' }}>
                          <Droplets size={13}/> Blood Type: <strong style={{ color: (patient.bloodType || patient.blood_type) && (patient.bloodType || patient.blood_type) !== 'Unknown' ? 'var(--clr-danger)' : 'var(--clr-text)' }}>{patient.bloodType || patient.blood_type || 'Unknown'}</strong>
                        </div>
                      </div>

                      {/* Stats row */}
                      <div style={{ display:'flex',gap:8 }}>
                        <span style={{ flex:1,textAlign:'center',padding:'6px 0',background:'var(--clr-bg)',borderRadius:6,fontSize:'0.68rem',fontWeight:700,color:'var(--clr-subtext)',border:'1px solid var(--clr-border)' }}>
                          {stats.appts} appt{stats.appts!==1?'s':''}
                        </span>
                        <span style={{ flex:1,textAlign:'center',padding:'6px 0',background:'var(--clr-bg)',borderRadius:6,fontSize:'0.68rem',fontWeight:700,color:'var(--clr-subtext)',border:'1px solid var(--clr-border)' }}>
                          {stats.records} report{stats.records!==1?'s':''}
                        </span>
                      </div>

                      {/* Actions */}
                      {canReadFinance && <div style={{ display:'flex',gap:8,flexWrap:'wrap' }}>
                        <button className="btn btn-secondary btn-sm" onClick={()=>openFinancialHistory(patient)} style={{ flex:1,fontSize:'.74rem' }}><History size={13}/> Financial History</button>
                        {Number(finance?.totalOutstanding || 0)>0&&<button className="btn btn-sm" onClick={()=>setOutstanding(finance)} style={{ flex:1,fontSize:'.72rem',fontWeight:800,color:'var(--clr-danger)',background:'#FEF2F2',border:'1px solid rgba(239,68,68,.25)' }}><CreditCard size={13}/> Outstanding {formatMoney(decimalToCents(finance.totalOutstanding)||0)}</button>}
                      </div>}
                      <div style={{ display:'flex',gap:8 }}>
                        <button onClick={()=>setViewPatient(patient)}
                          className="btn btn-secondary btn-sm" style={{ flex:1,display:'flex',alignItems:'center',justifyContent:'center',gap:5,fontSize:'0.78rem' }}>
                          <Eye size={13}/> View Patient
                        </button>
                        {(user?.role === 'doctor' || user?.role === 'admin') && (
                          <button onClick={()=>navigate(`/doctor/consultations-history?patientId=${patient.id}`)}
                            className="btn btn-primary btn-sm" style={{ flex:1,display:'flex',alignItems:'center',justifyContent:'center',gap:5,fontSize:'0.78rem' }}>
                            <Stethoscope size={13}/> View Consultation
                          </button>
                        )}
                      </div>
                    </article>
                  );
                })}
              </section>
            )}
          </div>
        </div>
      </div>

      {/* Modals */}
      {showNewPatient && <NewPatientModal onClose={handleNewPatientClose} onSave={addPatient}/>}
      {viewPatient && (
        <PatientViewModal
          patient={viewPatient}
          appointments={appointments}
          records={records}
          onClose={()=>setViewPatient(null)}
          onViewConsultation={(p, consultation)=>{setViewPatient(null);navigate(`/doctor/consultations-history?patientId=${p.id}${consultation?.consultationId ? `&consultationId=${consultation.consultationId}` : ''}`);}}
          onCreateAppointment={()=>navigate('/doctor/appointments')}
        />
      )}
      {patientToEdit && (
        <EditPatientModal
          patient={patientToEdit}
          role={user?.role}
          onClose={(updated)=>{
            setPatientToEdit(null);
            if (updated) {
              showToast('Patient updated successfully', 'success');
            }
          }}
          onSave={updatePatient}
        />
      )}
      {outstanding && <OutstandingBalanceModal data={outstanding} onClose={()=>setOutstanding(null)}/>}
      {financialHistory && <FinancialHistoryModal data={financialHistory.loading ? null : financialHistory} onClose={()=>setFinancialHistory(null)}/>}

      {/* Remove Confirmation Modal */}
      {patientToRemove && (
        <div style={{
          position: 'fixed',
          inset: 0,
          background: 'rgba(15, 17, 23, 0.6)',
          backdropFilter: 'blur(4px)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          zIndex: 1000,
          animation: 'fadeIn 0.2s ease-out'
        }}>
          <div className="card" style={{
            width: '90%',
            maxWidth: 420,
            padding: 24,
            borderRadius: 16,
            boxShadow: '0 20px 25px -5px rgba(0,0,0,0.1), 0 10px 10px -5px rgba(0,0,0,0.04)',
            background: 'var(--clr-card)'
          }}>
            <h3 style={{ margin: 0, fontSize: '1.1rem', fontWeight: 800, color: 'var(--clr-text)', display: 'flex', alignItems: 'center', gap: 10 }}>
              <Trash2 size={20} color="var(--clr-danger)" />
              Confirm Removal
            </h3>
            <p style={{ marginTop: 14, marginBottom: 20, fontSize: '0.88rem', color: 'var(--clr-subtext)', lineHeight: 1.5 }}>
              Are you sure you want to remove patient <strong style={{ color: 'var(--clr-text)' }}>{patientToRemove.name}</strong>?
              {getPatientStats(patientToRemove.id).records > 0 && (
                <span style={{ display: 'block', marginTop: 8, padding: 8, background: '#FEF2F2', borderRadius: 8, color: 'var(--clr-danger)', fontSize: '0.78rem', fontWeight: 700 }}>
                  ⚠️ This patient has existing medical reports. They will be safely archived instead of completely deleted to preserve history.
                </span>
              )}
            </p>
            <div style={{ display: 'flex', gap: 10, justifyContent: 'flex-end' }}>
              <button 
                onClick={() => setPatientToRemove(null)} 
                className="btn btn-secondary btn-sm" 
                disabled={isDeleting}
                style={{ minWidth: 80 }}
              >
                Cancel
              </button>
              <button 
                onClick={handleRemovePatient} 
                className="btn btn-danger btn-sm"
                disabled={isDeleting}
                style={{ minWidth: 120, background: 'var(--clr-danger)', borderColor: 'var(--clr-danger)', color: '#fff' }}
              >
                {isDeleting ? 'Removing…' : 'Remove Patient'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Toast Feedback */}
      {toast && (
        <div style={{
          position: 'fixed',
          bottom: 24,
          right: 24,
          padding: '12px 20px',
          borderRadius: 10,
          background: toast.type === 'success' ? 'var(--clr-primary-light)' : '#FEF2F2',
          border: `1px solid ${toast.type === 'success' ? 'rgba(16,185,129,0.2)' : 'rgba(239,68,68,0.2)'}`,
          color: toast.type === 'success' ? 'var(--clr-primary-dark)' : 'var(--clr-error)',
          fontWeight: 700,
          fontSize: '0.84rem',
          boxShadow: '0 10px 15px -3px rgba(0,0,0,0.1)',
          display: 'flex',
          alignItems: 'center',
          gap: 8,
          zIndex: 1100,
          animation: 'fadeIn 0.2s ease-out'
        }}>
          {toast.type === 'success' ? '✓' : '⚠️'} {toast.message}
        </div>
      )}
    </Layout>
  );
}
