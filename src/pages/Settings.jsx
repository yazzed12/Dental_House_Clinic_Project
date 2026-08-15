import React,{ useEffect, useRef, useState } from 'react';
import { AlertCircle, Building, CheckCircle2, Eye, EyeOff, Loader2, LockKeyhole, Save, Trash2, User, X } from 'lucide-react';
import Layout from '../components/Layout.jsx';
import { useAuth } from '../context/AuthContext.jsx';
import { useClinic } from '../context/ClinicContext.jsx';
import { getCurrentProfile, updateCurrentProfile, updatePassword } from '../services/profileApi.js';
import { formatClinicData } from '../services/adminClinicApi.js';

function SettingsCard({ icon: Icon, title, subtitle, children }) {
  return <section className="card" style={{ padding: 22 }}>
    <div style={{ display: 'flex', gap: 12, alignItems: 'center', paddingBottom: 16, marginBottom: 18, borderBottom: '1px solid var(--clr-border)' }}>
      <span style={{ width: 38, height: 38, borderRadius: 10, display: 'grid', placeItems: 'center', color: 'var(--clr-primary)', background: 'var(--clr-primary-light)' }}><Icon size={18} /></span>
      <div><h2 style={{ margin: 0, fontSize: '1rem' }}>{title}</h2><p className="muted" style={{ margin: '3px 0 0', fontSize: '.78rem' }}>{subtitle}</p></div>
    </div>
    {children}
  </section>;
}

const Feedback = ({ error, success }) => error ? <div role="alert" style={{ color: 'var(--clr-danger)', display: 'flex', gap: 7, marginTop: 12 }}><AlertCircle size={16} />{error}</div> : success ? <div role="status" style={{ color: 'var(--clr-success)', display: 'flex', gap: 7, marginTop: 12 }}><CheckCircle2 size={16} />{success}</div> : null;
const LoadingCard = ({ label }) => <div className="card" role="status" style={{ padding: 52, textAlign: 'center' }}><Loader2 className="animate-spin" /> <p>{label}</p></div>;
const LoadError = ({ message, onRetry }) => <div className="card" role="alert" style={{ padding: 30, textAlign: 'center' }}><AlertCircle size={24} color="var(--clr-danger)" /><p>{message}</p><button className="btn btn-secondary" onClick={onRetry}>Retry</button></div>;

export function FormatClinicDangerZone({userRole,formatAction=formatClinicData,reload=()=>window.location.reload(),schedule=(callback)=>window.setTimeout(callback,700)}) {
  const [formatOpen,setFormatOpen]=useState(false);
  const [formatConfirmation,setFormatConfirmation]=useState('');
  const [formatting,setFormatting]=useState(false);
  const [formatError,setFormatError]=useState('');
  const [formatComplete,setFormatComplete]=useState(false);
  const formatInFlight=useRef(false);
  if(userRole!=='admin')return null;
  const runFormat=async()=>{if(formatInFlight.current||formatting||formatConfirmation!=='FORMAT CLINIC')return;formatInFlight.current=true;setFormatting(true);setFormatError('');
    try{await formatAction();setFormatComplete(true);schedule(reload);}
    catch(error){formatInFlight.current=false;setFormatError(error.message||'Clinic data could not be formatted safely.');setFormatting(false);}};
  return <>
    <section className="card" aria-labelledby="format-danger-title" style={{padding:22,border:'1px solid var(--clr-danger)'}}>
      <div style={{display:'flex',gap:12,alignItems:'center',color:'var(--clr-danger)'}}><Trash2 size={20}/><div><h2 id="format-danger-title" style={{margin:0,fontSize:'1rem'}}>Danger Zone</h2><p style={{margin:'3px 0 0',fontSize:'.8rem'}}>Format Clinic Data</p></div></div>
      <p>This permanently removes old clinic data so the clinic can start with new real data.</p>
      <p className="muted" style={{fontSize:'.8rem'}}>All user accounts, login identities, roles, approvals, Clinic Settings, and system functionality remain unchanged.</p>
      <button type="button" className="btn btn-danger" onClick={()=>{setFormatConfirmation('');setFormatError('');setFormatComplete(false);setFormatOpen(true);}}><Trash2 size={15}/> Format Clinic Data</button>
    </section>
    {formatOpen&&<div className="modal-overlay" role="dialog" aria-modal="true" aria-labelledby="format-clinic-title" onClick={()=>!formatting&&!formatComplete&&setFormatOpen(false)}>
      <div className="modal card" onClick={event=>event.stopPropagation()} onKeyDown={event=>{if(event.key==='Enter')event.preventDefault();}} style={{width:'min(650px,100%)',padding:24,maxHeight:'92vh',overflow:'auto'}}>
        <div style={{display:'flex',justifyContent:'space-between',gap:12}}><div><h2 id="format-clinic-title" style={{marginTop:0}}>Format Clinic Data</h2><p>This permanently removes old clinic data so the clinic can start with new real data.</p></div><button type="button" className="icon-btn" aria-label="Close Format Clinic" disabled={formatting||formatComplete} onClick={()=>setFormatOpen(false)}><X size={18}/></button></div>
        <div className="grid-2" style={{gap:18,alignItems:'start'}}>
          <section><h3 style={{fontSize:'.9rem',color:'var(--clr-danger)'}}>Will be deleted</h3><ul style={{paddingInlineStart:20,fontSize:'.82rem'}}>{['Patients','Dental state','Appointments','Consultations','Medical reports / clinical history','Patient financial history','Consultation Lab history','Lab payments','Labs','Lab Product List','Notifications','Operational logs'].map(item=><li key={item}>{item}</li>)}</ul></section>
          <section><h3 style={{fontSize:'.9rem',color:'var(--clr-success)'}}>Will be preserved</h3><ul style={{paddingInlineStart:20,fontSize:'.82rem'}}>{['Admin accounts','Doctor accounts','Receptionist accounts','Login emails','Passwords / Supabase Auth identities','Roles / approvals','Clinic Settings','Procedure catalog','Symptoms catalog','Appointment-condition catalog','Database/system functionality'].map(item=><li key={item}>{item}</li>)}</ul></section>
        </div>
        <label className="form-label">Type <strong>FORMAT CLINIC</strong> to continue<input className="form-input" autoComplete="off" disabled={formatting||formatComplete} value={formatConfirmation} onChange={event=>setFormatConfirmation(event.target.value)}/></label>
        {formatError&&<div role="alert" className="auth-alert" style={{marginTop:14}}><AlertCircle size={17}/>{formatError}</div>}
        {formatComplete&&<div role="status" style={{color:'var(--clr-success)',marginTop:14,display:'flex',gap:8}}><CheckCircle2 size={17}/>Clinic data was formatted. Reloading authoritative data…</div>}
        <div style={{display:'flex',justifyContent:'flex-end',gap:10,marginTop:20,flexWrap:'wrap'}}><button type="button" className="btn btn-secondary" disabled={formatting||formatComplete} onClick={()=>setFormatOpen(false)}>Cancel</button><button type="button" className="btn btn-danger" disabled={formatting||formatComplete||formatConfirmation!=='FORMAT CLINIC'} onClick={runFormat}>{formatting||formatComplete?<><Loader2 size={15} className="animate-spin"/> Formatting…</>:<><Trash2 size={15}/> Format Clinic Data</>}</button></div>
      </div>
    </div>}
  </>;
}

export default function Settings() {
  const { user, refreshProfile } = useAuth();
  const { clinicSettings, loading: clinicLoading, error: clinicLoadError, updateClinicSettings, refreshClinicSettings } = useClinic();
  const canManageClinic = user?.role === 'doctor' || user?.role === 'admin';
  const [activeTab, setActiveTab] = useState('profile');
  const [profile, setProfile] = useState(null);
  const [profileLoading, setProfileLoading] = useState(true);
  const [profileLoadError, setProfileLoadError] = useState('');
  const [profileSaving, setProfileSaving] = useState(false);
  const [profileFeedback, setProfileFeedback] = useState({ error: '', success: '' });
  const [password, setPassword] = useState({ next: '', confirm: '' });
  const [showPasswords, setShowPasswords] = useState(false);
  const [passwordSaving, setPasswordSaving] = useState(false);
  const [passwordFeedback, setPasswordFeedback] = useState({ error: '', success: '' });
  const [clinic, setClinic] = useState(null);
  const [clinicSaving, setClinicSaving] = useState(false);
  const [clinicFeedback, setClinicFeedback] = useState({ error: '', success: '' });

  const loadProfile = async () => {
    setProfileLoading(true); setProfileLoadError('');
    try {
      const value = await getCurrentProfile();
      if (!value) throw new Error('Your profile could not be found.');
      setProfile({ fullName: value.full_name || '', email: value.email || '', phone: value.phone || '', specialization: value.specialization || '' });
    } catch (error) { setProfile(null); setProfileLoadError(error.message || 'Your profile could not be loaded.'); }
    finally { setProfileLoading(false); }
  };

  // Initial hydration synchronizes the component with the authenticated profile.
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { loadProfile(); }, []);
  useEffect(() => {
    // ClinicContext is the authoritative external source for this editable draft.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    if (clinicSettings) setClinic({ name: clinicSettings.name || '', email: clinicSettings.email || '', phone: clinicSettings.phone || '', address: clinicSettings.address || '' });
    else setClinic(null);
  }, [clinicSettings]);

  const saveProfile = async event => {
    event.preventDefault(); if (profileSaving || !profile) return;
    if (!profile.fullName.trim()) { setProfileFeedback({ error: 'Full Name is required.', success: '' }); return; }
    setProfileSaving(true); setProfileFeedback({ error: '', success: '' });
    try {
      const updated = await updateCurrentProfile({ fullName: profile.fullName.trim(), phone: profile.phone.trim(), specialization: user?.role === 'doctor' ? profile.specialization.trim() : null });
      setProfile(current => ({ ...current, fullName: updated.full_name || '', email: updated.email || current.email, phone: updated.phone || '', specialization: updated.specialization || '' }));
      await refreshProfile();
      setProfileFeedback({ error: '', success: 'Personal Information saved.' });
    } catch (error) { setProfileFeedback({ error: error.message || 'Personal Information could not be saved.', success: '' }); }
    finally { setProfileSaving(false); }
  };

  const savePassword = async event => {
    event.preventDefault(); if (passwordSaving) return;
    if (password.next.length < 8) { setPasswordFeedback({ error: 'Password must be at least 8 characters.', success: '' }); return; }
    if (password.next !== password.confirm) { setPasswordFeedback({ error: 'Passwords do not match.', success: '' }); return; }
    setPasswordSaving(true); setPasswordFeedback({ error: '', success: '' });
    try { await updatePassword(password.next); setPassword({ next: '', confirm: '' }); setPasswordFeedback({ error: '', success: 'Password updated securely.' }); }
    catch (error) { setPasswordFeedback({ error: error.message || 'Password could not be updated.', success: '' }); }
    finally { setPasswordSaving(false); }
  };

  const saveClinic = async event => {
    event.preventDefault(); if (clinicSaving || !clinic || clinicLoading || clinicLoadError) return;
    if (!clinic.name.trim()) { setClinicFeedback({ error: 'Clinic Name is required.', success: '' }); return; }
    setClinicSaving(true); setClinicFeedback({ error: '', success: '' });
    try {
      const updated = await updateClinicSettings({ name: clinic.name.trim(), email: clinic.email.trim(), phone: clinic.phone.trim(), address: clinic.address.trim() });
      setClinic({ name: updated.name || '', email: updated.email || '', phone: updated.phone || '', address: updated.address || '' });
      setClinicFeedback({ error: '', success: 'Clinic Information saved.' });
    } catch (error) { setClinicFeedback({ error: error.message || 'Clinic Information could not be saved.', success: '' }); }
    finally { setClinicSaving(false); }
  };


  return <Layout pageTitle="Settings" pageSubtitle="Manage your profile and clinic information">
    <div className="page-stack animate-fadeIn" style={{ maxWidth: 860 }}>
      <div className="card" style={{ padding: 8, overflowX: 'auto' }}><div role="tablist" aria-label="Settings sections" style={{ display: 'flex', gap: 7, width: 'max-content' }}>
        <button role="tab" aria-selected={activeTab === 'profile'} className={`btn ${activeTab === 'profile' ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setActiveTab('profile')}>Profile Settings</button>
        {canManageClinic && <button role="tab" aria-selected={activeTab === 'clinic'} className={`btn ${activeTab === 'clinic' ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setActiveTab('clinic')}>Clinic Settings</button>}
      </div></div>

      {activeTab === 'profile' && <div className="page-stack">
        {profileLoading ? <LoadingCard label="Loading Personal Information…" /> : profileLoadError ? <LoadError message={profileLoadError} onRetry={loadProfile} /> : <SettingsCard icon={User} title="Personal Information" subtitle="Your authenticated clinic profile">
          <form onSubmit={saveProfile}>
            <div className="grid-2" style={{ gap: 14 }}>
              <label className="form-label">Full Name<input className="form-input" value={profile.fullName} onChange={event => setProfile({ ...profile, fullName: event.target.value })} /></label>
              <label className="form-label">Login Email<input className="form-input" type="email" value={profile.email} readOnly aria-readonly="true" style={{ opacity: .72 }} /></label>
              <label className="form-label">Phone<input className="form-input" type="tel" value={profile.phone} onChange={event => setProfile({ ...profile, phone: event.target.value })} /></label>
              {user?.role === 'doctor' && <label className="form-label">Specialization<input className="form-input" value={profile.specialization} onChange={event => setProfile({ ...profile, specialization: event.target.value })} /></label>}
            </div>
            <Feedback {...profileFeedback} /><div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: 18 }}><button className="btn btn-primary" type="submit" disabled={profileSaving}><Save size={15} />{profileSaving ? 'Saving…' : 'Save Changes'}</button></div>
          </form>
        </SettingsCard>}

        <SettingsCard icon={LockKeyhole} title="Security" subtitle="Manage your Supabase account password securely">
          <form onSubmit={savePassword}><div className="grid-2" style={{ gap: 14 }}>
            <label className="form-label">New Password<div style={{ position: 'relative' }}><input className="form-input" type={showPasswords ? 'text' : 'password'} autoComplete="new-password" value={password.next} onChange={event => setPassword({ ...password, next: event.target.value })} /><button type="button" className="icon-btn" aria-label={showPasswords ? 'Hide passwords' : 'Show passwords'} onClick={() => setShowPasswords(value => !value)} style={{ position: 'absolute', right: 6, top: 5 }}>{showPasswords ? <EyeOff size={16} /> : <Eye size={16} />}</button></div></label>
            <label className="form-label">Confirm New Password<input className="form-input" type={showPasswords ? 'text' : 'password'} autoComplete="new-password" value={password.confirm} onChange={event => setPassword({ ...password, confirm: event.target.value })} /></label>
          </div><Feedback {...passwordFeedback} /><div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: 18 }}><button className="btn btn-primary" type="submit" disabled={passwordSaving}>{passwordSaving ? 'Updating…' : 'Update Password'}</button></div></form>
        </SettingsCard>
      </div>}

      {activeTab === 'clinic' && canManageClinic && <div className="page-stack">
        {clinicLoading ? <LoadingCard label="Loading Clinic Information…" /> : clinicLoadError || !clinic ? <LoadError message={clinicLoadError || 'Clinic Information could not be loaded.'} onRetry={() => refreshClinicSettings().catch(() => {})} /> : <SettingsCard icon={Building} title="Clinic Information" subtitle="Shared identity used across the clinic">
          <form onSubmit={saveClinic}><div className="grid-2" style={{ gap: 14 }}>
            <label className="form-label">Clinic Name<input className="form-input" value={clinic.name} onChange={event => setClinic({ ...clinic, name: event.target.value })} /></label>
            <label className="form-label">Clinic Email<input className="form-input" type="email" value={clinic.email} onChange={event => setClinic({ ...clinic, email: event.target.value })} /></label>
            <label className="form-label">Clinic Phone<input className="form-input" type="tel" value={clinic.phone} onChange={event => setClinic({ ...clinic, phone: event.target.value })} /></label>
            <label className="form-label">Clinic Address<input className="form-input" value={clinic.address} onChange={event => setClinic({ ...clinic, address: event.target.value })} /></label>
          </div><Feedback {...clinicFeedback} /><div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: 18 }}><button className="btn btn-primary" type="submit" disabled={clinicSaving}><Save size={15} />{clinicSaving ? 'Saving…' : 'Save Clinic Information'}</button></div></form>
        </SettingsCard>}
        <FormatClinicDangerZone userRole={user?.role}/>
      </div>}
    </div>
  </Layout>;
}
