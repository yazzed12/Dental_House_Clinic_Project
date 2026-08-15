import React,{ useEffect,useMemo,useRef,useState } from 'react';
import { AlertCircle,CheckCircle2,Eye,EyeOff,Loader2,LockKeyhole,Plus,Search,ShieldCheck,Trash2,UserRound,X } from 'lucide-react';
import Layout from '../../components/Layout.jsx';
import { useAuth } from '../../context/AuthContext.jsx';
import { createAdminStaff,deleteAdminManagedUser,getAdminUser,listAdminUsers,resetAdminUserPassword,updateAdminUser } from '../../services/adminUsersApi.js';

const blank={fullName:'',clinicEmail:'',personalEmail:'',phone:'',role:'doctor',specialization:'',password:'',confirmPassword:'',isActive:true};
const roleLabel=role=>String(role||'Unknown').replaceAll('_',' ').replace(/\b\w/g,letter=>letter.toUpperCase());
const validEmail=value=>/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value.trim());

export function AccountModal({user,currentUserId,onClose,onSaved,onDeleted,loadUser=getAdminUser,deleteUser=deleteAdminManagedUser}) {
  const creating=!user;
  const [form,setForm]=useState(creating?blank:{...blank,...user});
  const [loading,setLoading]=useState(!creating),[saving,setSaving]=useState(false),[error,setError]=useState(''),[success,setSuccess]=useState('');
  const [errorField,setErrorField]=useState('');
  const [showPassword,setShowPassword]=useState(false);
  const [resetPassword,setResetPassword]=useState(''),[resetConfirmation,setResetConfirmation]=useState('');
  const [resetting,setResetting]=useState(false),[resetError,setResetError]=useState(''),[resetSuccess,setResetSuccess]=useState('');
  const [showResetPassword,setShowResetPassword]=useState(false);
  const [deleteOpen,setDeleteOpen]=useState(false),[deleteConfirmation,setDeleteConfirmation]=useState('');
  const [deleting,setDeleting]=useState(false),[deleteError,setDeleteError]=useState('');
  const deleteInFlight=useRef(false);
  useEffect(()=>{if(!user)return;loadUser(user.id).then(value=>setForm({...blank,...value})).catch(e=>setError(e.message)).finally(()=>setLoading(false));},[user,loadUser]);
  const change=(key,value)=>setForm(current=>({...current,[key]:value}));
  const deletionPending=!creating&&form.deletionStatus==='pending_auth_delete';
  const accountLocked=!creating&&form.deletionStatus!=='active';
  const submit=async event=>{event.preventDefault();if(saving||accountLocked)return;setError('');setErrorField('');setSuccess('');
    if(!form.fullName.trim()||!form.clinicEmail.trim()){setError('Full Name and Clinic Login Email are required.');setErrorField(!form.fullName.trim()?'fullName':'clinicEmail');return;}
    if(!validEmail(form.clinicEmail)||(creating&&!validEmail(form.personalEmail))){setError('Enter valid Clinic Login and Personal/Auth email addresses.');setErrorField(!validEmail(form.clinicEmail)?'clinicEmail':'personalEmail');return;}
    if(creating&&(!form.personalEmail.trim()||form.password.length<8||form.password!==form.confirmPassword)){setError(form.password!==form.confirmPassword?'Passwords do not match.':'Personal/Auth Email and a password of at least 8 characters are required.');setErrorField(!form.personalEmail.trim()?'personalEmail':'password');return;}
    if(form.role==='doctor'&&!form.specialization.trim()){setError('Specialization is required for Doctors.');setErrorField('specialization');return;}
    setSaving(true);try{const saved=creating?await createAdminStaff({...form,fullName:form.fullName.trim(),clinicEmail:form.clinicEmail.trim().toLowerCase(),personalEmail:form.personalEmail.trim().toLowerCase()}):await updateAdminUser(user.id,{...form,fullName:form.fullName.trim(),clinicEmail:form.clinicEmail.trim().toLowerCase()});setSuccess(creating?'Account created and linked.':'Account updated.');await onSaved(saved);}
    catch(e){setError(e.message);setErrorField(e.code==='CLINIC_EMAIL_ALREADY_EXISTS'?'clinicEmail':e.code==='PERSONAL_EMAIL_ALREADY_EXISTS'?'personalEmail':e.code==='PASSWORD_POLICY_INVALID'?'password':'');}finally{setSaving(false);}};
  const resetAccountPassword=async event=>{event.preventDefault();if(resetting||creating||accountLocked||!form.isLinked)return;setResetError('');setResetSuccess('');
    if(resetPassword.length<8||resetPassword.length>256){setResetError('New password must be between 8 and 256 characters.');return;}
    if(resetPassword!==resetConfirmation){setResetError('Passwords do not match.');return;}
    setResetting(true);try{await resetAdminUserPassword(user.id,resetPassword);setResetPassword('');setResetConfirmation('');setResetSuccess('Password reset successfully.');}
    catch(e){setResetError(e.message);}finally{setResetting(false);}};
  const isSelf=!creating&&String(user.id)===String(currentUserId);
  const expectedConfirmation=`DELETE ${form.clinicEmail}`;
  const deleteAccount=async()=>{if(deleteInFlight.current||deleting||isSelf||deleteConfirmation!==expectedConfirmation)return;deleteInFlight.current=true;setDeleting(true);setDeleteError('');
    try{await deleteUser(user.id);setResetPassword('');setResetConfirmation('');setDeleteConfirmation('');setDeleteOpen(false);await onDeleted(user.id);}
    catch(e){if(e.code==='AUTH_DELETE_FAILED'||e.code==='ACCOUNT_FINALIZE_FAILED')setForm(current=>({...current,deletionStatus:'pending_auth_delete',isActive:false}));setDeleteError(e.message);}finally{deleteInFlight.current=false;setDeleting(false);}};
  return <div className="modal-overlay" role="dialog" aria-modal="true" aria-labelledby="account-dialog-title" onClick={()=>!saving&&!deleting&&onClose()}><form className="modal card" onClick={e=>e.stopPropagation()} onSubmit={submit} style={{width:'min(680px,100%)',padding:0,overflow:'auto',maxHeight:'92vh'}}>
    <header style={{padding:'20px 24px',borderBottom:'1px solid var(--clr-border)',display:'flex',justifyContent:'space-between'}}><div><h2 id="account-dialog-title" style={{margin:0}}>{creating?'Add User':'Account Information'}</h2><p className="muted" style={{margin:'4px 0 0'}}>Supabase-linked clinic staff account</p></div><button type="button" className="icon-btn" aria-label="Close account" disabled={deleting} onClick={onClose}><X size={18}/></button></header>
    {loading?<div role="status" style={{padding:60,textAlign:'center'}}><Loader2 className="animate-spin"/> Loading account…</div>:<div style={{padding:24}}>
      {error&&<div role="alert" className="auth-alert" style={{marginBottom:16}}><AlertCircle size={17}/>{error}</div>}{success&&<div role="status" style={{color:'var(--clr-success)',marginBottom:16,display:'flex',gap:8}}><CheckCircle2 size={17}/>{success}</div>}
      {deletionPending&&<div role="status" className="auth-alert" style={{marginBottom:16}}><AlertCircle size={17}/><div><strong>Deletion pending</strong><div>Normal editing and password reset are disabled. Retry Delete Account to finish safely.</div></div></div>}
      <fieldset disabled={accountLocked} style={{border:0,padding:0,margin:0,minWidth:0}}><div className="grid-2" style={{gap:14}}>
        <label className="form-label">Full Name<input className="form-input" value={form.fullName} onChange={e=>change('fullName',e.target.value)} required/></label>
        <label className="form-label">Clinic Login Email<input className="form-input" type="email" value={form.clinicEmail} onChange={e=>change('clinicEmail',e.target.value)} aria-invalid={errorField==='clinicEmail'} required/></label>
        {creating&&<label className="form-label">Personal/Auth Email<input className="form-input" type="email" value={form.personalEmail} onChange={e=>change('personalEmail',e.target.value)} aria-invalid={errorField==='personalEmail'} required/></label>}
        <label className="form-label">Phone<input className="form-input" value={form.phone||''} onChange={e=>change('phone',e.target.value)}/></label>
        {creating?<label className="form-label">Role<select className="form-input" value={form.role} onChange={e=>change('role',e.target.value)}><option value="doctor">Doctor</option><option value="receptionist">Receptionist</option></select></label>:<label className="form-label">Role<input className="form-input" value={roleLabel(form.role)} readOnly aria-readonly="true"/></label>}
        {form.role==='doctor'&&<label className="form-label">Specialization<input className="form-input" value={form.specialization||''} onChange={e=>change('specialization',e.target.value)} aria-invalid={errorField==='specialization'} required/></label>}
        {creating&&<><label className="form-label">Initial Password<div className="admin-password-field"><input className="form-input" type={showPassword?'text':'password'} value={form.password} onChange={e=>change('password',e.target.value)} aria-invalid={errorField==='password'} minLength="8" required/><button type="button" aria-label={showPassword?'Hide initial password':'Show initial password'} aria-pressed={showPassword} onClick={()=>setShowPassword(value=>!value)}>{showPassword?<EyeOff size={17}/>:<Eye size={17}/>}</button></div></label><label className="form-label">Confirm Initial Password<input className="form-input" type={showPassword?'text':'password'} value={form.confirmPassword} onChange={e=>change('confirmPassword',e.target.value)} minLength="8" required/></label></>}
        {!creating&&<label className="form-label" style={{display:'flex',alignItems:'center',gap:10,marginTop:22}}><input type="checkbox" checked={Boolean(form.isActive)} disabled={form.role==='admin'} onChange={e=>change('isActive',e.target.checked)}/> Active account{form.role==='admin'&&' (Admin status protected)'}</label>}
      </div></fieldset>
      <p className="muted" style={{fontSize:'.76rem',marginTop:16}}>Private Auth email and Supabase identity are never changed through normal account editing.</p>
      {!creating&&!accountLocked&&<section aria-labelledby="account-security-title" style={{borderTop:'1px solid var(--clr-border)',marginTop:22,paddingTop:20}}>
        <div style={{display:'flex',gap:10,alignItems:'center'}}><LockKeyhole size={18}/><div><h3 id="account-security-title" style={{margin:0}}>Security</h3><p className="muted" style={{fontSize:'.78rem',margin:'3px 0 0'}}>Set a new password for this account. The current password is never available.</p></div></div>
        <label className="form-label" style={{marginTop:14}}>Password<input className="form-input" type="password" value="••••••••" readOnly aria-readonly="true" tabIndex="-1"/></label>
        {!form.isLinked?<div role="alert" className="auth-alert" style={{marginTop:14}}><AlertCircle size={17}/>This account is not linked to Supabase Auth yet.</div>:<>
          {resetError&&<div role="alert" className="auth-alert" style={{marginTop:14}}><AlertCircle size={17}/>{resetError}</div>}
          {resetSuccess&&<div role="status" style={{color:'var(--clr-success)',marginTop:14,display:'flex',gap:8}}><CheckCircle2 size={17}/>{resetSuccess}</div>}
          <div className="grid-2" style={{gap:14,marginTop:14}}>
            <label className="form-label">New Password<div className="admin-password-field"><input className="form-input" type={showResetPassword?'text':'password'} value={resetPassword} onChange={e=>{setResetPassword(e.target.value);setResetSuccess('');}} minLength="8" maxLength="256" autoComplete="new-password"/><button type="button" aria-label={showResetPassword?'Hide new password':'Show new password'} aria-pressed={showResetPassword} onClick={()=>setShowResetPassword(value=>!value)}>{showResetPassword?<EyeOff size={17}/>:<Eye size={17}/>}</button></div></label>
            <label className="form-label">Confirm New Password<input className="form-input" type={showResetPassword?'text':'password'} value={resetConfirmation} onChange={e=>{setResetConfirmation(e.target.value);setResetSuccess('');}} minLength="8" maxLength="256" autoComplete="new-password"/></label>
          </div>
          <button type="button" className="btn btn-secondary" onClick={resetAccountPassword} disabled={resetting||!resetPassword||!resetConfirmation} style={{marginTop:14}}>{resetting?<><Loader2 size={15} className="animate-spin"/> Resetting…</>:<><LockKeyhole size={15}/> Reset Password</>}</button>
        </>}
      </section>}
      {!creating&&<section aria-labelledby="account-danger-title" style={{border:'1px solid var(--clr-danger)',borderRadius:10,marginTop:22,padding:18}}>
        <div style={{display:'flex',gap:10,alignItems:'center',color:'var(--clr-danger)'}}><Trash2 size={18}/><div><h3 id="account-danger-title" style={{margin:0}}>Danger Zone</h3><p style={{fontSize:'.78rem',margin:'3px 0 0'}}>Delete Account</p></div></div>
        <p style={{fontSize:'.82rem'}}>{deletionPending?'Retrying deletion for':'Deleting'} <strong>{form.fullName}</strong> ({roleLabel(form.role)}, {form.clinicEmail}) permanently removes login access.</p>
        <p className="muted" style={{fontSize:'.78rem'}}>Historical clinic records created by this account will remain preserved.</p>
        {isSelf&&<div role="status" className="auth-alert"><AlertCircle size={17}/>You cannot delete your own account.</div>}
        <button type="button" className="btn btn-danger" disabled={isSelf||deleting} onClick={()=>{setDeleteError('');setDeleteConfirmation('');setDeleteOpen(true);}}><Trash2 size={15}/> {deletionPending?'Retry Delete Account':'Delete Account'}</button>
      </section>}
      <div style={{display:'flex',justifyContent:'flex-end',gap:10,marginTop:22}}><button type="button" className="btn btn-secondary" disabled={deleting} onClick={onClose}>Cancel</button>{!accountLocked&&<button className="btn btn-primary" disabled={saving||deleting}>{saving?<><Loader2 size={15} className="animate-spin"/> Saving…</>:creating?'Create Account':'Save Changes'}</button>}</div>
    </div>}
    {deleteOpen&&<div className="modal-overlay" role="dialog" aria-modal="true" aria-labelledby="delete-account-title" onClick={()=>!deleting&&setDeleteOpen(false)} style={{zIndex:11000}}><div className="modal card" onClick={e=>e.stopPropagation()} onKeyDown={e=>{if(e.key==='Enter')e.preventDefault();}} style={{width:'min(520px,100%)',padding:24}}>
      <h2 id="delete-account-title" style={{marginTop:0}}>Permanently delete account?</h2>
      <p><strong>{form.fullName}</strong> — {roleLabel(form.role)} — {form.clinicEmail}</p>
      <p>Login access will be permanently removed. Historical clinic records will remain preserved.</p>
      <label className="form-label">Type <strong>{expectedConfirmation}</strong> to continue<input className="form-input" value={deleteConfirmation} disabled={deleting} autoComplete="off" onChange={e=>setDeleteConfirmation(e.target.value)}/></label>
      {deleteError&&<div role="alert" className="auth-alert" style={{marginTop:14}}><AlertCircle size={17}/>{deleteError}</div>}
      <div style={{display:'flex',justifyContent:'flex-end',gap:10,marginTop:20,flexWrap:'wrap'}}><button type="button" className="btn btn-secondary" disabled={deleting} onClick={()=>setDeleteOpen(false)}>Cancel</button><button type="button" className="btn btn-danger" disabled={deleting||deleteConfirmation!==expectedConfirmation} onClick={deleteAccount}>{deleting?<><Loader2 size={15} className="animate-spin"/> Deleting…</>:<><Trash2 size={15}/> Delete Account</>}</button></div>
    </div></div>}
  </form></div>;
}

export default function UserManagement(){
  const {user:currentUser}=useAuth();
  const [users,setUsers]=useState([]),[loading,setLoading]=useState(true),[error,setError]=useState(''),[search,setSearch]=useState(''),[role,setRole]=useState('all'),[active,setActive]=useState('all'),[selected,setSelected]=useState(undefined);
  const [notice,setNotice]=useState('');
  const load=async()=>{setLoading(true);setError('');try{setUsers(await listAdminUsers());}catch(e){setError(e.message);}finally{setLoading(false);}};
  // Initial hydration is an external Supabase synchronization.
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(()=>{load();},[]);
  const roles=useMemo(()=>[...new Set(users.map(user=>user.role).filter(Boolean))].sort(),[users]);
  const filtered=useMemo(()=>{const q=search.trim().toLowerCase();return users.filter(user=>(!q||`${user.fullName} ${user.clinicEmail}`.toLowerCase().includes(q))&&(role==='all'||user.role===role)&&(active==='all'||String(user.isActive)===active));},[users,search,role,active]);
  const saved=async()=>{await load();};
  const deleted=async userId=>{setSelected(undefined);setNotice('Account deleted. Historical clinic records were preserved.');
    try{const refreshed=await listAdminUsers();setUsers(refreshed.filter(item=>String(item.id)!==String(userId)));}catch(e){setUsers(current=>current.filter(item=>String(item.id)!==String(userId)));setError(e.message);}};
  return <Layout pageTitle="User Management" pageSubtitle="Manage Supabase-linked clinic staff accounts"><div className="page-stack animate-fadeIn">
    {notice&&<div role="status" className="card" style={{padding:14,color:'var(--clr-success)',display:'flex',gap:8}}><CheckCircle2 size={17}/>{notice}</div>}
    <div style={{display:'flex',gap:12,flexWrap:'wrap',alignItems:'center'}}><div style={{position:'relative',flex:'1 1 280px'}}><Search size={17} style={{position:'absolute',left:13,top:13}}/><input className="form-input" aria-label="Search users" placeholder="Search by name or clinic email…" value={search} onChange={e=>setSearch(e.target.value)} style={{paddingLeft:40}}/></div><select className="form-input" aria-label="Filter by role" value={role} onChange={e=>setRole(e.target.value)} style={{width:160}}><option value="all">All roles</option>{roles.map(value=><option key={value} value={value}>{roleLabel(value)}</option>)}</select><select className="form-input" aria-label="Filter by active status" value={active} onChange={e=>setActive(e.target.value)} style={{width:150}}><option value="all">All statuses</option><option value="true">Active</option><option value="false">Inactive</option></select><button className="btn btn-primary" onClick={()=>setSelected(null)}><Plus size={17}/> Add User</button></div>
    {loading?<div className="card" role="status" style={{padding:60,textAlign:'center'}}><Loader2 className="animate-spin"/> Loading users…</div>:error?<div className="card" role="alert" style={{padding:32,textAlign:'center'}}><AlertCircle/> <p>{error}</p><button className="btn btn-secondary" onClick={load}>Retry</button></div>:filtered.length===0?<div className="card" style={{padding:55,textAlign:'center'}}><UserRound size={34}/><h3>No matching users</h3></div>:<div className="card table-wrap"><table className="table"><thead><tr><th>User</th><th>Role</th><th>Phone</th><th>Approval</th><th>Status</th><th></th></tr></thead><tbody>{filtered.map(user=><tr key={user.id}><td><strong>{user.fullName}</strong><small style={{display:'block'}}>{user.clinicEmail}</small></td><td>{roleLabel(user.role)}{user.role==='doctor'&&user.specialization?<small style={{display:'block'}}>{user.specialization}</small>:null}</td><td>{user.phone||'—'}</td><td>{user.approvedAt?<span className="badge badge-success"><ShieldCheck size={12}/> Approved</span>:<span className="badge">Pending</span>}</td><td>{user.deletionStatus==='pending_auth_delete'?<span className="badge badge-danger">Deletion pending</span>:<span className={`badge ${user.isActive?'badge-success':'badge-danger'}`}>{user.isActive?'Active':'Inactive'}</span>}</td><td><button className="btn btn-secondary btn-sm" onClick={()=>setSelected(user)}>Open</button></td></tr>)}</tbody></table></div>}
    {selected!==undefined&&<AccountModal user={selected} currentUserId={currentUser?.id} onClose={()=>setSelected(undefined)} onSaved={saved} onDeleted={deleted}/>} </div></Layout>;
}
