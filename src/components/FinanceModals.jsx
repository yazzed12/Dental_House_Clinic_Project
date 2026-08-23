import React from 'react';
import { ExternalLink, X } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { decimalToCents, formatMoney } from '../config/money';

const money = value => formatMoney(decimalToCents(value) ?? 0);

function Shell({ title, onClose, children }) {
  return <div className="modal-overlay" onClick={onClose} style={{ position:'fixed',inset:0,zIndex:99999,display:'flex',alignItems:'center',justifyContent:'center',padding:20,background:'rgba(15,23,42,.55)',backdropFilter:'blur(3px)' }}>
    <div className="card" onClick={event=>event.stopPropagation()} style={{ width:'min(760px,100%)',maxHeight:'88vh',overflow:'auto',padding:22 }}>
      <div style={{ display:'flex',justifyContent:'space-between',alignItems:'center',marginBottom:18 }}><h2 style={{ margin:0,fontSize:'1.15rem' }}>{title}</h2><button className="btn btn-secondary btn-sm" onClick={onClose}><X size={15}/></button></div>
      {children}
    </div>
  </div>;
}

export function OutstandingBalanceModal({ data, onClose }) {
  return <Shell title="Outstanding Balance" onClose={onClose}>
    {!data?.items?.length ? <p className="muted">No outstanding balance.</p> : <div className="page-stack">
      {data.items.map((item,index)=><div key={`${item.consultationId}-${item.procedureId}-${index}`} style={{ padding:14,border:'1px solid var(--clr-border)',borderRadius:10 }}>
        <strong>{item.name}</strong><div className="muted" style={{ fontSize:'.76rem',marginTop:4 }}>Consultation {item.consultationDisplayId || '—'} · {item.consultationDate ? new Date(item.consultationDate).toLocaleDateString() : 'Date unavailable'}</div>
        <div style={{ color:'var(--clr-danger)',fontWeight:800,marginTop:7 }}>Remaining: {money(item.remaining)}</div>
      </div>)}
      <div style={{ display:'flex',justifyContent:'space-between',fontWeight:900,fontSize:'1rem',paddingTop:10,borderTop:'1px solid var(--clr-border)' }}><span>Total Outstanding</span><span style={{ color:'var(--clr-danger)' }}>{money(data.totalOutstanding)}</span></div>
    </div>}
  </Shell>;
}

export function FinancialHistoryModal({ data, onClose }) {
  const navigate = useNavigate();
  const balance = Number(data?.balance || 0);
  return <Shell title="Patient Financial History" onClose={onClose}>
    {!data ? <p className="muted">Loading financial history…</p> : <div className="page-stack">
      <div className="grid-3">
        <Summary label="Total Billed" value={data.billedTotal}/><Summary label="Total Paid" value={data.paidTotal}/>
        <Summary label={balance > 0 ? 'Paid Extra' : balance < 0 ? 'Outstanding' : 'Settled'} value={balance > 0 ? data.creditTotal : data.outstandingTotal} color={balance > 0 ? 'var(--clr-success)' : balance < 0 ? 'var(--clr-danger)' : 'var(--clr-subtext)'}/>
      </div>
      {!data.consultations.length ? <p className="muted" style={{ textAlign:'center',padding:30 }}>No financial activity yet.</p> : data.consultations.map(card=><div key={card.consultationId} style={{ padding:16,border:'1px solid var(--clr-border)',borderRadius:12 }}>
        <div style={{ display:'flex',justifyContent:'space-between',gap:12 }}><div><strong>Consultation {card.consultationDisplayId || '—'}</strong><div className="muted" style={{ fontSize:'.75rem' }}>{card.consultationDate ? new Date(card.consultationDate).toLocaleString() : ''}</div></div><button className="btn btn-secondary btn-sm" onClick={()=>navigate(`/doctor/consultations-history?consultationId=${card.consultationId}`)}><ExternalLink size={13}/> View Consultation</button></div>
        <div style={{ marginTop:12 }}>{card.procedures.map(item=><div key={item.id} style={{ display:'flex',justifyContent:'space-between',fontSize:'.82rem',padding:'4px 0' }}><span>{item.quantity} × {item.name}</span><strong>{money(item.lineTotal)}</strong></div>)}</div>
        <div style={{ marginTop:10,paddingTop:8,borderTop:'1px solid var(--clr-border)' }}>{card.payments.length ? card.payments.map(payment=><div key={payment.paymentId} style={{ display:'flex',justifyContent:'space-between',fontSize:'.78rem',padding:'3px 0' }}><span>{new Date(payment.paidAt).toLocaleString()} {payment.corrected ? '· Corrected' : ''}</span><strong>{money(payment.amount)}</strong></div>) : <span className="muted" style={{ fontSize:'.78rem' }}>No payments recorded.</span>}</div>
        <div style={{ display:'flex',justifyContent:'space-between',marginTop:10,fontWeight:800 }}><span>Billed {money(card.billedTotal)} · Paid {money(card.paidTotal)}</span><span style={{ color:Number(card.balance)>0?'var(--clr-success)':Number(card.balance)<0?'var(--clr-danger)':'var(--clr-subtext)' }}>{Number(card.balance)>0?`Paid Extra ${money(card.creditTotal)}`:Number(card.balance)<0?`Remaining ${money(card.outstandingTotal)}`:'Settled'}</span></div>
      </div>)}
    </div>}
  </Shell>;
}

function Summary({ label, value, color='var(--clr-text)' }) { return <div style={{ padding:14,border:'1px solid var(--clr-border)',borderRadius:10 }}><div className="muted" style={{ fontSize:'.72rem' }}>{label}</div><strong style={{ color,fontSize:'1.05rem' }}>{money(value)}</strong></div>; }
