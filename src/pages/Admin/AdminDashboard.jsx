import { useEffect,useMemo,useState } from 'react';
import { AlertCircle,CheckCircle2,Loader2,Settings,ShieldCheck,Stethoscope,UserCircle,UserPlus,Users } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import Layout from '../../components/Layout.jsx';
import { listAdminUsers } from '../../services/adminUsersApi.js';

export default function AdminDashboard(){
  const navigate=useNavigate();
  const [accounts,setAccounts]=useState([]),[loading,setLoading]=useState(true),[error,setError]=useState('');
  const load=async()=>{setLoading(true);setError('');try{setAccounts(await listAdminUsers());}catch(e){setError(e.message);}finally{setLoading(false);}};
  // Admin overview is hydrated exclusively from the authoritative account RPC.
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(()=>{load();},[]);
  const metrics=useMemo(()=>[
    {label:'Application Accounts',value:accounts.length,icon:Users},
    {label:'Active Doctors',value:accounts.filter(a=>a.role==='doctor'&&a.isActive).length,icon:Stethoscope},
    {label:'Active Receptionists',value:accounts.filter(a=>a.role==='receptionist'&&a.isActive).length,icon:UserCircle},
    {label:'Linked Accounts',value:accounts.filter(a=>a.isLinked).length,icon:ShieldCheck},
  ],[accounts]);
  return <Layout pageTitle="Admin Overview" pageSubtitle="Authoritative clinic account administration"><div className="page-stack animate-fadeIn">
    <div style={{display:'flex',gap:10,flexWrap:'wrap'}}><button className="btn btn-primary" onClick={()=>navigate('/admin/users')}><UserPlus size={16}/> Add or Manage Users</button><button className="btn btn-secondary" onClick={()=>navigate('/admin/settings')}><Settings size={16}/> Settings</button></div>
    {loading?<div className="card" role="status" style={{padding:55,textAlign:'center'}}><Loader2 className="animate-spin"/> Loading Admin overview…</div>:error?<div className="card" role="alert" style={{padding:32,textAlign:'center'}}><AlertCircle size={24}/><p>{error}</p><button className="btn btn-secondary" onClick={load}>Retry</button></div>:<>
      <section className="metric-grid">{metrics.map(metric=><div className="card stat-card" key={metric.label}><div className="stat-icon"><metric.icon size={20}/></div><div><div className="stat-value">{metric.value}</div><div className="stat-label">{metric.label}</div></div></div>)}</section>
      <section className="card"><div className="section-header"><div><h2 className="section-title">Recently Listed Accounts</h2><p className="section-subtitle">Current application identities from Supabase</p></div><button className="btn btn-secondary btn-sm" onClick={()=>navigate('/admin/users')}>View All</button></div>
        <div className="table-wrap"><table className="table"><thead><tr><th>Name</th><th>Clinic Email</th><th>Role</th><th>Status</th></tr></thead><tbody>{accounts.slice(0,6).map(account=><tr key={account.id}><td><strong>{account.fullName}</strong></td><td>{account.clinicEmail}</td><td>{account.role}</td><td>{account.isActive?<span className="badge badge-success"><CheckCircle2 size={12}/> Active</span>:<span className="badge badge-danger">Inactive</span>}</td></tr>)}{accounts.length===0&&<tr><td colSpan="4" style={{textAlign:'center',padding:30}}>No application accounts found.</td></tr>}</tbody></table></div>
      </section>
    </>}
  </div></Layout>;
}
