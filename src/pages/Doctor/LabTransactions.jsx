import { useCallback, useEffect, useMemo, useState } from 'react';
import { AlertCircle, Edit3, ExternalLink, Loader2, Plus, ReceiptText, X } from 'lucide-react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import Layout from '../../components/Layout.jsx';
import { centsToDecimal, decimalToCents, formatMoney } from '../../config/money.js';
import { listLabs } from '../../services/labApi.js';
import {
  createLabPayment, correctLabPayment, getLabTransactionSummary,
  listLabPayments, listLabTransactions,
} from '../../services/labTransactionsApi.js';
import { currentLocalDateInput, labTransactionRange, LAB_TRANSACTION_FILTERS } from '../../services/labTransactionDates.js';

const money = value => formatMoney(decimalToCents(value) ?? 0);
const localDateTime = value => {
  const date = value ? new Date(value) : new Date();
  date.setMinutes(date.getMinutes() - date.getTimezoneOffset());
  return date.toISOString().slice(0, 16);
};
const labels = { daily: 'Daily', weekly: 'Weekly', monthly: 'Monthly', yearly: 'Yearly', custom: 'Custom' };

export default function LabTransactions() {
  const navigate = useNavigate();
  const [params, setParams] = useSearchParams();
  const initialFilter = LAB_TRANSACTION_FILTERS.includes(params.get('period')) ? params.get('period') : 'monthly';
  const [filter, setFilter] = useState(initialFilter);
  const [anchor, setAnchor] = useState(params.get('date') || currentLocalDateInput());
  const [customEnd, setCustomEnd] = useState(params.get('end') || currentLocalDateInput());
  const [labs, setLabs] = useState([]);
  const [selectedLabId, setSelectedLabId] = useState(params.get('labId'));
  const [labsState, setLabsState] = useState({ loading: true, error: '' });
  const [transactions, setTransactions] = useState([]);
  const [summary, setSummary] = useState(null);
  const [payments, setPayments] = useState([]);
  const [sectionState, setSectionState] = useState({ transactions: '', summary: '', payments: '' });
  const [loading, setLoading] = useState({ transactions: false, summary: false, payments: false });
  const [dialog, setDialog] = useState(null);
  const selectedLab = labs.find(lab => lab.id === selectedLabId) || null;
  const range = useMemo(() => labTransactionRange(filter, anchor, customEnd), [filter, anchor, customEnd]);

  useEffect(() => {
    let active = true;
    listLabs(true).then(rows => {
      if (!active) return;
      setLabs(rows);
      setSelectedLabId(current => rows.some(lab => lab.id === current) ? current : rows[0]?.id || null);
      setLabsState({ loading: false, error: '' });
    }).catch(error => { if (active) setLabsState({ loading: false, error: error.message }); });
    return () => { active = false; };
  }, []);

  useEffect(() => {
    const next = new URLSearchParams();
    if (selectedLabId) next.set('labId', selectedLabId);
    next.set('period', filter); next.set('date', anchor);
    if (filter === 'custom') next.set('end', customEnd);
    setParams(next, { replace: true });
  }, [selectedLabId, filter, anchor, customEnd, setParams]);

  const refreshSection = useCallback(async section => {
    if (!selectedLabId || !range) return;
    setLoading(state => ({ ...state, [section]: true }));
    setSectionState(state => ({ ...state, [section]: '' }));
    try {
      if (section === 'transactions') setTransactions(await listLabTransactions(selectedLabId, range.dateFrom, range.dateTo));
      if (section === 'summary') setSummary(await getLabTransactionSummary(selectedLabId, range.dateFrom, range.dateTo));
      if (section === 'payments') setPayments(await listLabPayments(selectedLabId, range.dateFrom, range.dateTo));
    } catch (error) { setSectionState(state => ({ ...state, [section]: error.message })); }
    finally { setLoading(state => ({ ...state, [section]: false })); }
  }, [selectedLabId, range]);

  useEffect(() => {
    if (!selectedLabId || !range) return;
    refreshSection('transactions'); refreshSection('summary'); refreshSection('payments');
  }, [selectedLabId, range?.dateFrom, range?.dateTo]); // eslint-disable-line react-hooks/exhaustive-deps

  return <Layout pageTitle="Lab Transactions" pageSubtitle="Review Lab purchases, payments, and balances by period.">
    <div className="page-stack animate-fadeIn">
      <div className="card" style={{ padding: 10, overflowX: 'auto' }}>
        {labsState.loading ? <div style={{ padding: 18 }}><Loader2 className="animate-spin" /></div> : labsState.error ?
          <InlineError message={labsState.error} /> : labs.length === 0 ? <div style={{ padding: 18 }}>No Labs available.</div> :
          <div role="tablist" aria-label="Labs" style={{ display: 'flex', gap: 7, width: 'max-content', minWidth: '100%' }}>
            {labs.map(lab => <button key={lab.id} role="tab" aria-selected={lab.id === selectedLabId} onClick={() => setSelectedLabId(lab.id)}
              style={{ border: lab.id === selectedLabId ? '1px solid var(--clr-primary)' : '1px solid var(--clr-border)', background: lab.id === selectedLabId ? 'var(--clr-primary-light)' : 'var(--clr-card)', borderRadius: 999, padding: '9px 15px', cursor: 'pointer', whiteSpace: 'nowrap', fontWeight: 700, opacity: lab.isActive ? 1 : .65 }}>
              {lab.name} {!lab.isActive && <span className="badge" style={{ marginLeft: 6 }}>Archived</span>}
            </button>)}
          </div>}
      </div>

      <div className="card" style={{ padding: 16, overflowX: 'auto' }}>
        <div role="tablist" aria-label="Date filters" style={{ display: 'flex', gap: 7, width: 'max-content' }}>
          {LAB_TRANSACTION_FILTERS.map(value => <button key={value} className={`btn btn-sm ${filter === value ? 'btn-primary' : 'btn-secondary'}`} onClick={() => setFilter(value)}>{labels[value]}</button>)}
        </div>
        <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap', marginTop: 14 }}>
          <label className="form-label">{filter === 'custom' ? 'Start date' : 'Period date'}<input className="form-input" type="date" value={anchor} onChange={event => setAnchor(event.target.value)} /></label>
          {filter === 'custom' && <label className="form-label">End date<input className="form-input" type="date" value={customEnd} onChange={event => setCustomEnd(event.target.value)} /></label>}
          {range && <div className="muted" style={{ alignSelf: 'end', paddingBottom: 11 }}>Showing {range.startInput} through {range.endInput}</div>}
          {!range && <div role="alert" style={{ color: 'var(--clr-danger)', alignSelf: 'end', paddingBottom: 11 }}>End date must be on or after start date.</div>}
        </div>
      </div>

      <Summary summary={summary} loading={loading.summary} error={sectionState.summary} />

      <section className="card" style={{ padding: 20 }} aria-labelledby="lab-transactions-heading">
        <h2 id="lab-transactions-heading" style={{ marginTop: 0 }}>Transactions</h2>
        {loading.transactions ? <Loading label="Loading Lab transactions…" /> : sectionState.transactions ? <InlineError message={sectionState.transactions} /> : !transactions.length ?
          <Empty text="No Lab transactions for this period." /> : transactions.map(transaction => <article key={transaction.consultationId} style={{ padding: '16px 0', borderBottom: '1px solid var(--clr-border)' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, flexWrap: 'wrap' }}>
              <div><strong>{transaction.labName}</strong><div className="muted" style={{ fontSize: '.78rem' }}>{new Date(transaction.transactionDate).toLocaleString()} · Consultation {transaction.consultationDisplayId || '—'}</div></div>
              <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}><strong>{money(transaction.transactionTotal)}</strong><button className="btn btn-secondary btn-sm" onClick={() => navigate(`/doctor/consultations-history?consultationId=${transaction.consultationId}`)}><ExternalLink size={13} /> View Consultation</button></div>
            </div>
            <div style={{ marginTop: 10 }}>{(transaction.items || []).map(item => <div key={item.labProductId} style={{ display: 'grid', gridTemplateColumns: 'minmax(0,1fr) auto', gap: 12, padding: '6px 0' }}><span>{item.productName}<small className="muted" style={{ display: 'block' }}>Qty {item.quantity} · Unit Price {money(item.unitPrice)}</small></span><strong>{money(item.totalAmount)}</strong></div>)}</div>
          </article>)}
      </section>

      <section className="card" style={{ padding: 20 }} aria-labelledby="lab-payments-heading">
        <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, flexWrap: 'wrap' }}><div><h2 id="lab-payments-heading" style={{ margin: 0 }}>Payments</h2>{selectedLab && !selectedLab.isActive && <small className="muted">Archived Lab · history is read-only</small>}</div><button className="btn btn-primary" disabled={!selectedLab?.isActive} onClick={() => setDialog({ type: 'add' })}><Plus size={15} /> Add Payment</button></div>
        {loading.payments ? <Loading label="Loading Lab payments…" /> : sectionState.payments ? <InlineError message={sectionState.payments} /> : !payments.length ? <Empty text="No Lab payments for this period." /> :
          <div style={{ marginTop: 14 }}>{payments.map(payment => <div key={payment.paymentId} style={{ display: 'flex', justifyContent: 'space-between', gap: 12, flexWrap: 'wrap', padding: '11px 0', borderBottom: '1px solid var(--clr-border)' }}><div><strong>{money(payment.amount)}</strong><div className="muted" style={{ fontSize: '.77rem' }}>{new Date(payment.paidAt).toLocaleString()} · Revision {payment.revision}{payment.corrected ? ' · Corrected' : ''}</div>{payment.note && <div style={{ whiteSpace: 'pre-wrap', marginTop: 4 }}>{payment.note}</div>}{payment.correctionReason && <small className="muted">Reason: {payment.correctionReason}</small>}</div><button className="btn btn-secondary btn-sm" onClick={() => setDialog({ type: 'correct', payment })}><Edit3 size={13} /> Correct Payment</button></div>)}</div>}
      </section>
      {dialog && selectedLab && <PaymentDialog dialog={dialog} lab={selectedLab} onClose={() => setDialog(null)} onSaved={async () => { setDialog(null); await Promise.all([refreshSection('payments'), refreshSection('summary')]); }} />}
    </div>
  </Layout>;
}

function Summary({ summary, loading, error }) {
  if (loading) return <div className="card"><Loading label="Loading Lab transaction summary…" /></div>;
  if (error) return <div className="card"><InlineError message={error} /></div>;
  const cards = [['Total Purchases', money(summary?.totalPurchases)], ['Total Paid', money(summary?.totalPaid)], ['Remaining Balance', money(summary?.remainingBalance)], ['Transactions', summary?.transactionCount ?? 0], ['Items', summary?.itemCount ?? 0]];
  return <section aria-label="Lab transaction summary" style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(150px,1fr))', gap: 12 }}>{cards.map(([label, value]) => <div className="card" key={label} style={{ padding: 16 }}><div className="muted" style={{ fontSize: '.75rem' }}>{label}</div><strong style={{ fontSize: '1.15rem' }}>{value}</strong></div>)}</section>;
}
function PaymentDialog({ dialog, lab, onClose, onSaved }) {
  const correcting = dialog.type === 'correct'; const payment = dialog.payment;
  const [amount, setAmount] = useState(correcting ? payment.amount : '');
  const [paidAt, setPaidAt] = useState(localDateTime(correcting ? payment.paidAt : null));
  const [note, setNote] = useState(correcting ? payment.note || '' : ''); const [reason, setReason] = useState('');
  const [saving, setSaving] = useState(false); const [error, setError] = useState('');
  const save = async event => { event.preventDefault(); if (saving) return; const cents = decimalToCents(amount);
    if (cents === null || cents <= 0 || !paidAt) { setError('Enter a positive amount and payment date.'); return; }
    if (correcting && !reason.trim()) { setError('Correction reason is required.'); return; }
    setSaving(true); setError(''); try { const values = { amount: centsToDecimal(cents), paidAt: new Date(paidAt).toISOString(), note: note.trim() || null };
      if (correcting) await correctLabPayment({ paymentId: payment.paymentId, expectedRevision: payment.revision, ...values, reason: reason.trim() });
      else await createLabPayment({ labId: lab.id, ...values }); await onSaved();
    } catch (err) { setError(err.message); } finally { setSaving(false); } };
  return <div className="modal-overlay" onClick={onClose} style={{ position: 'fixed', inset: 0, zIndex: 99999, display: 'grid', placeItems: 'center', background: 'rgba(15,23,42,.55)', padding: 16 }}><form className="card" onClick={event => event.stopPropagation()} onSubmit={save} style={{ width: 'min(460px,100%)', maxHeight: '90vh', overflowY: 'auto' }}><div style={{ display: 'flex', justifyContent: 'space-between' }}><div><h3 style={{ margin: 0 }}>{correcting ? 'Correct Payment' : 'Add Payment'}</h3>{correcting && <small className="muted">Creates a new revision; history is not overwritten.</small>}</div><button type="button" className="btn btn-secondary btn-sm" aria-label="Close" onClick={onClose}><X size={15} /></button></div><label className="form-label">Amount (EGP)<input className="form-input" inputMode="decimal" value={amount} onChange={event => setAmount(event.target.value)} /></label><label className="form-label">Paid At<input className="form-input" type="datetime-local" required value={paidAt} onChange={event => setPaidAt(event.target.value)} /></label><label className="form-label">Note<textarea className="form-input" value={note} onChange={event => setNote(event.target.value)} /></label>{correcting && <label className="form-label">Correction Reason<textarea className="form-input" required value={reason} onChange={event => setReason(event.target.value)} /></label>}{error && <InlineError message={error} />}<div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8, marginTop: 14 }}><button type="button" className="btn btn-secondary" onClick={onClose} disabled={saving}>Cancel</button><button type="submit" className="btn btn-primary" disabled={saving}>{saving ? 'Saving…' : correcting ? 'Create Correction' : 'Add Payment'}</button></div></form></div>;
}
const Loading = ({ label }) => <div role="status" style={{ padding: 28, textAlign: 'center' }}><Loader2 className="animate-spin" /> {label}</div>;
const InlineError = ({ message }) => <div role="alert" style={{ color: 'var(--clr-danger)', display: 'flex', gap: 7, padding: 10 }}><AlertCircle size={16} /> {message}</div>;
const Empty = ({ text }) => <div style={{ padding: 32, textAlign: 'center', color: 'var(--clr-subtext)' }}><ReceiptText size={25} style={{ opacity: .35 }} /><p>{text}</p></div>;
