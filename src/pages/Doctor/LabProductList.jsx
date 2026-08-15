import { useEffect, useMemo, useState } from 'react';
import { AlertCircle, Archive, CheckCircle2, Edit3, Loader2, Package, Plus, Search, X } from 'lucide-react';
import Layout from '../../components/Layout';
import { centsToDecimal, decimalToCents, formatMoney } from '../../config/money';
import {
  archiveLab, archiveLabProduct, createLab, createLabProduct,
  listLabProducts, listLabs, updateLabProductPrice,
} from '../../services/labApi.js';
import { chooseLabAfterRefresh, filterLabProducts } from '../../services/labView.js';

const emptyLabDraft = { name: '' };
const emptyProductDraft = { name: '', price: '' };

export default function LabProductList() {
  const [labs, setLabs] = useState([]);
  const [selectedLabId, setSelectedLabId] = useState(null);
  const [showArchived, setShowArchived] = useState(false);
  const [products, setProducts] = useState([]);
  const [search, setSearch] = useState('');
  const [labsLoading, setLabsLoading] = useState(true);
  const [productsLoading, setProductsLoading] = useState(false);
  const [error, setError] = useState('');
  const [toast, setToast] = useState('');
  const [modal, setModal] = useState(null);
  const [labDraft, setLabDraft] = useState(emptyLabDraft);
  const [productDraft, setProductDraft] = useState(emptyProductDraft);
  const [saving, setSaving] = useState(false);

  const selectedLab = labs.find(lab => lab.id === selectedLabId) || null;
  const filteredProducts = useMemo(
    () => filterLabProducts(products, search),
    [products, search],
  );

  const refreshLabs = async preferredLabId => {
    const rows = await listLabs(showArchived);
    setLabs(rows);
    setSelectedLabId(current => chooseLabAfterRefresh(rows, current, preferredLabId));
    return rows;
  };

  useEffect(() => {
    let active = true;
    setLabsLoading(true);
    setError('');
    listLabs(showArchived)
      .then(rows => {
        if (!active) return;
        setLabs(rows);
        setSelectedLabId(current => chooseLabAfterRefresh(rows, current));
      })
      .catch(err => { if (active) setError(err.message); })
      .finally(() => { if (active) setLabsLoading(false); });
    return () => { active = false; };
  }, [showArchived]);

  useEffect(() => {
    let active = true;
    setProducts([]);
    setSearch('');
    if (!selectedLabId) return () => { active = false; };
    setProductsLoading(true);
    setError('');
    listLabProducts(selectedLabId, showArchived)
      .then(rows => { if (active) setProducts(rows); })
      .catch(err => { if (active) setError(err.message); })
      .finally(() => { if (active) setProductsLoading(false); });
    return () => { active = false; };
  }, [selectedLabId, showArchived]);

  const refreshProducts = async () => {
    if (!selectedLabId) return;
    setProducts(await listLabProducts(selectedLabId, showArchived));
  };

  const openAddLab = () => {
    setLabDraft(emptyLabDraft); setError(''); setModal({ type: 'lab' });
  };
  const openAddProduct = () => {
    if (!selectedLab?.isActive) return;
    setProductDraft(emptyProductDraft); setError(''); setModal({ type: 'product' });
  };
  const openEditPrice = product => {
    if (!selectedLab?.isActive || !product.isActive) return;
    const cents = decimalToCents(product.currentPrice);
    setProductDraft({ name: product.name, price: cents === null ? String(product.currentPrice) : centsToDecimal(cents) });
    setError(''); setModal({ type: 'price', product });
  };

  const saveLab = async event => {
    event.preventDefault();
    const name = labDraft.name.trim();
    if (!name) { setError('Lab name is required.'); return; }
    setSaving(true); setError('');
    try {
      const created = await createLab(name);
      await refreshLabs(created.id);
      setModal(null); setToast('Lab added.');
    } catch (err) { setError(err.message); }
    finally { setSaving(false); }
  };

  const saveProduct = async event => {
    event.preventDefault();
    const cents = decimalToCents(productDraft.price);
    if (!productDraft.name.trim() || cents === null) {
      setError('Enter a product name and a non-negative price with at most two decimals.'); return;
    }
    setSaving(true); setError('');
    try {
      await createLabProduct(selectedLab.id, productDraft.name.trim(), centsToDecimal(cents));
      await refreshProducts(); setModal(null); setToast('Product added.');
    } catch (err) { setError(err.message); }
    finally { setSaving(false); }
  };

  const savePrice = async event => {
    event.preventDefault();
    const cents = decimalToCents(productDraft.price);
    if (cents === null) { setError('Enter a non-negative price with at most two decimals.'); return; }
    setSaving(true); setError('');
    try {
      await updateLabProductPrice(modal.product.id, centsToDecimal(cents));
      await refreshProducts(); setModal(null); setToast('Product price updated.');
    } catch (err) { setError(err.message); }
    finally { setSaving(false); }
  };

  const handleArchiveLab = async () => {
    if (!selectedLab?.isActive || saving || !window.confirm(`Archive ${selectedLab.name}?`)) return;
    setSaving(true); setError('');
    try {
      await archiveLab(selectedLab.id);
      const rows = await listLabs(showArchived);
      setLabs(rows);
      setSelectedLabId(chooseLabAfterRefresh(rows, null));
      setToast('Lab archived.');
    } catch (err) { setError(err.message); }
    finally { setSaving(false); }
  };

  const handleArchiveProduct = async product => {
    if (!selectedLab?.isActive || !product.isActive || saving || !window.confirm(`Archive ${product.name}?`)) return;
    setSaving(true); setError('');
    try {
      await archiveLabProduct(product.id);
      await refreshProducts(); setToast('Product archived.');
    } catch (err) { setError(err.message); }
    finally { setSaving(false); }
  };

  return <Layout pageTitle="Lab Product List" pageSubtitle="Manage shared labs and their current product prices.">
    <div className="page-stack animate-fadeIn">
      <div className="card" style={{ padding: 20 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 14, flexWrap: 'wrap' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <label style={{ display: 'inline-flex', alignItems: 'center', gap: 8, fontSize: '.85rem', fontWeight: 700 }}>
              <input type="checkbox" checked={showArchived} onChange={event => setShowArchived(event.target.checked)} />
              Show Archived
            </label>
          </div>
          <button className="btn btn-primary" onClick={openAddLab} disabled={saving}><Plus size={16} /> Add Lab</button>
        </div>
        {toast && <div role="status" style={{ marginTop: 14, color: 'var(--clr-success)', display: 'flex', gap: 8 }}><CheckCircle2 size={17} /> {toast}</div>}
        {error && <div role="alert" style={{ marginTop: 14, color: 'var(--clr-danger)', display: 'flex', gap: 8 }}><AlertCircle size={17} /> {error}</div>}
      </div>

      {labsLoading ? <div className="card" style={{ padding: 60, textAlign: 'center' }}><Loader2 className="animate-spin" /></div> : labs.length === 0 ?
        <div className="card" style={{ padding: 64, textAlign: 'center' }}><Package size={34} style={{ opacity: .25 }} /><h3>No labs added yet.</h3><button className="btn btn-primary" onClick={openAddLab}><Plus size={16} /> Add Lab</button></div> : <>
          <div className="card" style={{ padding: 10, overflowX: 'auto' }}>
            <div role="tablist" aria-label="Labs" style={{ display: 'flex', gap: 7, width: 'max-content', minWidth: '100%' }}>
              {labs.map(lab => <button key={lab.id} role="tab" aria-selected={lab.id === selectedLabId} onClick={() => setSelectedLabId(lab.id)}
                style={{ border: lab.id === selectedLabId ? '1px solid var(--clr-primary)' : '1px solid var(--clr-border)', background: lab.id === selectedLabId ? 'var(--clr-primary-light)' : 'var(--clr-card)', color: 'var(--clr-text)', borderRadius: 999, padding: '9px 15px', cursor: 'pointer', whiteSpace: 'nowrap', fontWeight: lab.id === selectedLabId ? 800 : 600, transition: 'all .18s ease', opacity: lab.isActive ? 1 : .65 }}>
                {lab.name} {!lab.isActive && <span className="badge" style={{ marginLeft: 7 }}>Archived</span>}
              </button>)}
            </div>
          </div>

          {selectedLab && <div className="card" style={{ padding: 20 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', gap: 16, flexWrap: 'wrap', alignItems: 'center' }}>
              <div><h2 style={{ margin: 0 }}>{selectedLab.name}</h2><p style={{ margin: '4px 0 0', color: 'var(--clr-subtext)' }}>{selectedLab.isActive ? 'Current product catalog' : 'Archived lab · read-only'}</p></div>
              {selectedLab.isActive && <button className="btn btn-secondary btn-sm" onClick={handleArchiveLab} disabled={saving} style={{ color: 'var(--clr-danger)' }}><Archive size={14} /> Archive Lab</button>}
            </div>
            <div style={{ display: 'flex', justifyContent: 'space-between', gap: 14, flexWrap: 'wrap', marginTop: 22 }}>
              <div style={{ position: 'relative', flex: '1 1 280px', maxWidth: 460 }}><Search size={17} style={{ position: 'absolute', left: 13, top: 14, color: 'var(--clr-subtext)' }} /><input className="form-input" aria-label="Search lab products" placeholder="Search lab products..." value={search} onChange={event => setSearch(event.target.value)} style={{ paddingLeft: 40 }} /></div>
              <button className="btn btn-primary" onClick={openAddProduct} disabled={!selectedLab.isActive || saving}><Plus size={16} /> Add Product</button>
            </div>
          </div>}

          <div className="card" style={{ padding: 0, overflow: 'hidden' }}>
            {productsLoading ? <div style={{ padding: 60, textAlign: 'center' }}><Loader2 className="animate-spin" /></div> : filteredProducts.length === 0 ?
              <div style={{ padding: 60, textAlign: 'center', color: 'var(--clr-subtext)' }}>{products.length ? 'No matching lab products.' : 'No products added for this lab yet.'}</div> :
              <div style={{ overflowX: 'auto' }}><table className="clinic-table" style={{ width: '100%' }}><thead><tr><th>Product Name</th><th>Current Price</th><th>Status</th><th aria-label="Actions" /></tr></thead><tbody>{filteredProducts.map(product => <tr key={product.id} style={{ opacity: product.isActive ? 1 : .6 }}><td><strong>{product.name}</strong></td><td>{formatMoney(decimalToCents(product.currentPrice))}</td><td><span className={`badge ${product.isActive ? 'badge-success' : ''}`}>{product.isActive ? 'Active' : 'Archived'}</span></td><td><div className="row-actions" style={{ justifyContent: 'flex-end' }}>{selectedLab?.isActive && product.isActive && <><button className="btn btn-secondary btn-sm" onClick={() => openEditPrice(product)}><Edit3 size={14} /> Edit Price</button><button className="btn btn-secondary btn-sm" onClick={() => handleArchiveProduct(product)} disabled={saving} style={{ color: 'var(--clr-danger)' }}><Archive size={14} /> Archive</button></>}</div></td></tr>)}</tbody></table></div>}
          </div>
        </>}
    </div>

    {modal?.type === 'lab' && <Dialog title="Add Lab" error={error} onClose={() => !saving && setModal(null)}><form onSubmit={saveLab}><div className="form-group"><label className="form-label">Lab Name</label><input autoFocus className="form-input" value={labDraft.name} onChange={event => setLabDraft({ name: event.target.value })} maxLength={200} required /></div><DialogActions saving={saving} onCancel={() => setModal(null)} /></form></Dialog>}
    {modal?.type === 'product' && <Dialog title="Add Product" error={error} onClose={() => !saving && setModal(null)}><form onSubmit={saveProduct}><div className="form-group"><label className="form-label">Product Name</label><input autoFocus className="form-input" value={productDraft.name} onChange={event => setProductDraft({ ...productDraft, name: event.target.value })} maxLength={200} required /></div><div className="form-group"><label className="form-label">Current Price (EGP)</label><input className="form-input" inputMode="decimal" value={productDraft.price} onChange={event => setProductDraft({ ...productDraft, price: event.target.value })} placeholder="0.00" required /></div><DialogActions saving={saving} onCancel={() => setModal(null)} /></form></Dialog>}
    {modal?.type === 'price' && <Dialog title="Edit Product Price" error={error} onClose={() => !saving && setModal(null)}><form onSubmit={savePrice}><p><strong>Product:</strong> {modal.product.name}</p><p style={{ color: 'var(--clr-subtext)', fontSize: '.84rem' }}>Changing this price affects new selections only. Old consultation transactions keep their saved price.</p><div className="form-group"><label className="form-label">New Price (EGP)</label><input autoFocus className="form-input" inputMode="decimal" value={productDraft.price} onChange={event => setProductDraft({ ...productDraft, price: event.target.value })} required /></div><DialogActions saving={saving} onCancel={() => setModal(null)} /></form></Dialog>}
  </Layout>;
}

function Dialog({ title, error, onClose, children }) {
  return <div className="modal-overlay" onClick={onClose} style={{ position: 'fixed', inset: 0, zIndex: 10000, display: 'grid', placeItems: 'center', padding: 20, background: 'rgba(15,23,42,.55)' }}><div className="card" role="dialog" aria-modal="true" aria-label={title} onClick={event => event.stopPropagation()} style={{ width: '100%', maxWidth: 480, padding: 24 }}><div style={{ display: 'flex', justifyContent: 'space-between', gap: 12 }}><h2 style={{ marginTop: 0 }}>{title}</h2><button className="icon-btn" aria-label="Close" onClick={onClose}><X size={17} /></button></div>{error && <div role="alert" style={{ marginBottom: 14, color: 'var(--clr-danger)', display: 'flex', gap: 8 }}><AlertCircle size={17} /> {error}</div>}{children}</div></div>;
}

function DialogActions({ saving, onCancel }) {
  return <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 10 }}><button type="button" className="btn btn-secondary" onClick={onCancel} disabled={saving}>Cancel</button><button className="btn btn-primary" disabled={saving}>{saving && <Loader2 size={15} className="animate-spin" />} Save</button></div>;
}
