import { useEffect, useMemo, useState } from 'react';
import { AlertCircle, Edit3, Loader2, Plus, Search } from 'lucide-react';
import Layout from '../../components/Layout';
import { centsToDecimal, decimalToCents, formatMoney } from '../../config/money';
import { createProcedure, listProcedures, updateProcedure } from '../../services/financeApi';

const emptyDraft = { name: '', price: '' };

export default function PriceList() {
  const [procedures, setProcedures] = useState([]);
  const [search, setSearch] = useState('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [modal, setModal] = useState(null);
  const [draft, setDraft] = useState(emptyDraft);
  const [saving, setSaving] = useState(false);

  const load = async () => {
    setLoading(true); setError('');
    try { setProcedures(await listProcedures()); }
    catch (err) { setError(err.message); }
    finally { setLoading(false); }
  };
  useEffect(() => {
    let active = true;
    listProcedures()
      .then(items => { if (active) setProcedures(items); })
      .catch(err => { if (active) setError(err.message); })
      .finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, []);

  const filtered = useMemo(() => procedures.filter(item => item.name.toLowerCase().includes(search.trim().toLowerCase())), [procedures, search]);
  const openCreate = () => { setDraft(emptyDraft); setModal({ mode: 'create' }); };
  const openEdit = item => { setDraft({ name: item.name, price: centsToDecimal(decimalToCents(item.price)) }); setModal({ mode: 'edit', item }); };
  const save = async event => {
    event.preventDefault();
    const cents = decimalToCents(draft.price);
    if (!draft.name.trim() || cents === null) { setError('Enter a name and a non-negative price with at most two decimals.'); return; }
    setSaving(true); setError('');
    try {
      const payload = { name: draft.name.trim(), price: centsToDecimal(cents) };
      if (modal.mode === 'create') await createProcedure(payload);
      else await updateProcedure(modal.item.id, payload);
      setModal(null); await load();
    } catch (err) { setError(err.message); }
    finally { setSaving(false); }
  };
  const toggleActive = async item => {
    setError('');
    try { await updateProcedure(item.id, { is_active: !item.isActive }); await load(); }
    catch (err) { setError(err.message); }
  };

  return <Layout pageTitle="Price List" pageSubtitle="Manage the clinic's procedure catalog and current prices.">
    <div className="page-stack animate-fadeIn">
      <div className="card" style={{ padding: 20 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', gap: 16, flexWrap: 'wrap' }}>
          <div style={{ position: 'relative', flex: '1 1 280px', maxWidth: 460 }}>
            <Search size={17} style={{ position: 'absolute', left: 13, top: 14, color: 'var(--clr-subtext)' }} />
            <input className="form-input" aria-label="Search procedures" placeholder="Search procedures..." value={search} onChange={event => setSearch(event.target.value)} style={{ paddingLeft: 40 }} />
          </div>
          <button className="btn btn-primary" onClick={openCreate}><Plus size={16} /> Add Procedure</button>
        </div>
        {error && <div style={{ marginTop: 14, color: 'var(--clr-danger)', display: 'flex', gap: 8 }}><AlertCircle size={17} /> {error}</div>}
      </div>
      <div className="card" style={{ padding: 0, overflow: 'hidden' }}>
        {loading ? <div style={{ padding: 60, textAlign: 'center' }}><Loader2 className="animate-spin" /></div> : filtered.length === 0 ? <div style={{ padding: 60, textAlign: 'center', color: 'var(--clr-subtext)' }}>{procedures.length ? 'No procedures match your search.' : 'No procedures yet. Add the clinic’s first procedure.'}</div> :
          <div style={{ overflowX: 'auto' }}><table className="clinic-table" style={{ width: '100%' }}><thead><tr><th>Procedure</th><th>Price</th><th>Status</th><th aria-label="Actions" /></tr></thead><tbody>{filtered.map(item => <tr key={item.id} style={{ opacity: item.isActive ? 1 : .6 }}><td><strong>{item.name}</strong></td><td>{formatMoney(decimalToCents(item.price))}</td><td><span className={`badge ${item.isActive ? 'badge-success' : ''}`}>{item.isActive ? 'Active' : 'Inactive'}</span></td><td><div className="row-actions" style={{ justifyContent: 'flex-end' }}><button className="btn btn-secondary btn-sm" onClick={() => openEdit(item)}><Edit3 size={14} /> Edit</button><button className="btn btn-secondary btn-sm" onClick={() => toggleActive(item)}>{item.isActive ? 'Deactivate' : 'Reactivate'}</button></div></td></tr>)}</tbody></table></div>}
      </div>
    </div>
    {modal && <div className="modal-overlay" onClick={() => !saving && setModal(null)} style={{ position: 'fixed', inset: 0, zIndex: 10000, display: 'grid', placeItems: 'center', padding: 20, background: 'rgba(15,23,42,.55)' }}><form className="card" onSubmit={save} onClick={event => event.stopPropagation()} style={{ width: '100%', maxWidth: 500, padding: 24 }}><h2 style={{ marginTop: 0 }}>{modal.mode === 'create' ? 'Add Procedure' : 'Edit Procedure'}</h2><div className="form-group"><label className="form-label">Procedure name</label><input autoFocus className="form-input" value={draft.name} onChange={event => setDraft({ ...draft, name: event.target.value })} maxLength={200} required /></div><div className="form-group"><label className="form-label">Price (EGP)</label><input className="form-input" inputMode="decimal" value={draft.price} onChange={event => setDraft({ ...draft, price: event.target.value })} placeholder="0.00" required /></div><div style={{ display: 'flex', justifyContent: 'flex-end', gap: 10 }}><button type="button" className="btn btn-secondary" onClick={() => setModal(null)} disabled={saving}>Cancel</button><button className="btn btn-primary" disabled={saving}>{saving && <Loader2 size={15} className="animate-spin" />} Save</button></div></form></div>}
  </Layout>;
}
