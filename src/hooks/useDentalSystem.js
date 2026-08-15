import { useState, useCallback, useEffect, useRef } from 'react';
import { INITIAL_CLINICAL_STATE, FDI_TOOTH_MAP } from '../data/toothData';
import {
  fetchConsultation,
  invalidateConsultationSessionState,
  resumeConsultationSaveQueue,
  saveConsultationToApi,
} from '../services/consultationApi';
import { useAuth } from '../context/AuthContext';
import {
  hydrateClinicalFindings,
  removeClinicalFinding as removeFinding,
  serializeClinicalFindings,
  unionFindingSymptoms,
  upsertClinicalFinding,
} from '../services/clinicalFindings.js';

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export const isValidConsultationPatientId = (patientId) => (
  typeof patientId === 'string' && UUID_PATTERN.test(patientId)
);

/**
 * Business Logic Layer: Dental System State Management
 * The backend database is the sole authority for clinical consultation data.
 */
export const useDentalSystem = (patientId = null) => {
  const { user, loading: authLoading } = useAuth();
  const [toothData, setToothData] = useState(INITIAL_CLINICAL_STATE);
  const [selectedToothId, setSelectedToothId] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [persistenceMode, setPersistenceMode] = useState('api'); // 'api' | 'error'
  const [version, setVersion] = useState(0); // ENTERPRISE: Optimistic Locking Version
  const [dentalStateVersion, setDentalStateVersion] = useState(0);
  const [sessionNote, setSessionNote] = useState('');
  const [symptoms, setSymptoms] = useState([]);
  const [clinicalFindingsByTooth, setClinicalFindingsByTooth] = useState(null);
  const [lastConsultationNote, setLastConsultationNote] = useState(null);
  const [consultationId, setConsultationId] = useState(null);
  const [appointmentId, setAppointmentId] = useState(null);
  const lastSavedData = useRef(JSON.stringify({
    toothData: INITIAL_CLINICAL_STATE, symptoms: [], clinicalFindings: null,
  }));
  const toothDataRef = useRef(INITIAL_CLINICAL_STATE);
  const symptomsRef = useRef([]);
  const clinicalFindingsRef = useRef(null);
  const versionRef = useRef(0);
  const dentalStateVersionRef = useRef(0);
  const initializationCompleteRef = useRef(false);
  const autosavePausedRef = useRef(false);
  const lifecycleBarrierRef = useRef(false);
  const autosaveTimerRef = useRef(null);
  const activeScopeRef = useRef('');
  const previousUserIdRef = useRef(user?.id ?? null);
  const consultationIdRef = useRef(null);
  const consultationInitializationRef = useRef(null);

  const sessionScope = user?.id || '';
  const hasAuthenticatedUser = Boolean(user);

  useEffect(() => {
    activeScopeRef.current = `${sessionScope}:${patientId || ''}`;
  }, [patientId, sessionScope]);

  useEffect(() => {
    const nextUserId = user?.id ?? null;
    if (previousUserIdRef.current !== nextUserId) {
      invalidateConsultationSessionState();
      previousUserIdRef.current = nextUserId;
    }
  }, [user?.id]);

  useEffect(() => {
    toothDataRef.current = toothData;
  }, [toothData]);

  useEffect(() => {
    symptomsRef.current = symptoms;
  }, [symptoms]);

  useEffect(() => {
    clinicalFindingsRef.current = clinicalFindingsByTooth;
  }, [clinicalFindingsByTooth]);

  useEffect(() => {
    consultationIdRef.current = consultationId;
  }, [consultationId]);

  const applySaveResult = useCallback((result, savedToothData, savedSymptoms, savedFindings) => {
    versionRef.current = result.version;
    dentalStateVersionRef.current = (
      result.dentalStateVersion ?? dentalStateVersionRef.current
    );
    lastSavedData.current = JSON.stringify({
      toothData: savedToothData, symptoms: savedSymptoms, clinicalFindings: savedFindings,
    });
    setVersion(result.version);
    setDentalStateVersion(dentalStateVersionRef.current);
    setSessionNote(result.sessionNote ?? sessionNote);
    consultationIdRef.current = result.consultationId ?? consultationIdRef.current;
    setConsultationId(consultationIdRef.current);
    setAppointmentId(result.appointmentId ?? appointmentId);
    setLastConsultationNote(result.lastConsultationNote ?? lastConsultationNote);
    setError(null);
  }, [appointmentId, lastConsultationNote, sessionNote]);

  const handleSaveFailure = useCallback((err) => {
    if (err?.status === 409 || err?.message?.includes('CONFLICT')) {
      const authoritative = err.authoritative;
      if (authoritative) {
        versionRef.current = authoritative.version ?? versionRef.current;
        dentalStateVersionRef.current = (
          authoritative.dentalStateVersion ?? dentalStateVersionRef.current
        );
        setVersion(versionRef.current);
        setDentalStateVersion(dentalStateVersionRef.current);
        setConsultationId(authoritative.consultationId ?? consultationId);
        setAppointmentId(authoritative.appointmentId ?? appointmentId);
      }
      autosavePausedRef.current = true;
      setError(
        'VERSION_CONFLICT: Your unsaved dental changes are preserved. Review them and retry.'
      );
      return;
    }
    setError(err?.message || 'Clinical changes could not be saved to the clinic database.');
  }, [appointmentId, consultationId]);

  const persistConsultation = useCallback(async (
    data,
    note,
    sessionSymptoms = symptomsRef.current,
    findingsByTooth = clinicalFindingsRef.current,
  ) => {
    const operationScope = `${sessionScope}:${patientId || ''}`;
    const findingsSnapshot = findingsByTooth === null
      ? undefined
      : serializeClinicalFindings(findingsByTooth);
    const compatibilitySymptoms = findingsByTooth === null
      ? sessionSymptoms
      : unionFindingSymptoms(findingsByTooth);
    try {
      const result = await saveConsultationToApi(
        patientId,
        data,
        versionRef.current,
        note,
        dentalStateVersionRef.current,
        sessionScope,
        compatibilitySymptoms,
        findingsSnapshot,
      );
      if (activeScopeRef.current === operationScope) {
        applySaveResult(result, data, compatibilitySymptoms, findingsSnapshot ?? null);
      }
      return result;
    } catch (err) {
      if (activeScopeRef.current === operationScope) handleSaveFailure(err);
      throw err;
    }
  }, [applySaveResult, handleSaveFailure, patientId, sessionScope]);

  const ensureConsultationInitialized = useCallback(async () => {
    if (consultationIdRef.current) {
      return { consultationId: consultationIdRef.current, appointmentId };
    }
    if (consultationInitializationRef.current) return consultationInitializationRef.current;
    if (authLoading || !hasAuthenticatedUser || !isValidConsultationPatientId(patientId)) {
      throw new Error('The consultation is not ready to initialize.');
    }
    const operationScope = `${sessionScope}:${patientId || ''}`;
    const initialization = (async () => {
      const loaded = await fetchConsultation(patientId, sessionScope);
      const result = loaded?.consultationId
        ? loaded
        : await persistConsultation(
          toothDataRef.current,
          undefined,
          symptomsRef.current,
          clinicalFindingsRef.current,
        );
      if (!result?.consultationId) {
        throw new Error('The consultation service did not return a consultation identifier.');
      }
      if (activeScopeRef.current !== operationScope) {
        throw new Error('The consultation changed while initialization was in progress.');
      }
      consultationIdRef.current = result.consultationId;
      setConsultationId(result.consultationId);
      setAppointmentId(result.appointmentId ?? null);
      return result;
    })().finally(() => {
      consultationInitializationRef.current = null;
    });
    consultationInitializationRef.current = initialization;
    return initialization;
  }, [appointmentId, authLoading, hasAuthenticatedUser, patientId, persistConsultation, sessionScope]);

  // INITIALIZATION: consultation data is loaded only from the backend API.
  useEffect(() => {
    let active = true;

    async function initData() {
      initializationCompleteRef.current = false;
      autosavePausedRef.current = false;
      lifecycleBarrierRef.current = false;
      if (autosaveTimerRef.current) clearTimeout(autosaveTimerRef.current);
      autosaveTimerRef.current = null;
      toothDataRef.current = INITIAL_CLINICAL_STATE;
      symptomsRef.current = [];
      clinicalFindingsRef.current = null;
      versionRef.current = 0;
      dentalStateVersionRef.current = 0;
      lastSavedData.current = JSON.stringify({ toothData: INITIAL_CLINICAL_STATE, symptoms: [], clinicalFindings: null });
      setToothData(INITIAL_CLINICAL_STATE);
      setSelectedToothId(null);
      setVersion(0);
      setDentalStateVersion(0);
      setSessionNote('');
      setSymptoms([]);
      setClinicalFindingsByTooth(null);
      setLastConsultationNote(null);
      setConsultationId(null);
      consultationIdRef.current = null;
      consultationInitializationRef.current = null;
      setAppointmentId(null);
      setLoading(true);
      setError(null);

      if (authLoading) return;
      if (!hasAuthenticatedUser) {
        setPersistenceMode('error');
        setError('You are not authorized to access this consultation.');
        setLoading(false);
        return;
      }
      if (!isValidConsultationPatientId(patientId)) {
        setPersistenceMode('error');
        setError('Patient record not found.');
        setLoading(false);
        return;
      }

      try {
        const apiData = await fetchConsultation(patientId, sessionScope);
        if (!active) return;
        if (!apiData) throw new Error('The consultation could not be loaded from the clinic database.');

        const loadedToothData = {
          ...INITIAL_CLINICAL_STATE,
          ...(apiData.toothData || {}),
        };
        const loadedVersion = apiData.version ?? 0;
        const loadedDentalStateVersion = apiData.dentalStateVersion ?? 0;
        const loadedSymptoms = Array.isArray(apiData.symptoms) ? apiData.symptoms : [];
        const loadedFindings = hydrateClinicalFindings(apiData.clinicalFindings);
        toothDataRef.current = loadedToothData;
        versionRef.current = loadedVersion;
        dentalStateVersionRef.current = loadedDentalStateVersion;
        symptomsRef.current = loadedSymptoms;
        clinicalFindingsRef.current = loadedFindings;
        lastSavedData.current = JSON.stringify({
          toothData: loadedToothData,
          symptoms: loadedFindings === null ? loadedSymptoms : unionFindingSymptoms(loadedFindings),
          clinicalFindings: loadedFindings === null ? null : serializeClinicalFindings(loadedFindings),
        });
        resumeConsultationSaveQueue(
          patientId,
          loadedVersion,
          loadedDentalStateVersion,
          sessionScope,
        );
        setToothData(loadedToothData);
        setVersion(loadedVersion);
        setDentalStateVersion(loadedDentalStateVersion);
        setSessionNote(apiData.sessionNote ?? '');
        setSymptoms(loadedSymptoms);
        setClinicalFindingsByTooth(loadedFindings);
        setLastConsultationNote(apiData.lastConsultationNote ?? null);
        setConsultationId(apiData.consultationId ?? null);
        consultationIdRef.current = apiData.consultationId ?? null;
        setAppointmentId(apiData.appointmentId ?? null);
        setPersistenceMode('api');
        initializationCompleteRef.current = true;
      } catch (err) {
        if (!active) return;
        console.error("Consultation backend load failed", err);
        setPersistenceMode('error');
        setError(err?.message || 'The consultation could not be loaded from the clinic database.');
      } finally {
        if (active) setLoading(false);
      }
    }
    initData();
    return () => {
      active = false;
    };
  }, [authLoading, hasAuthenticatedUser, patientId, sessionScope]);

  // Select a tooth by its FDI ID
  const selectTooth = useCallback((id) => {
    const sId = id?.toString();
    if (sId && FDI_TOOTH_MAP[sId]) {
      setSelectedToothId(sId);
    } else {
      setSelectedToothId(null);
    }
  }, []);

  // ENTERPRISE: Debounced Autosave Effect with VERSIONING
  useEffect(() => {
    if (
      persistenceMode !== 'api'
      || loading
      || !initializationCompleteRef.current
      || autosavePausedRef.current
      || lifecycleBarrierRef.current
    ) return;

    // Avoid syncing if data hasn't changed since last successful save
    const currentFindings = clinicalFindingsByTooth === null
      ? null : serializeClinicalFindings(clinicalFindingsByTooth);
    const currentSymptoms = clinicalFindingsByTooth === null
      ? symptoms : unionFindingSymptoms(clinicalFindingsByTooth);
    if (JSON.stringify({ toothData, symptoms: currentSymptoms, clinicalFindings: currentFindings }) === lastSavedData.current) {
      return;
    }

    autosaveTimerRef.current = setTimeout(async () => {
      autosaveTimerRef.current = null;
      if (lifecycleBarrierRef.current) return;
      try {
        await persistConsultation(toothData, undefined, currentSymptoms, clinicalFindingsByTooth);
      } catch (err) {
        console.error("Enterprise sync failed:", err);
      }
    }, 1000); // Slightly longer debounce for stability

    return () => {
      if (autosaveTimerRef.current) clearTimeout(autosaveTimerRef.current);
      autosaveTimerRef.current = null;
    };
  }, [toothData, symptoms, clinicalFindingsByTooth, persistenceMode, loading, persistConsultation, version]);

  const saveSessionNote = useCallback(async (note) => {
    if (persistenceMode !== 'api') {
      throw new Error('Consultation note requires a backend connection.');
    }
    if (autosavePausedRef.current) {
      resumeConsultationSaveQueue(
        patientId,
        versionRef.current,
        dentalStateVersionRef.current,
        sessionScope,
      );
      autosavePausedRef.current = false;
    }
    return persistConsultation(toothDataRef.current, note);
  }, [patientId, persistenceMode, persistConsultation, sessionScope]);

  const saveCurrentSession = useCallback(async () => {
    if (persistenceMode !== 'api') {
      throw new Error('Consultation save requires a backend connection.');
    }
    if (autosavePausedRef.current) {
      resumeConsultationSaveQueue(
        patientId,
        versionRef.current,
        dentalStateVersionRef.current,
        sessionScope,
      );
      autosavePausedRef.current = false;
    }
    return persistConsultation(toothDataRef.current, undefined, symptomsRef.current);
  }, [patientId, persistenceMode, persistConsultation, sessionScope]);

  const flushBeforeFinish = useCallback(async (note) => {
    if (persistenceMode !== 'api') {
      throw new Error('Consultation save requires a backend connection.');
    }
    lifecycleBarrierRef.current = true;
    if (autosaveTimerRef.current) clearTimeout(autosaveTimerRef.current);
    autosaveTimerRef.current = null;
    if (autosavePausedRef.current) {
      resumeConsultationSaveQueue(
        patientId,
        versionRef.current,
        dentalStateVersionRef.current,
        sessionScope,
      );
      autosavePausedRef.current = false;
    }
    try {
      return await persistConsultation(
        toothDataRef.current,
        note,
        symptomsRef.current,
      );
    } catch (error) {
      lifecycleBarrierRef.current = false;
      throw error;
    }
  }, [patientId, persistenceMode, persistConsultation, sessionScope]);

  const cancelFinishBarrier = useCallback(() => {
    lifecycleBarrierRef.current = false;
  }, []);

  const markConsultationFinished = useCallback(() => {
    lifecycleBarrierRef.current = true;
    initializationCompleteRef.current = false;
    if (autosaveTimerRef.current) clearTimeout(autosaveTimerRef.current);
    autosaveTimerRef.current = null;
  }, []);

  const retrySave = useCallback(async () => {
    if (persistenceMode !== 'api') {
      throw new Error('Consultation retry requires a backend connection.');
    }
    resumeConsultationSaveQueue(
      patientId,
      versionRef.current,
      dentalStateVersionRef.current,
      sessionScope,
    );
    autosavePausedRef.current = false;
    return persistConsultation(toothDataRef.current);
  }, [patientId, persistenceMode, persistConsultation, sessionScope]);

  const setSessionSymptoms = useCallback((nextSymptoms) => {
    setSymptoms(current => {
      const next = typeof nextSymptoms === 'function' ? nextSymptoms(current) : nextSymptoms;
      return Array.isArray(next) ? next : current;
    });
  }, []);

  // Update clinical status (Immediate UI Update)
  const updateToothStatus = useCallback((id, status) => {
    if (!id) return;
    
    const newEntry = { 
      type: 'Status Change', 
      date: new Date().toISOString(), 
      note: `Status updated to ${status}` 
    };

    setToothData(prev => {
      const next = {
        ...prev,
        [id]: {
        ...prev[id],
        status,
        history: [...(prev[id].history || []), newEntry]
      }};
      toothDataRef.current = next;
      return next;
    });
    setClinicalFindingsByTooth(previous => {
      const next = upsertClinicalFinding(previous || {}, id, toothDataRef.current[id], {
        toothStatus: status,
      });
      clinicalFindingsRef.current = next;
      return next;
    });
  }, []);

  // Bulk update tooth record (Immediate UI Update)
  const updateToothRecord = useCallback((id, updates) => {
    if (!id) return;

    const newEntry = { 
      type: 'Record Update', 
      date: new Date().toISOString(), 
      note: updates.notes || 'Clinical record updated.' 
    };

    setToothData(prev => ({
      ...prev,
      [id]: { 
        ...prev[id], 
        ...updates,
        history: [...(prev[id].history || []), newEntry]
      }
    }));
  }, []);

  // Manual Note Update (Immediate UI Update)
  const updateToothNotes = useCallback((id, notes) => {
    if (!id) return;
    setToothData(prev => {
      const next = { ...prev, [id]: { ...prev[id], notes } };
      toothDataRef.current = next;
      return next;
    });
    setClinicalFindingsByTooth(previous => {
      const next = upsertClinicalFinding(previous || {}, id, toothDataRef.current[id], {
        toothNote: notes,
      });
      clinicalFindingsRef.current = next;
      return next;
    });
  }, []);

  const setToothFindingSymptoms = useCallback((id, nextSymptoms) => {
    if (!id) return;
    setClinicalFindingsByTooth(previous => {
      const currentSymptoms = previous?.[id]?.symptoms || [];
      const symptomsForTooth = typeof nextSymptoms === 'function'
        ? nextSymptoms(currentSymptoms)
        : nextSymptoms;
      const next = upsertClinicalFinding(previous || {}, id, toothDataRef.current[id], {
        symptoms: Array.isArray(symptomsForTooth) ? symptomsForTooth : currentSymptoms,
      });
      clinicalFindingsRef.current = next;
      return next;
    });
  }, []);

  const removeClinicalFinding = useCallback((id) => {
    setClinicalFindingsByTooth(previous => {
      const next = removeFinding(previous || {}, id);
      clinicalFindingsRef.current = next;
      return next;
    });
  }, []);

  const resetSystem = useCallback(async () => {
    try {
      if (persistenceMode !== 'api') {
        throw new Error('Consultation reset requires a backend connection.');
      }
      if (autosavePausedRef.current) {
        resumeConsultationSaveQueue(
          patientId,
          versionRef.current,
          dentalStateVersionRef.current,
          sessionScope,
        );
        autosavePausedRef.current = false;
      }
      await persistConsultation(INITIAL_CLINICAL_STATE, undefined, [], {});
      setToothData(INITIAL_CLINICAL_STATE);
      toothDataRef.current = INITIAL_CLINICAL_STATE;
      setClinicalFindingsByTooth({});
      clinicalFindingsRef.current = {};
      setSelectedToothId(null);
      setError(null);
    } catch (err) {
      setError(err?.message || 'The consultation could not be reset in the clinic database.');
      throw err;
    }
  }, [patientId, persistenceMode, persistConsultation, sessionScope]);

  return {
    toothData,
    selectedToothId,
    selectedToothData: selectedToothId ? toothData[selectedToothId] : null,
    selectTooth,
    updateToothStatus,
    updateToothNotes,
    updateToothRecord,
    resetSystem,
    loading,
    error,
    persistenceMode,
    version,
    dentalStateVersion,
    consultationId,
    appointmentId,
    sessionNote,
    symptoms,
    setSessionSymptoms,
    clinicalFindingsByTooth,
    setToothFindingSymptoms,
    removeClinicalFinding,
    lastConsultationNote,
    saveSessionNote,
    saveCurrentSession,
    ensureConsultationInitialized,
    flushBeforeFinish,
    cancelFinishBarrier,
    markConsultationFinished,
    retrySave,
  };
};
