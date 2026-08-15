import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { getConsultationLabItems, saveLabDraft } from '../services/labApi.js';

const clampQuantity = value => Math.max(1, Math.min(999, Number.parseInt(value, 10) || 1));
const savedItem = item => ({
  ...item,
  labProductId: item.labProductId,
  quantity: clampQuantity(item.quantity),
  displayPrice: item.unitPrice,
  totalAmount: item.totalAmount,
  isSavedSnapshot: true,
});

export function useConsultationLabs(consultationId, ensureConsultationInitialized) {
  const [items, setItems] = useState([]);
  const [labNote, setLabNoteState] = useState('');
  const [dirty, setDirty] = useState(false);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const stateRef = useRef({ items: [], labNote: '', dirty: false });
  const savePromiseRef = useRef(null);
  const revisionRef = useRef(0);
  const consultationRef = useRef(null);

  const commitState = useCallback((nextItems, nextNote, nextDirty) => {
    stateRef.current = { items: nextItems, labNote: nextNote, dirty: nextDirty };
    setItems(nextItems);
    setLabNoteState(nextNote);
    setDirty(nextDirty);
  }, []);

  useEffect(() => {
    if (!consultationId) return undefined;
    if (consultationRef.current !== consultationId) {
      const previousConsultationId = consultationRef.current;
      consultationRef.current = consultationId;
      if (previousConsultationId) {
        revisionRef.current = 0;
        commitState([], '', false);
      }
    }
    let active = true;
    setLoading(true);
    setError('');
    getConsultationLabItems(consultationId)
      .then(result => {
        if (!active || stateRef.current.dirty) return;
        commitState((result?.items || []).map(savedItem), result?.labNote || '', false);
      })
      .catch(reason => { if (active) setError(reason.message); })
      .finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, [consultationId, commitState]);

  const addProduct = useCallback((lab, product) => {
    revisionRef.current += 1;
    const current = stateRef.current;
    const existing = current.items.find(item => item.labProductId === product.id);
    const next = existing
      ? current.items.map(item => item.labProductId === product.id
        ? { ...item, quantity: clampQuantity(item.quantity + 1), isSavedSnapshot: false, displayPrice: product.currentPrice }
        : item)
      : [...current.items, {
        labProductId: product.id,
        labId: lab.id,
        labName: lab.name,
        productName: product.name,
        quantity: 1,
        displayPrice: product.currentPrice,
        isSavedSnapshot: false,
      }];
    commitState(next, current.labNote, true);
  }, [commitState]);

  const setQuantity = useCallback((labProductId, quantity) => {
    revisionRef.current += 1;
    const current = stateRef.current;
    const next = current.items.map(item => item.labProductId === labProductId
      ? { ...item, quantity: clampQuantity(quantity), isSavedSnapshot: false }
      : item);
    commitState(next, current.labNote, true);
  }, [commitState]);

  const removeItem = useCallback(labProductId => {
    revisionRef.current += 1;
    const current = stateRef.current;
    commitState(current.items.filter(item => item.labProductId !== labProductId), current.labNote, true);
  }, [commitState]);

  const setLabNote = useCallback(value => {
    revisionRef.current += 1;
    const current = stateRef.current;
    commitState(current.items, value.slice(0, 4000), true);
  }, [commitState]);

  const save = useCallback(() => {
    if (savePromiseRef.current) return savePromiseRef.current;
    setSaving(true);
    setError('');
    const request = Promise.resolve()
      .then(async () => {
        const draft = stateRef.current;
        const savedRevision = revisionRef.current;
        const result = await saveLabDraft({
          consultationId,
          ensureConsultationInitialized,
          items: draft.items,
          labNote: draft.labNote,
        });
        return { result, savedRevision };
      })
      .then(({ result, savedRevision }) => {
        if (revisionRef.current === savedRevision) {
          commitState((result?.items || []).map(savedItem), result?.labNote || '', false);
        }
        return result;
      })
      .catch(reason => { setError(reason.message); throw reason; })
      .finally(() => { setSaving(false); savePromiseRef.current = null; });
    savePromiseRef.current = request;
    return request;
  }, [consultationId, ensureConsultationInitialized, commitState]);

  const flushBeforeFinish = useCallback(() => stateRef.current.dirty ? save() : Promise.resolve(), [save]);
  const groups = useMemo(() => Object.values(items.reduce((result, item) => {
    const key = item.labId || 'unknown';
    if (!result[key]) result[key] = { labId: key, labName: item.labName || 'Lab', items: [] };
    result[key].items.push(item);
    return result;
  }, {})), [items]);

  return { items, groups, labNote, dirty, loading, saving, error, addProduct, setQuantity, removeItem, setLabNote, save, flushBeforeFinish };
}
