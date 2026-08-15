import { useEffect, useMemo, useState } from 'react';
import { AlertCircle, Check, Loader2, Minus, Plus, Search, Trash2, X } from 'lucide-react';
import { decimalToCents, formatMoney } from '../config/money.js';
import { listLabProducts, listLabs } from '../services/labApi.js';

export default function LabProductSelector({ items, labNote, loading: loadingSaved, saving, error, onAdd, onQuantity, onRemove, onNote, onSave, onClose }) {
  const [labs, setLabs] = useState([]);
  const [selectedLabId, setSelectedLabId] = useState('');
  const [productsByLab, setProductsByLab] = useState({});
  const [search, setSearch] = useState('');
  const [loadingLabs, setLoadingLabs] = useState(true);
  const [loadingProducts, setLoadingProducts] = useState(false);
  const [catalogError, setCatalogError] = useState('');

  useEffect(() => {
    let active = true;
    listLabs(false).then(result => {
      if (!active) return;
      setLabs(result);
      setSelectedLabId(current => current || result[0]?.id || '');
    }).catch(reason => { if (active) setCatalogError(reason.message); })
      .finally(() => { if (active) setLoadingLabs(false); });
    return () => { active = false; };
  }, []);

  useEffect(() => {
    if (!selectedLabId || productsByLab[selectedLabId]) return undefined;
    let active = true;
    setLoadingProducts(true);
    setCatalogError('');
    listLabProducts(selectedLabId, false)
      .then(result => { if (active) setProductsByLab(current => ({ ...current, [selectedLabId]: result })); })
      .catch(reason => { if (active) setCatalogError(reason.message); })
      .finally(() => { if (active) setLoadingProducts(false); });
    return () => { active = false; };
  }, [selectedLabId, productsByLab]);

  const selectedLab = labs.find(lab => lab.id === selectedLabId);
  const products = productsByLab[selectedLabId] || [];
  const filtered = useMemo(() => products.filter(product => product.name.toLowerCase().includes(search.trim().toLowerCase())), [products, search]);
  const quantities = useMemo(() => Object.fromEntries(items.map(item => [item.labProductId, item.quantity])), [items]);

  return <div className="modal-overlay" role="dialog" aria-modal="true" aria-labelledby="lab-products-heading" onClick={() => !saving && onClose()} style={{ position: 'fixed', inset: 0, zIndex: 11000, display: 'grid', placeItems: 'center', padding: 20, background: 'rgba(15,23,42,.62)', backdropFilter: 'blur(4px)' }}><div className="card" onClick={event => event.stopPropagation()} style={{ width: 'min(860px, 100%)', maxHeight: '90vh', padding: 0, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
    <div style={{ padding: '20px 22px', borderBottom: '1px solid var(--clr-border)', display: 'flex', justifyContent: 'space-between' }}><div><h2 id="lab-products-heading" style={{ margin: 0 }}>Lab Products</h2><p style={{ margin: '3px 0 0', color: 'var(--clr-subtext)', fontSize: '.8rem' }}>Select products from one or more Labs for this consultation.</p></div><button type="button" aria-label="Close Lab Products" onClick={onClose} className="btn btn-secondary btn-sm"><X size={17} /></button></div>
    <div style={{ padding: '14px 18px', borderBottom: '1px solid var(--clr-border)' }}>
      {loadingLabs ? <Loader2 size={17} className="animate-spin" /> : labs.length === 0 ? <span style={{ color: 'var(--clr-subtext)' }}>No active labs available.</span> : <div role="tablist" aria-label="Labs" style={{ display: 'flex', gap: 8, overflowX: 'auto', paddingBottom: 2 }}>{labs.map(lab => <button key={lab.id} role="tab" aria-selected={lab.id === selectedLabId} className={`btn btn-sm ${lab.id === selectedLabId ? 'btn-primary' : 'btn-secondary'}`} onClick={() => { setSelectedLabId(lab.id); setSearch(''); }}>{lab.name}</button>)}</div>}
      <div style={{ position: 'relative', marginTop: 12 }}><Search size={17} style={{ position: 'absolute', left: 13, top: 13, color: 'var(--clr-subtext)' }} /><input autoFocus className="form-input" aria-label="Search Lab products" placeholder="Search Lab products..." value={search} onChange={event => setSearch(event.target.value)} style={{ paddingLeft: 40 }} /></div>
      {(catalogError || error) && <div role="alert" style={{ color: 'var(--clr-danger)', marginTop: 10, display: 'flex', gap: 7 }}><AlertCircle size={16} /> {catalogError || error}</div>}
    </div>
    <div style={{ overflowY: 'auto', minHeight: 220, padding: 12 }}>
      {loadingProducts || loadingSaved ? <div style={{ padding: 50, textAlign: 'center' }}><Loader2 className="animate-spin" /></div> : selectedLab && filtered.length === 0 ? <div style={{ padding: 45, textAlign: 'center', color: 'var(--clr-subtext)' }}>{products.length ? 'No Lab products match your search.' : 'No active products for this lab.'}</div> : filtered.map(product => { const qty = quantities[product.id] || 0; return <div key={product.id} style={{ display: 'grid', gridTemplateColumns: 'minmax(0,1fr) auto', gap: 14, alignItems: 'center', padding: 13, borderBottom: '1px solid var(--clr-border)', background: qty ? 'var(--clr-primary-light)' : 'transparent' }}><button onClick={() => onAdd(selectedLab, product)} style={{ border: 0, background: 'transparent', textAlign: 'left', cursor: 'pointer', color: 'inherit' }}><strong>{product.name}</strong><small style={{ display: 'block', color: 'var(--clr-subtext)' }}>{formatMoney(decimalToCents(product.currentPrice))} current price</small></button><button className="btn btn-secondary btn-sm" onClick={() => onAdd(selectedLab, product)}><Plus size={14} /> {qty ? 'Add one' : 'Add'}</button></div>; })}
      {items.length > 0 && <div style={{ marginTop: 14, borderTop: '1px solid var(--clr-border)', paddingTop: 12 }}><strong style={{ display: 'block', margin: '0 8px 8px' }}>Selected Lab Items</strong>{items.map(item => <div key={item.labProductId} style={{ display: 'grid', gridTemplateColumns: 'minmax(0,1fr) auto auto', alignItems: 'center', gap: 8, padding: 8 }}><span><strong>{item.productName}</strong><small style={{ display: 'block', color: 'var(--clr-subtext)' }}>{item.labName}</small></span><div style={{ display: 'flex', alignItems: 'center', gap: 6 }}><button aria-label={`Decrease ${item.productName}`} className="btn btn-secondary btn-sm" onClick={() => item.quantity === 1 ? onRemove(item.labProductId) : onQuantity(item.labProductId, item.quantity - 1)}><Minus size={13} /></button><input aria-label={`Quantity for ${item.productName}`} className="form-input" type="number" min="1" max="999" value={item.quantity} onChange={event => onQuantity(item.labProductId, event.target.value)} style={{ width: 70, padding: '6px 8px', textAlign: 'center' }} /><button aria-label={`Increase ${item.productName}`} className="btn btn-secondary btn-sm" disabled={item.quantity >= 999} onClick={() => onQuantity(item.labProductId, item.quantity + 1)}><Plus size={13} /></button></div><button aria-label={`Remove ${item.productName}`} className="btn btn-secondary btn-sm" onClick={() => onRemove(item.labProductId)}><Trash2 size={14} /></button></div>)}</div>}
      <div style={{ margin: '16px 8px 4px' }}><label className="form-label" htmlFor="consultation-lab-note">Lab Note</label><textarea id="consultation-lab-note" className="form-input" rows="3" maxLength="4000" value={labNote} onChange={event => onNote(event.target.value)} placeholder="Shade, urgency, or delivery instructions for all Lab items..." style={{ resize: 'vertical' }} /><small style={{ display: 'block', textAlign: 'right', color: 'var(--clr-subtext)' }}>{labNote.length}/4000</small></div>
    </div>
    <div style={{ padding: '14px 22px', borderTop: '1px solid var(--clr-border)', display: 'flex', justifyContent: 'flex-end', gap: 10 }}><button type="button" className="btn btn-secondary" onClick={onClose} disabled={saving}>Close</button><button type="button" className="btn btn-primary" onClick={onSave} disabled={saving || loadingSaved}>{saving ? <Loader2 size={15} className="animate-spin" /> : <Check size={15} />} Save Lab Items</button></div>
  </div></div>;
}
