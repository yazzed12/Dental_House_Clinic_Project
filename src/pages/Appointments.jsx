import { useState, useMemo } from 'react';
import Layout from '../components/Layout';
import { useData } from '../context/DataContext';
import { useAuth } from '../context/AuthContext';
import { DetailModal, EditModal } from '../components/AppointmentModals';
import {
  Search, Plus, Calendar, Clock, MapPin, User,
  X, ChevronLeft, ChevronRight, Eye, Edit3
} from 'lucide-react';
import AddModal from '../components/appointments/AddModal';

const STATUS_CLASS = {
  Confirmed: 'badge badge-success', Pending: 'badge badge-warning',
  Completed: 'badge badge-success', Cancelled: 'badge badge-danger', Missed: 'badge badge-muted',
};
const TYPE_CLASS = {
  'Follow-up': 'badge badge-primary', 'Consultation': 'badge badge-cyan',
  'Urgent': 'badge badge-danger', 'Check-up': 'badge badge-success',
  'Therapy': 'badge badge-purple', 'Surgery Prep': 'badge badge-warning',
};


/* ── Mini Calendar ─────────────────────────────────────────── */
function MiniCalendar({ selectedDate, onSelect }) {
  const initDate = selectedDate ? new Date(selectedDate + 'T00:00:00') : new Date();
  const [month, setMonth] = useState(new Date(initDate.getFullYear(), initDate.getMonth(), 1));
  const year = month.getFullYear(), mon = month.getMonth();
  const first = new Date(year, mon, 1).getDay(), days = new Date(year, mon + 1, 0).getDate();
  const { appointments } = useData();
  const dateStr = (d) => `${year}-${String(mon+1).padStart(2,'0')}-${String(d).padStart(2,'0')}`;
  const apptCounts = useMemo(() => {
    const counts = {};
    appointments.forEach(a => { counts[a.date] = (counts[a.date]||0) + 1; });
    return counts;
  }, [appointments]);
  const months = ['January','February','March','April','May','June','July','August','September','October','November','December'];

  return (
    <div className="card" style={{ padding:'var(--sp-md)' }}>
      <div style={{ display:'flex',alignItems:'center',justifyContent:'space-between',marginBottom:12 }}>
        <button className="icon-btn" style={{ width:28,height:28 }} onClick={()=>setMonth(new Date(year,mon-1,1))}><ChevronLeft size={14}/></button>
        <span style={{ fontSize:'0.85rem',fontWeight:700 }}>{months[mon]} {year}</span>
        <button className="icon-btn" style={{ width:28,height:28 }} onClick={()=>setMonth(new Date(year,mon+1,1))}><ChevronRight size={14}/></button>
      </div>
      <div style={{ display:'grid',gridTemplateColumns:'repeat(7,1fr)',gap:2,marginBottom:4 }}>
        {['S','M','T','W','T','F','S'].map((d,i)=>(
          <div key={i} style={{ textAlign:'center',fontSize:'0.65rem',color:'var(--clr-subtext)',fontWeight:700,padding:'2px 0' }}>{d}</div>
        ))}
      </div>
      <div style={{ display:'grid',gridTemplateColumns:'repeat(7,1fr)',gap:2 }}>
        {Array.from({length:first}).map((_,i)=><div key={`e${i}`}/>)}
        {Array.from({length:days},(_,i)=>i+1).map(d => {
          const ds = dateStr(d); const isSel = ds===selectedDate; const count = apptCounts[ds]||0;
          return (
            <button key={d} onClick={()=>onSelect(ds)} style={{
              aspectRatio:'1',borderRadius:'var(--r-sm)',border:'none',cursor:'pointer',
              fontSize:'0.75rem',fontWeight:count?700:400,position:'relative',
              background:isSel?'var(--grad-primary,var(--clr-primary))':'transparent',
              color:isSel?'#fff':count?'var(--clr-primary)':'var(--clr-subtext)',
              transition:'all 0.15s',
            }}>
              {d}
              {count>0 && !isSel && <span style={{ position:'absolute',bottom:1,left:'50%',transform:'translateX(-50%)',width:4,height:4,borderRadius:'50%',background:'var(--clr-primary)' }}/>}
            </button>
          );
        })}
      </div>
      {/* Today button */}
      <button onClick={()=>{const t=new Date();setMonth(new Date(t.getFullYear(),t.getMonth(),1));onSelect(t.toISOString().split('T')[0]);}}
        style={{ width:'100%',marginTop:10,padding:'6px 0',border:'1px solid var(--clr-border)',borderRadius:6,background:'transparent',color:'var(--clr-primary)',fontSize:'0.78rem',fontWeight:700,cursor:'pointer' }}>
        Today
      </button>
    </div>
  );
}

/* ── Appointments Page ─────────────────────────────────────── */
export default function Appointments() {
  const { user } = useAuth();
  const { appointments, patients, doctors, updateAppointmentStatus, updateAppointment } = useData();
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('All');
  const [selectedDate, setSelectedDate] = useState(new Date().toISOString().split('T')[0]);
  const [showAdd, setShowAdd] = useState(false);
  const [detailAppt, setDetailAppt] = useState(null);
  const [editAppt, setEditAppt] = useState(null);

  const filtered = useMemo(() => {
    return appointments.filter(a => {
      const q = search.toLowerCase();
      const matchSearch = !q || [a.displayId, a.patient, a.doctor, a.type, a.status, a.date, a.time, a.phone]
        .filter(Boolean).some(f => f.toLowerCase().includes(q));
      const matchStatus = statusFilter === 'All' || a.status === statusFilter;
      const matchDate = !selectedDate || a.date === selectedDate;
      return matchSearch && matchStatus && matchDate;
    });
  }, [appointments, search, statusFilter, selectedDate]);

  const dayCounts = useMemo(() => {
    const dateAppts = selectedDate ? appointments.filter(a => a.date === selectedDate) : appointments;
    return {
      total: dateAppts.length,
      completed: dateAppts.filter(a => a.status === 'Completed').length,
      pending: dateAppts.filter(a => ['Pending','Confirmed'].includes(a.status)).length,
      cancelled: dateAppts.filter(a => a.status === 'Cancelled').length,
    };
  }, [appointments, selectedDate]);

  const handleStatusChange = (id, status) => {
    updateAppointmentStatus(id, status);
    if (detailAppt?.id === id) setDetailAppt(prev => ({ ...prev, status }));
  };

  const handleSaveEdit = async (id, updates) => {
    await updateAppointment(id, updates);
  };

  const clearFilters = () => { setSearch(''); setStatusFilter('All'); setSelectedDate(''); };

  return (
    <Layout pageTitle="Appointments" pageSubtitle={`${filtered.length} Appointment${filtered.length !== 1 ? 's' : ''}`}>

      {/* Summary Strip */}
      <div style={{ display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(180px,1fr))',gap:14,marginBottom:20 }}>
        {[
          { label:'Total',value:dayCounts.total,color:'var(--clr-primary)' },
          { label:'Completed',value:dayCounts.completed,color:'#10b981' },
          { label:'Pending',value:dayCounts.pending,color:'#f59e0b' },
          { label:'Cancelled',value:dayCounts.cancelled,color:'#ef4444' },
        ].map(({label,value,color})=>(
          <div key={label} className="card" style={{ padding:'14px 18px',display:'flex',alignItems:'center',justifyContent:'space-between' }}>
            <div>
              <div style={{ fontSize:'0.68rem',color:'var(--clr-subtext)',fontWeight:700,textTransform:'uppercase',letterSpacing:'0.04em' }}>{label}</div>
              <div style={{ fontSize:'1.4rem',fontWeight:900,color:'var(--clr-text)' }}>{value}</div>
            </div>
            <div style={{ width:10,height:10,borderRadius:'50%',background:color,boxShadow:`0 0 8px ${color}40` }}/>
          </div>
        ))}
      </div>

      {/* Main Grid */}
      <div style={{ display:'grid',gridTemplateColumns:'260px 1fr',gap:20,alignItems:'start' }}>

        {/* Sidebar */}
        <div style={{ display:'flex',flexDirection:'column',gap:14 }}>
          <MiniCalendar selectedDate={selectedDate} onSelect={d=>setSelectedDate(prev=>prev===d?'':d)}/>
        </div>

        {/* Table Area */}
        <div className="card" style={{ padding:0,display:'flex',flexDirection:'column',overflow:'hidden' }}>

          {/* Controls */}
          <div style={{ padding:'16px 20px',borderBottom:'1px solid var(--clr-border)',display:'flex',flexWrap:'wrap',gap:12,alignItems:'center',justifyContent:'space-between' }}>
            <div style={{ position:'relative',flex:'1 1 220px',maxWidth:300 }}>
              <Search size={15} style={{ position:'absolute',left:12,top:'50%',transform:'translateY(-50%)',color:'var(--clr-text-light)' }}/>
              <input className="form-input" style={{ paddingLeft:36,width:'100%',margin:0 }}
                placeholder="Search patient, type, status..." value={search} onChange={e=>setSearch(e.target.value)}/>
              {search && <button onClick={()=>setSearch('')} style={{ position:'absolute',right:8,top:'50%',transform:'translateY(-50%)',background:'none',border:'none',cursor:'pointer',color:'var(--clr-text-light)',padding:2 }}><X size={14}/></button>}
            </div>
            <div style={{ display:'flex',alignItems:'center',gap:10,flexWrap:'wrap' }}>
              <div style={{ display:'flex',background:'var(--clr-bg)',padding:3,borderRadius:8,border:'1px solid var(--clr-border)' }}>
                {['All','Pending','Completed','Cancelled'].map(s=>(
                  <button key={s} onClick={()=>setStatusFilter(s)} style={{
                    padding:'5px 12px',border:'none',borderRadius:6,fontSize:'0.75rem',fontWeight:700,cursor:'pointer',
                    background:statusFilter===s?'var(--clr-card)':'transparent',
                    color:statusFilter===s?'var(--clr-text)':'var(--clr-subtext)',
                    boxShadow:statusFilter===s?'0 1px 2px rgba(0,0,0,0.06)':'none',transition:'all 0.15s',
                  }}>{s}</button>
                ))}
              </div>
              {(search || statusFilter!=='All' || selectedDate) && (
                <button onClick={clearFilters} style={{ padding:'5px 10px',border:'1px solid var(--clr-border)',borderRadius:6,background:'transparent',color:'var(--clr-subtext)',fontSize:'0.72rem',fontWeight:700,cursor:'pointer',display:'flex',alignItems:'center',gap:4 }}>
                  <X size={12}/> Clear
                </button>
              )}
              {['doctor','receptionist'].includes(user?.role?.toLowerCase()) && (
                <button className="btn btn-primary btn-sm" onClick={()=>setShowAdd(true)} style={{ display:'flex',alignItems:'center',gap:6 }}>
                  <Plus size={14}/> New
                </button>
              )}
            </div>
          </div>

          {/* Date indicator */}
          {selectedDate && (
            <div style={{ padding:'8px 20px',background:'var(--clr-bg)',borderBottom:'1px solid var(--clr-border)',display:'flex',alignItems:'center',justifyContent:'space-between' }}>
              <div style={{ fontSize:'0.8rem',color:'var(--clr-primary)',fontWeight:700,display:'flex',alignItems:'center',gap:6 }}>
                <Calendar size={13}/> {new Date(selectedDate+'T00:00:00').toLocaleDateString('en-US',{weekday:'long',month:'long',day:'numeric',year:'numeric'})}
                <span style={{ fontSize:'0.72rem',color:'var(--clr-subtext)',fontWeight:600 }}>• {filtered.length} appointment{filtered.length!==1?'s':''}</span>
              </div>
              <button onClick={()=>setSelectedDate('')} style={{ background:'none',border:'none',cursor:'pointer',color:'var(--clr-text-light)',fontSize:'0.72rem',display:'flex',alignItems:'center',gap:4 }}>
                <X size={12}/> All dates
              </button>
            </div>
          )}

          {/* Table */}
          <div style={{ overflowX:'auto' }}>
            <table style={{ width:'100%',borderCollapse:'collapse' }}>
              <thead>
                <tr style={{ borderBottom:'2px solid var(--clr-border)' }}>
                  {['ID','Patient','Doctor','Visit Reason','Date & Time','Status','Actions'].map(h=>(
                    <th key={h} style={{ padding:'12px 16px',fontSize:'0.68rem',color:'var(--clr-subtext)',textTransform:'uppercase',letterSpacing:'0.05em',fontWeight:700,textAlign:'left' }}>{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {filtered.map(a => (
                  <tr key={a.id} style={{ borderBottom:'1px solid var(--clr-border)',cursor:'pointer',transition:'background 0.1s' }}
                    onMouseEnter={e=>e.currentTarget.style.background='var(--clr-bg)'}
                    onMouseLeave={e=>e.currentTarget.style.background='transparent'}
                    onClick={()=>setDetailAppt(a)}>
                    <td style={{ padding:'12px 16px',color:'var(--clr-subtext)',fontSize:'0.82rem',fontFamily:'monospace' }}>{a.displayId || '—'}</td>
                    <td style={{ padding:'12px 16px' }}>
                      <div style={{ display:'flex',alignItems:'center',gap:10 }}>
                        <div className="avatar" style={{ width:30,height:30,fontSize:'0.65rem' }}>
                          {(a.patient||'U').split(' ').map(n=>n[0]).join('').toUpperCase().slice(0,2)}
                        </div>
                        <span style={{ fontWeight:700,fontSize:'0.86rem',color:'var(--clr-text)' }}>{a.patient}</span>
                      </div>
                    </td>
                    <td style={{ padding:'12px 16px',color:'var(--clr-subtext)',fontSize:'0.84rem' }}>{a.doctor}</td>
                    <td style={{ padding:'12px 16px' }}><span className="badge badge-primary" style={{ fontWeight:700,fontSize:'0.72rem',background:'var(--clr-primary-light)',color:'var(--clr-primary-dark)',border:'1px solid rgba(16,185,129,0.15)' }}>{a.condition || 'Routine Checkup'}</span></td>
                    <td style={{ padding:'12px 16px' }}>
                      <div style={{ display:'flex',flexDirection:'column',gap:2 }}>
                        <span style={{ display:'flex',alignItems:'center',gap:5,fontSize:'0.82rem',color:'var(--clr-text)',fontWeight:600 }}><Calendar size={12} color="var(--clr-text-light)"/> {a.date}</span>
                        <span style={{ display:'flex',alignItems:'center',gap:5,fontSize:'0.76rem',color:'var(--clr-subtext)' }}><Clock size={12}/> {a.time}</span>
                      </div>
                    </td>
                    <td style={{ padding:'12px 16px' }}><span className={STATUS_CLASS[a.status]||'badge'} style={{ fontSize:'0.72rem',fontWeight:700 }}>{a.status}</span></td>
                    <td style={{ padding:'12px 16px' }} onClick={e=>e.stopPropagation()}>
                      <div style={{ display:'flex',gap:6 }}>
                        <button title="View" onClick={()=>setDetailAppt(a)} style={{ width:30,height:30,borderRadius:6,border:'1px solid var(--clr-border)',background:'transparent',cursor:'pointer',display:'grid',placeItems:'center',color:'var(--clr-subtext)' }}><Eye size={14}/></button>
                        <button title="Edit" onClick={()=>setEditAppt(a)} style={{ width:30,height:30,borderRadius:6,border:'1px solid var(--clr-border)',background:'transparent',cursor:'pointer',display:'grid',placeItems:'center',color:'var(--clr-subtext)' }}><Edit3 size={14}/></button>
                      </div>
                    </td>
                  </tr>
                ))}
                {filtered.length === 0 && (
                  <tr><td colSpan={7} style={{ textAlign:'center',padding:'48px 20px',color:'var(--clr-subtext)' }}>
                    <Calendar size={36} style={{ margin:'0 auto 12px',opacity:0.15,display:'block' }}/>
                    <p style={{ fontSize:'0.95rem',fontWeight:700,margin:0,color:'var(--clr-text)' }}>No appointments found</p>
                    <p style={{ fontSize:'0.82rem',marginTop:4 }}>Try adjusting your filters or select a different date</p>
                  </td></tr>
                )}
              </tbody>
            </table>
          </div>
        </div>
      </div>

      {/* Modals */}
      {showAdd && <AddModal onClose={()=>setShowAdd(false)}/>}
      {detailAppt && <DetailModal appointment={detailAppt} patients={patients} onClose={()=>setDetailAppt(null)} onEdit={a=>{setDetailAppt(null);setEditAppt(a);}} onStatusChange={handleStatusChange}/>}
      {editAppt && <EditModal appointment={editAppt} patients={patients} doctors={doctors} onClose={()=>setEditAppt(null)} onSave={handleSaveEdit}/>}
    </Layout>
  );
}
