import { useEffect, useMemo, useState } from 'react';
import { AlertCircle, Check, Loader2, Minus, Plus, Search, X } from 'lucide-react';
import { decimalToCents, formatMoney } from '../config/money';
import { getConsultationProcedures, listProcedures, saveConsultationProcedures } from '../services/financeApi';

export default function ProcedureSelector({ patientId, onClose, onSaved }) {
  const [catalog, setCatalog] = useState([]);
  const [quantities, setQuantities] = useState({});
  const [version, setVersion] = useState(0);
  const [search, setSearch] = useState('');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  useEffect(() => {
    Promise.all([listProcedures(true), getConsultationProcedures(patientId)]).then(([items, saved]) => {
      const activeIds = new Set(items.map(item => item.id));
      const savedById = new Map(saved.items.map(item => [item.procedureId, item]));
      const displayItems = items.map(item => {
        const previous = savedById.get(item.id);
        return previous ? { ...item, name: previous.name, price: previous.unitPrice } : item;
      });
      const historicalOnly = saved.items
        .filter(item => !activeIds.has(item.procedureId))
        .map(item => ({ id: item.procedureId, name: item.name, price: item.unitPrice, isActive: false }));
      setCatalog([...displayItems, ...historicalOnly]); setVersion(saved.version);
      setQuantities(Object.fromEntries(saved.items.map(item => [item.procedureId, item.quantity])));
    }).catch(err => setError(err.message)).finally(() => setLoading(false));
  }, [patientId]);
  const filtered = useMemo(() => catalog.filter(item => item.name.toLowerCase().includes(search.trim().toLowerCase())), [catalog, search]);
  const total = useMemo(() => catalog.reduce((sum, item) => sum + decimalToCents(item.price) * (quantities[item.id] || 0), 0), [catalog, quantities]);
  const setQty = (id, qty) => setQuantities(current => { const next = { ...current }; if (qty > 0) next[id] = Math.min(qty, 999); else delete next[id]; return next; });
  const save = async () => {
    setSaving(true); setError('');
    try {
      const result = await saveConsultationProcedures(patientId, { version, selections: Object.entries(quantities).map(([procedureId, quantity]) => ({ procedureId, quantity })) });
      onSaved(result); onClose();
    } catch (err) { setError(err.status === 409 ? 'This procedure list changed in another tab. Close and reopen to review the latest version.' : err.message); }
    finally { setSaving(false); }
  };
  return <div className="modal-overlay" onClick={() => !saving && onClose()} style={{ position: 'fixed', inset: 0, zIndex: 11000, display: 'grid', placeItems: 'center', padding: 20, background: 'rgba(15,23,42,.62)', backdropFilter: 'blur(4px)' }}><div className="card" onClick={event => event.stopPropagation()} style={{ width: 'min(820px, 100%)', maxHeight: '88vh', padding: 0, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
    <div style={{ padding: '20px 22px', borderBottom: '1px solid var(--clr-border)', display: 'flex', justifyContent: 'space-between' }}><div><h2 style={{ margin: 0 }}>Performed Procedures</h2><p style={{ margin: '3px 0 0', color: 'var(--clr-subtext)', fontSize: '.8rem' }}>Select procedures and record quantities for this consultation.</p></div><button aria-label="Close" onClick={onClose} className="btn btn-secondary btn-sm"><X size={17} /></button></div>
    <div style={{ padding: 18, borderBottom: '1px solid var(--clr-border)' }}><div style={{ position: 'relative' }}><Search size={17} style={{ position: 'absolute', left: 13, top: 13, color: 'var(--clr-subtext)' }} /><input autoFocus className="form-input" aria-label="Search procedures" placeholder="Search filling, extraction, crown..." value={search} onChange={event => setSearch(event.target.value)} style={{ paddingLeft: 40 }} /></div>{error && <div style={{ color: 'var(--clr-danger)', marginTop: 10, display: 'flex', gap: 7 }}><AlertCircle size={16} /> {error}</div>}</div>
    <div style={{ overflowY: 'auto', minHeight: 240, padding: 12 }}>{loading ? <div style={{ padding: 60, textAlign: 'center' }}><Loader2 className="animate-spin" /></div> : filtered.length === 0 ? <div style={{ padding: 60, textAlign: 'center', color: 'var(--clr-subtext)' }}>{catalog.length ? 'No procedures match your search.' : 'The active Price List is empty.'}</div> : filtered.map(item => { const qty = quantities[item.id] || 0; return <div key={item.id} style={{ display: 'grid', gridTemplateColumns: 'minmax(0,1fr) auto auto', gap: 16, alignItems: 'center', padding: 13, borderBottom: '1px solid var(--clr-border)', background: qty ? 'var(--clr-primary-light)' : 'transparent' }}><button onClick={() => setQty(item.id, qty ? 0 : 1)} disabled={!item.isActive && !qty} style={{ border: 0, background: 'transparent', textAlign: 'left', cursor: 'pointer', color: 'inherit', display: 'flex', gap: 10, alignItems: 'center' }}><span style={{ width: 23, height: 23, borderRadius: 6, border: `1px solid ${qty ? 'var(--clr-primary)' : 'var(--clr-border)'}`, background: qty ? 'var(--clr-primary)' : 'var(--clr-card)', color: 'white', display: 'grid', placeItems: 'center' }}>{qty ? <Check size={15} /> : null}</span><span><strong>{item.name}</strong><small style={{ display: 'block', color: 'var(--clr-subtext)' }}>{formatMoney(decimalToCents(item.price))} each{!item.isActive ? ' · no longer active' : ''}</small></span></button><div style={{ display: 'flex', alignItems: 'center', gap: 7 }}><button aria-label={`Decrease ${item.name}`} className="btn btn-secondary btn-sm" disabled={!qty} onClick={() => setQty(item.id, qty - 1)}><Minus size={13} /></button><strong style={{ minWidth: 24, textAlign: 'center' }}>{qty}</strong><button aria-label={`Increase ${item.name}`} className="btn btn-secondary btn-sm" disabled={!item.isActive && !qty} onClick={() => setQty(item.id, qty + 1)}><Plus size={13} /></button></div><strong style={{ minWidth: 100, textAlign: 'right' }}>{formatMoney(decimalToCents(item.price) * qty)}</strong></div>; })}</div>
    <div style={{ padding: '16px 22px', borderTop: '1px solid var(--clr-border)', display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 16 }}><div><small style={{ display: 'block', color: 'var(--clr-subtext)' }}>Total</small><strong style={{ fontSize: '1.35rem' }}>{formatMoney(total)}</strong></div><div style={{ display: 'flex', gap: 10 }}><button className="btn btn-secondary" onClick={onClose} disabled={saving}>Cancel</button><button className="btn btn-primary" onClick={save} disabled={saving || loading}>{saving ? <Loader2 size={15} className="animate-spin" /> : <Check size={15} />} Save Procedures</button></div></div>
  </div></div>;
}
