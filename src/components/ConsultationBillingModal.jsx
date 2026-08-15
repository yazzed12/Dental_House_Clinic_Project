import React, { useState } from 'react';
import { X } from 'lucide-react';
import { BillingCard, PaymentDialog } from '../pages/Billing';

export default function ConsultationBillingModal({ billing, onClose, onUpdated }) {
  const [card, setCard] = useState(billing);
  const [dialog, setDialog] = useState(null);
  const saved = updated => {
    setCard(updated);
    setDialog(null);
    onUpdated?.(updated);
  };
  return <div className="modal-overlay" onClick={onClose} style={{ position:'fixed',inset:0,zIndex:99999,display:'flex',alignItems:'center',justifyContent:'center',padding:20,background:'rgba(15,23,42,.55)',backdropFilter:'blur(3px)' }}>
    <div onClick={event=>event.stopPropagation()} style={{ width:'min(820px,100%)',maxHeight:'90vh',overflow:'auto' }}>
      <div style={{ display:'flex',justifyContent:'flex-end',marginBottom:8 }}><button className="btn btn-secondary btn-sm" onClick={onClose}><X size={15}/> Close</button></div>
      <BillingCard card={card} onAdd={()=>setDialog({type:'add',card})} onCorrect={payment=>setDialog({type:'correct',card,payment})}/>
    </div>
    {dialog&&<PaymentDialog dialog={dialog} onClose={()=>setDialog(null)} onSaved={saved}/>}
  </div>;
}
