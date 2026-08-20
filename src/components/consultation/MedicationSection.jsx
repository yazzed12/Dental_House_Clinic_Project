import React, { useEffect, useMemo, useRef, useState } from 'react';
import { AlertCircle, CheckCircle2, Loader2, Pencil, Pill, Plus, Search, ShieldCheck, Trash2, X } from 'lucide-react';
import {
  createCustomMedication, getEffectiveMedicationPreset, searchMedications,
} from '../../services/medicationApi.js';

const EMPTY_CUSTOM = {
  brand_name: '', generic_name: '', strength: '', dosage_form: '', route: '',
  category: '', manufacturer: '',
};

export const createPrescriptionEditor = details => {
  const medication = details?.medication || details || {};
  const preset = details?.effectivePreset || {};
  return {
    medicationId: medication.id,
    clinicalPresetId: preset.clinicalPresetId || null,
    doctorPresetId: preset.doctorPresetId || null,
    brandName: medication.brandName || '', genericName: medication.genericName || '',
    strength: medication.strength || '', dosageForm: medication.dosageForm || '',
    route: medication.route || '', dose: preset.dose || '', frequency: preset.frequency || '',
    duration: preset.duration || '', instructions: preset.instructions || '',
    doctorNotes: preset.doctorNotes || '',
  };
};

export const prescriptionDraftItem = item => ({
  medicationId: item.medicationId,
  clinicalPresetId: item.clinicalPresetId || null,
  doctorPresetId: item.doctorPresetId || null,
  brandName: item.brandName || '', genericName: item.genericName || '',
  strength: item.strength || '', dosageForm: item.dosageForm || '', route: item.route || '',
  dose: item.dose || '', frequency: item.frequency || '', duration: item.duration || '',
  instructions: item.instructions || '', doctorNotes: item.doctorNotes || '',
});

export const updatePrescriptionItems = (items, editor, editingIndex = null) => {
  const next = items.map(prescriptionDraftItem);
  const value = prescriptionDraftItem(editor);
  if (editingIndex === null) next.push(value);
  else next[editingIndex] = value;
  return next;
};

export const removePrescriptionItem = (items, index) => items
  .filter((_, itemIndex) => itemIndex !== index)
  .map(prescriptionDraftItem);

const requiredEditorFields = ['brandName', 'strength', 'dosageForm', 'route', 'dose', 'frequency', 'duration'];

export default function MedicationSection({ workflow, disabled = false, sectionRef }) {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState([]);
  const [searching, setSearching] = useState(false);
  const [editor, setEditor] = useState(null);
  const [editingIndex, setEditingIndex] = useState(null);
  const [selectionLoading, setSelectionLoading] = useState(false);
  const [showCustom, setShowCustom] = useState(false);
  const [custom, setCustom] = useState(EMPTY_CUSTOM);
  const [customSaving, setCustomSaving] = useState(false);
  const [reviewConfirmed, setReviewConfirmed] = useState(false);
  const [actionError, setActionError] = useState('');
  const searchInput = useRef(null);
  const readOnly = disabled || workflow.prescription?.status === 'approved';
  const canAdd = editor && requiredEditorFields.every(field => editor[field]?.trim());

  useEffect(() => {
    let active = true;
    const normalized = query.trim();
    if (normalized.length < 2 || readOnly) return () => { active = false; };
    const timer = setTimeout(() => {
      setSearching(true);
      searchMedications(normalized)
        .then(data => { if (active) { setResults(Array.isArray(data) ? data : []); setActionError(''); } })
        .catch(error => { if (active) { setResults([]); setActionError(error.message || 'Medication search failed.'); } })
        .finally(() => { if (active) setSearching(false); });
    }, 300);
    return () => { active = false; clearTimeout(timer); };
  }, [query, readOnly]);

  const selectMedication = async medication => {
    setSelectionLoading(true); setActionError('');
    try {
      const details = await getEffectiveMedicationPreset(medication.id);
      setEditor(createPrescriptionEditor(details));
      setEditingIndex(null); setQuery(''); setResults([]);
    } catch (error) {
      setActionError(error.message || 'Medication details could not be loaded.');
    } finally { setSelectionLoading(false); }
  };

  const saveEditor = async () => {
    if (!canAdd || workflow.saving) return;
    const next = updatePrescriptionItems(workflow.items, editor, editingIndex);
    try {
      await workflow.saveItems(next);
      setReviewConfirmed(false);
      setEditor(null); setEditingIndex(null);
    } catch { /* usePrescription exposes the authoritative error below. */ }
  };

  const editItem = (item, index) => {
    setEditor(createPrescriptionEditor(item)); setEditingIndex(index);
  };

  const deleteItem = async index => {
    try {
      await workflow.saveItems(removePrescriptionItem(workflow.items, index));
      setReviewConfirmed(false);
      if (editingIndex === index) { setEditor(null); setEditingIndex(null); }
    } catch { /* usePrescription exposes the authoritative error below. */ }
  };

  const createCustom = async () => {
    setCustomSaving(true); setActionError('');
    try {
      const medication = await createCustomMedication(custom);
      setShowCustom(false); setCustom(EMPTY_CUSTOM);
      await selectMedication(medication);
    } catch (error) {
      setActionError(error.message || 'Custom medication could not be saved.');
    } finally { setCustomSaving(false); }
  };

  const approve = async () => {
    if (!reviewConfirmed) return;
    try {
      await workflow.approve();
      setEditor(null); setEditingIndex(null);
    } catch { /* usePrescription exposes the authoritative error below. */ }
  };

  const statusLabel = workflow.prescription?.status === 'approved' ? 'Approved · immutable'
    : workflow.items.length ? 'Draft · review required' : 'No prescription';
  const editorFields = useMemo(() => [
    ['brandName', 'Brand', true], ['genericName', 'Generic', false],
    ['strength', 'Strength', true], ['dosageForm', 'Dosage Form', true],
    ['route', 'Route', true], ['dose', 'Dose', true],
    ['frequency', 'Frequency', true], ['duration', 'Duration', true],
  ], []);

  return (
    <section ref={sectionRef} className="consultation-section" aria-label="Medication">
      <div className="consultation-mini-head" style={{ display: 'flex', justifyContent: 'space-between', gap: 10 }}>
        <div><p className="section-kicker">Consultation level</p><h4>Medication</h4></div>
        <span className={`badge ${workflow.prescription?.status === 'approved' ? 'badge-success' : ''}`}>{statusLabel}</span>
      </div>

      {!readOnly && (
        <div style={{ position: 'relative' }}>
          <Search size={15} style={{ position: 'absolute', left: 11, top: 13, color: 'var(--clr-subtext)' }} />
          <input ref={searchInput} className="form-input" value={query}
            onChange={event => { setQuery(event.target.value); setResults([]); setSearching(false); }} placeholder="Search medication by brand, generic, strength, form, or category"
            style={{ paddingLeft: 34 }} aria-label="Search medication" />
          {(searching || results.length > 0) && (
            <div style={{ position: 'absolute', zIndex: 120, top: '100%', left: 0, right: 0, marginTop: 5, background: 'white', border: '1px solid var(--clr-border)', borderRadius: 10, boxShadow: '0 12px 28px rgba(15,23,42,.15)', maxHeight: 240, overflow: 'auto' }}>
              {searching ? <div style={{ padding: 14, display: 'flex', gap: 8 }}><Loader2 size={15} className="animate-spin" /> Searching…</div>
                : results.map(result => <button type="button" key={result.id} onClick={() => selectMedication(result)}
                  style={{ display: 'block', width: '100%', border: 0, borderBottom: '1px solid var(--clr-border)', background: 'white', textAlign: 'left', padding: 11, cursor: 'pointer' }}>
                  <strong>{result.brandName}</strong> — {result.genericName || 'Generic not supplied'} — {result.strength} — {result.dosageForm} — {result.category || 'Uncategorized'}
                  <small style={{ display: 'block', marginTop: 3, color: 'var(--clr-subtext)' }}>{result.isCustom ? 'Clinic custom · unverified' : 'Verified catalog'}</small>
                </button>)}
            </div>
          )}
          <button type="button" className="btn btn-ghost btn-sm" onClick={() => setShowCustom(value => !value)} style={{ marginTop: 7 }}>
            <Plus size={14} /> Add custom medication
          </button>
        </div>
      )}

      {showCustom && !readOnly && (
        <div style={{ marginTop: 10, padding: 12, border: '1px solid var(--clr-border)', borderRadius: 10, background: 'var(--clr-bg)' }}>
          <strong>Clinic custom medication</strong>
          <p style={{ fontSize: '.74rem', color: 'var(--clr-subtext)' }}>Saved as clinic-only and unverified; it never becomes global catalog data.</p>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
            {[
              ['brand_name', 'Brand *'], ['generic_name', 'Generic'], ['strength', 'Strength *'],
              ['dosage_form', 'Dosage Form *'], ['route', 'Route *'], ['category', 'Category'],
              ['manufacturer', 'Manufacturer'],
            ].map(([field, label]) => <input key={field} className="form-input" aria-label={label}
              placeholder={label} value={custom[field]} onChange={event => setCustom(current => ({ ...current, [field]: event.target.value }))} />)}
          </div>
          <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8, marginTop: 9 }}>
            <button className="btn btn-secondary btn-sm" onClick={() => setShowCustom(false)}>Cancel</button>
            <button className="btn btn-primary btn-sm" onClick={createCustom} disabled={customSaving || !custom.brand_name.trim() || !custom.strength.trim() || !custom.dosage_form.trim() || !custom.route.trim()}>
              {customSaving ? <Loader2 size={14} className="animate-spin" /> : <Plus size={14} />} Save &amp; select
            </button>
          </div>
        </div>
      )}

      {(selectionLoading || editor) && !readOnly && (
        <div style={{ marginTop: 12, padding: 12, border: '1px solid var(--clr-primary)', borderRadius: 10 }}>
          {selectionLoading ? <div><Loader2 size={15} className="animate-spin" /> Loading preset…</div> : <>
            <div style={{ display: 'flex', justifyContent: 'space-between' }}><strong>{editingIndex === null ? 'Add prescription item' : 'Edit prescription item'}</strong><button className="icon-button" onClick={() => { setEditor(null); setEditingIndex(null); }}><X size={14}/></button></div>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8, marginTop: 9 }}>
              {editorFields.map(([field, label, required]) => <label key={field} style={{ fontSize: '.72rem', fontWeight: 700 }}>{label}{required ? ' *' : ''}<input className="form-input" value={editor[field]} onChange={event => setEditor(current => ({ ...current, [field]: event.target.value }))} /></label>)}
            </div>
            <label style={{ display: 'block', marginTop: 8, fontSize: '.72rem', fontWeight: 700 }}>Instructions<textarea className="consultation-textarea" value={editor.instructions} onChange={event => setEditor(current => ({ ...current, instructions: event.target.value }))} style={{ minHeight: 58 }} /></label>
            <label style={{ display: 'block', marginTop: 8, fontSize: '.72rem', fontWeight: 700 }}>Doctor Notes<textarea className="consultation-textarea" value={editor.doctorNotes} onChange={event => setEditor(current => ({ ...current, doctorNotes: event.target.value }))} style={{ minHeight: 50 }} /></label>
            <button className="btn btn-primary btn-sm" onClick={saveEditor} disabled={!canAdd || workflow.saving} style={{ marginTop: 9 }}>
              {workflow.saving ? <Loader2 size={14} className="animate-spin"/> : <Plus size={14}/>} {editingIndex === null ? 'Add to Prescription' : 'Save Item'}
            </button>
          </>}
        </div>
      )}

      <div style={{ marginTop: 14 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}><strong>Prescription Draft</strong><span className="badge">{workflow.items.length} item{workflow.items.length === 1 ? '' : 's'}</span></div>
        {workflow.loading ? <p><Loader2 size={14} className="animate-spin" /> Loading prescription…</p>
          : workflow.items.length === 0 ? <p style={{ fontSize: '.76rem', color: 'var(--clr-subtext)' }}>No medication prescribed for this consultation.</p>
            : <div style={{ display: 'grid', gap: 8, marginTop: 8 }}>{workflow.items.map((item, index) => <article key={item.id || `${item.medicationId}-${index}`} style={{ padding: 10, border: '1px solid var(--clr-border)', borderRadius: 9, background: 'white' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', gap: 8 }}><div><strong><Pill size={14} style={{ verticalAlign: -2 }} /> {item.brandName}</strong><small style={{ display: 'block', color: 'var(--clr-subtext)' }}>{item.genericName || 'Generic not supplied'} · {item.strength} · {item.dosageForm} · {item.route}</small></div>
                {!readOnly && <div style={{ display: 'flex', gap: 4 }}><button className="icon-button" aria-label={`Edit ${item.brandName}`} onClick={() => editItem(item, index)}><Pencil size={13}/></button><button className="icon-button" aria-label={`Delete ${item.brandName}`} onClick={() => deleteItem(index)}><Trash2 size={13}/></button></div>}</div>
              <div style={{ marginTop: 6, fontSize: '.75rem' }}><strong>Dose:</strong> {item.dose} · <strong>Frequency:</strong> {item.frequency} · <strong>Duration:</strong> {item.duration}</div>
              {item.instructions && <div style={{ marginTop: 3, fontSize: '.75rem' }}><strong>Instructions:</strong> {item.instructions}</div>}
            </article>)}</div>}
      </div>

      {workflow.reviewRequired && !readOnly && (
        <div style={{ marginTop: 12, padding: 12, border: '1px solid #f59e0b', borderRadius: 10, background: '#fffbeb' }}>
          <strong>Review Full Prescription</strong>
          <label style={{ display: 'flex', gap: 8, alignItems: 'flex-start', marginTop: 8, fontSize: '.78rem' }}>
            <input type="checkbox" checked={reviewConfirmed} onChange={event => setReviewConfirmed(event.target.checked)} />
            I reviewed every medication, strength, route, dose, frequency, duration, and instruction.
          </label>
          <button className="btn btn-primary btn-sm" onClick={approve} disabled={!reviewConfirmed || workflow.saving} style={{ marginTop: 9 }}>
            {workflow.saving ? <Loader2 size={14} className="animate-spin"/> : <ShieldCheck size={14}/>} Approve Prescription
          </button>
        </div>
      )}
      {workflow.prescription?.status === 'approved' && <div style={{ marginTop: 10, display: 'flex', gap: 7, alignItems: 'center', color: 'var(--clr-success)', fontSize: '.78rem', fontWeight: 700 }}><CheckCircle2 size={15}/> Doctor-approved prescription snapshot is locked.</div>}
      {(workflow.error || actionError) && <div style={{ marginTop: 9, color: 'var(--clr-danger)', display: 'flex', gap: 6, fontSize: '.76rem' }}><AlertCircle size={14}/>{workflow.error || actionError}</div>}
    </section>
  );
}
