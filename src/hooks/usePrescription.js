import { useCallback, useEffect, useRef, useState } from 'react';
import {
  approvePrescription, getConsultationPrescription, savePrescriptionDraft,
} from '../services/medicationApi.js';

export function usePrescription({ consultationId, ensureConsultationInitialized }) {
  const [prescription, setPrescription] = useState(null);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const prescriptionRef = useRef(null);
  const consultationIdRef = useRef(consultationId);

  useEffect(() => { prescriptionRef.current = prescription; }, [prescription]);
  useEffect(() => { consultationIdRef.current = consultationId; }, [consultationId]);
  useEffect(() => {
    let active = true;
    const load = async () => {
      await Promise.resolve();
      if (!active) return;
      setPrescription(null); setError('');
      if (!consultationId) { setLoading(false); return; }
      setLoading(true);
      try {
        const result = await getConsultationPrescription(consultationId);
        if (active) setPrescription(result || null);
      } catch (loadError) {
        if (active) setError(loadError.message);
      } finally {
        if (active) setLoading(false);
      }
    };
    load();
    return () => { active = false; };
  }, [consultationId]);

  const ensureId = useCallback(async () => {
    if (consultationIdRef.current) return consultationIdRef.current;
    const initialized = await ensureConsultationInitialized();
    consultationIdRef.current = initialized.consultationId;
    return initialized.consultationId;
  }, [ensureConsultationInitialized]);

  const saveItems = useCallback(async items => {
    setSaving(true); setError('');
    try {
      const id = await ensureId();
      const current = prescriptionRef.current;
      if (current?.status === 'approved') throw new Error('The approved prescription is read-only.');
      const result = await savePrescriptionDraft(id, current?.version || 0, items);
      prescriptionRef.current = result || null;
      setPrescription(result || null);
      return result;
    } catch (saveError) {
      setError(saveError.message); throw saveError;
    } finally { setSaving(false); }
  }, [ensureId]);

  const approve = useCallback(async () => {
    const current = prescriptionRef.current;
    if (!current?.id || current.status !== 'draft' || !current.items?.length) {
      throw new Error('Add at least one medication before approval.');
    }
    setSaving(true); setError('');
    try {
      const result = await approvePrescription(current.id, current.version);
      prescriptionRef.current = result; setPrescription(result); return result;
    } catch (approveError) {
      setError(approveError.message); throw approveError;
    } finally { setSaving(false); }
  }, []);

  return {
    prescription, loading, saving, error, saveItems, approve,
    items: prescription?.items || [],
    reviewRequired: prescription?.status === 'draft' && Boolean(prescription?.items?.length),
    approvedPrescription: prescription?.status === 'approved' ? prescription : null,
  };
}
