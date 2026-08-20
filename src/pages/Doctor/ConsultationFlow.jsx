import React, { useEffect, useMemo, useState } from 'react';
import { useParams, useNavigate, useLocation } from 'react-router-dom';
import { AlertCircle, ArrowLeft, Brain, CheckCircle2, ClipboardList, Cloud, Edit3, FileText, FlaskConical, Heart, Loader2, Save, ShieldCheck, Sparkles, Stethoscope, WifiOff, X, RefreshCw, User, Phone, Droplets, ChevronDown, Search, PlusCircle, ReceiptText } from 'lucide-react';
import Layout from '../../components/Layout';
import Dental3DModel from '../../components/Dental3DModel';
import { getToothById } from '../../data/toothData';
import { CLINICAL_STATUSES } from '../../data/clinicalOptions';
import { DENTAL_SYMPTOMS } from '../../data/medicalKnowledge';
import { useDentalSystem } from '../../hooks/useDentalSystem';
import { useData } from '../../context/DataContext';
import { useAuth } from '../../context/AuthContext';
import { buildAIReportGenerationPayload, buildClinicalReportPayload, finalizeReport, generateAIReport, humanizeReport, saveReport, updateReport } from '../../services/reportApi';
import PreviousConsultationNoteCurtain from '../../components/PreviousConsultationNoteCurtain';
import { createSymptom, listSymptoms } from '../../services/clinicalReferenceApi.js';
import ProcedureSelector from '../../components/ProcedureSelector';
import LabProductSelector from '../../components/LabProductSelector.jsx';
import { useConsultationLabs } from '../../hooks/useConsultationLabs.js';
import { getConsultationProcedures } from '../../services/financeApi';
import { decimalToCents, formatMoney } from '../../config/money';
import { serializeClinicalFindings, unionFindingSymptoms } from '../../services/clinicalFindings.js';
import MedicalReportMarkdown from '../../components/consultation/MedicalReportMarkdown.jsx';
import MedicationSection from '../../components/consultation/MedicationSection.jsx';
import { usePrescription } from '../../hooks/usePrescription.js';
import {
  serializeReviewedAssessments,
} from '../../services/medicalReportReview.js';

// ── Dropdown Component ──────────────────────────────────────────────────────
function SymptomDropdown({ options, selected, onToggle, disabled, onAddCustom }) {
  const [isOpen, setIsOpen] = useState(false);
  const [search, setSearch] = useState('');

  const filtered = options.filter(opt => 
    opt.name.toLowerCase().includes(search.toLowerCase()) && 
    !selected.includes(opt.name)
  );

  return (
    <div className="custom-dropdown" style={{ position: 'relative', width: '100%' }}>
      <div 
        className={`form-input ${disabled ? 'disabled' : ''}`}
        onClick={() => !disabled && setIsOpen(!isOpen)}
        style={{ 
          display: 'flex', 
          alignItems: 'center', 
          justifyContent: 'space-between',
          cursor: disabled ? 'not-allowed' : 'pointer',
          minHeight: '44px',
          padding: '0 12px'
        }}
      >
        <span style={{ color: search || selected.length > 0 ? 'var(--clr-text)' : 'var(--clr-subtext)', fontSize: '0.85rem' }}>
          {selected.length > 0 ? `${selected.length} Selected` : 'Select symptoms...'}
        </span>
        <ChevronDown size={16} style={{ transition: 'transform 0.2s', transform: isOpen ? 'rotate(180deg)' : '' }} />
      </div>

      {isOpen && (
        <div style={{ 
          position: 'absolute', 
          top: '100%', 
          left: 0, 
          right: 0, 
          background: 'white', 
          border: '1px solid var(--clr-border)', 
          borderRadius: 12, 
          boxShadow: '0 10px 25px rgba(0,0,0,0.1)', 
          zIndex: 100,
          marginTop: 6,
          padding: 8
        }}>
          <div style={{ position: 'relative', marginBottom: 8 }}>
            <Search size={14} style={{ position: 'absolute', left: 10, top: '50%', transform: 'translateY(-50%)', color: 'var(--clr-subtext)' }} />
            <input 
              autoFocus
              className="form-input" 
              placeholder="Search or add custom..." 
              value={search}
              onChange={e => setSearch(e.target.value)}
              onKeyDown={e => {
                if (e.key === 'Enter' && search.trim()) {
                  onAddCustom(search.trim());
                  setSearch('');
                  setIsOpen(false);
                }
              }}
              style={{ paddingLeft: 32, fontSize: '0.8rem', height: 36, margin: 0 }}
            />
          </div>
          <div style={{ maxHeight: 200, overflow: 'auto' }}>
            {filtered.length > 0 ? filtered.map(opt => (
              <div 
                key={opt.id} 
                onClick={() => { onToggle(opt.name); setSearch(''); setIsOpen(false); }}
                style={{ 
                  padding: '8px 12px', 
                  fontSize: '0.82rem', 
                  cursor: 'pointer', 
                  borderRadius: 8,
                  display: 'flex',
                  alignItems: 'center',
                  gap: 10
                }}
                className="dropdown-item-hover"
              >
                {opt.name}
              </div>
            )) : search.trim() ? (
              <div 
                onClick={() => { onAddCustom(search.trim()); setSearch(''); setIsOpen(false); }}
                style={{ padding: '8px 12px', fontSize: '0.82rem', cursor: 'pointer', borderRadius: 8, color: 'var(--clr-primary)', fontWeight: 700 }}
              >
                + Add "{search}"
              </div>
            ) : (
              <div style={{ padding: '8px 12px', fontSize: '0.82rem', color: 'var(--clr-subtext)', textAlign: 'center' }}>
                No symptoms found
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

export default function ConsultationFlow() {
  const { user } = useAuth();
  const { id: urlPatientId } = useParams();
  const navigate = useNavigate();
  const location = useLocation();
  const { patients, appointments, completeAppointmentByPatient, updatePatient, fetchPatientById } = useData();

  const [viewMode, setViewMode] = useState('both');
  const [customSymptom, setCustomSymptom] = useState('');
  const [isConsultationActive, setIsConsultationActive] = useState(true);
  const [toast, setToast] = useState(null);
  const [showConsultationNote, setShowConsultationNote] = useState(false);
  const [noteDraft, setNoteDraft] = useState('');
  const [noteDraftDirty, setNoteDraftDirty] = useState(false);
  const [isSavingNote, setIsSavingNote] = useState(false);
  const [noteError, setNoteError] = useState('');
  const [showProcedures, setShowProcedures] = useState(false);
  const [showLabProducts, setShowLabProducts] = useState(false);
  const [procedureSummary, setProcedureSummary] = useState({ items: [], total: '0.00' });
  const [procedureSummaryError, setProcedureSummaryError] = useState('');

  // Symptoms & Findings
  const [availableSymptoms, setAvailableSymptoms] = useState([]);
  const [isSymptomsLoading, setIsSymptomsLoading] = useState(true);
  const [symptomsError, setSymptomsError] = useState('');
  const [showCustomModal, setShowCustomModal] = useState(false);
  const [pendingCustomSymptom, setPendingCustomSymptom] = useState('');

  // AI Report state
  const [reportMode, setReportMode] = useState('ai');
  const [aiReportDraft, setAiReportDraft] = useState('');
  const [manualReportDraft, setManualReportDraft] = useState('');
  const [aiReportBaseline, setAiReportBaseline] = useState('');
  const [isGenerating, setIsGenerating] = useState(false);
  const [reportStep, setReportStep] = useState('input'); // input | ai_review | editing | saved | humanizing | humanized
  const [humanizedReport, setHumanizedReport] = useState('');
  const [isHumanizing, setIsHumanizing] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [currentReportId, setCurrentReportId] = useState(null);
  const [aiInstructions, setAiInstructions] = useState('');
  const [reviewDraft, setReviewDraft] = useState({});
  const [summaryDraft, setSummaryDraft] = useState('');
  const [isEditingReport, setIsEditingReport] = useState(false);
  const [finalizedSnapshot, setFinalizedSnapshot] = useState(null);

  // Patient state
  const [patient, setPatient] = useState(null);
  const [isPageLoading, setIsPageLoading] = useState(true);
  const [editingPatient, setEditingPatient] = useState(false);
  const [patientEdits, setPatientEdits] = useState({});
  const [isSavingPatient, setIsSavingPatient] = useState(false);
  const [isFinishing, setIsFinishing] = useState(false);
  const finishInFlightRef = React.useRef(false);
  const medicationSectionRef = React.useRef(null);

  const showToast = (msg, type = 'info') => {
    setToast({ msg, type });
    setTimeout(() => setToast(null), 3500);
  };

  useEffect(() => {
    let isMounted = true;
    const loadPatient = async () => {
      if (!urlPatientId) {
        navigate('/doctor/patients');
        return;
      }

      // Check if we already have the full data for this ID
      const isFull = (p) => p && p.id && (p.gender || p.phone || p.bloodType || p.blood_type);
      if (patient && patient.id.toString() === urlPatientId && isFull(patient)) {
        return;
      }

      // 1. Check if we have the patient in state or context
      let candidate = location.state?.patient;
      if (!isFull(candidate)) {
        const fromContext = patients.find(p => p.id.toString() === urlPatientId);
        if (isFull(fromContext)) {
          candidate = fromContext;
        }
      }

      // 2. If we have a FULL patient, use it
      if (isFull(candidate)) {
        if (isMounted) {
          setPatient(candidate);
          setIsPageLoading(false);
        }
      } else {
        // 3. Otherwise (missing or partial), fetch from backend
        const fromBackend = await fetchPatientById(urlPatientId);
        if (isMounted && fromBackend) {
          setPatient(fromBackend);
          setIsPageLoading(false);
        } else if (isMounted) {
          setIsPageLoading(false);
        }
      }
    };

    loadPatient();
    return () => { isMounted = false; };
  }, [urlPatientId, patients, fetchPatientById, location.state, navigate, patient]);

  useEffect(() => {
    if (patient) {
      setPatientEdits({ 
        phone: patient.phone, 
        age: patient.age, 
        gender: patient.gender, 
        bloodType: patient.bloodType || patient.blood_type 
      });
    }
  }, [patient]);

  const {
    toothData, selectedToothId, selectedToothData, selectTooth,
    updateToothStatus, updateToothNotes, updateToothRecord,
    loading, error: consultationError, persistenceMode, consultationId, appointmentId, sessionNote,
    lastConsultationNote, saveSessionNote, saveCurrentSession, flushBeforeFinish,
    ensureConsultationInitialized,
    cancelFinishBarrier, markConsultationFinished, retrySave, symptoms,
    clinicalFindingsByTooth, setToothFindingSymptoms, removeClinicalFinding,
  } = useDentalSystem(urlPatientId);

  const prescriptionWorkflow = usePrescription({
    consultationId,
    ensureConsultationInitialized,
  });

  const consultationLabs = useConsultationLabs(consultationId, ensureConsultationInitialized);

  useEffect(() => {
    let active = true;
    setProcedureSummary({ items: [], total: '0.00' });
    setProcedureSummaryError('');
    if (!user?.id || !urlPatientId) return () => { active = false; };
    getConsultationProcedures(urlPatientId)
      .then(result => { if (active) { setProcedureSummary(result); setProcedureSummaryError(''); } })
      .catch(error => { if (active) setProcedureSummaryError(error.message); });
    return () => { active = false; };
  }, [urlPatientId, user?.id]);

  const handleRetryConsultationSave = async () => {
    try {
      await retrySave();
      showToast('Dental changes saved successfully.', 'success');
    } catch (err) {
      showToast(err?.message || 'Dental changes are still unsaved.', 'error');
    }
  };

  const openConsultationNote = () => {
    setNoteDraft(sessionNote || '');
    setNoteDraftDirty(false);
    setNoteError('');
    setShowConsultationNote(true);
  };

  const handleSaveConsultationNote = async () => {
    setIsSavingNote(true);
    setNoteError('');
    try {
      await saveSessionNote(noteDraft);
      setNoteDraftDirty(false);
      setShowConsultationNote(false);
      showToast('Consultation note saved', 'success');
    } catch (err) {
      const message = err?.message?.includes('CONFLICT')
        ? 'This consultation changed elsewhere. Refresh before saving the note.'
        : 'The note could not be saved to the clinic database.';
      setNoteError(message);
      showToast(message, 'error');
    } finally {
      setIsSavingNote(false);
    }
  };

  useEffect(() => {
    const fetchSymptoms = async () => {
      setSymptomsError('');
      try {
        const data = await listSymptoms();
        setAvailableSymptoms(data);
      } catch (err) {
        console.error('Failed to fetch symptoms:', err);
        setSymptomsError(err?.message || 'Clinical symptoms could not be loaded.');
      } finally {
        setIsSymptomsLoading(false);
      }
    };
    fetchSymptoms();
  }, []);

  useEffect(() => { 
    setReportMode('ai');
    setAiReportDraft('');
    setManualReportDraft('');
    setAiReportBaseline('');
    setReportStep('input'); 
    setHumanizedReport(''); 
    setCurrentReportId(null);
    setReviewDraft({});
    setSummaryDraft('');
    setIsEditingReport(false);
    setFinalizedSnapshot(null);
  }, [urlPatientId]);

  const stats = useMemo(() => {
    const c = { healthy: 0, problem: 0, treated: 0, missing: 0 };
    Object.values(toothData).forEach(t => { if (c[t.status] !== undefined) c[t.status]++; });
    return c;
  }, [toothData]);

  const selectedTooth = selectedToothId ? getToothById(selectedToothId) : null;
  const structuredFindings = clinicalFindingsByTooth === null
    ? null : serializeClinicalFindings(clinicalFindingsByTooth);
  const selectedFinding = selectedToothId ? clinicalFindingsByTooth?.[selectedToothId] : null;
  const selectedSymptoms = selectedFinding?.symptoms || [];
  const reportSymptoms = clinicalFindingsByTooth === null
    ? symptoms : unionFindingSymptoms(clinicalFindingsByTooth);
  const toggleSymptom = (name) => setToothFindingSymptoms(
    selectedToothId,
    current => current.includes(name) ? current.filter(s => s !== name) : [...current, name],
  );
  
  const handleAddCustomRequest = (name) => {
    if (!name.trim()) return;
    if (selectedSymptoms.includes(name.trim())) return;
    setPendingCustomSymptom(name.trim());
    setShowCustomModal(true);
  };

  const handleCustomSymptomAction = async (saveGlobally) => {
    const name = pendingCustomSymptom;
    if (saveGlobally) {
      try {
        const newSym = await createSymptom({ name });
        setAvailableSymptoms(prev => [...prev, newSym].sort((a, b) => a.name.localeCompare(b.name)));
        showToast(`Symptom "${name}" saved for future use`, 'success');
      } catch (err) {
        console.error('Failed to save global symptom:', err);
        showToast('Failed to save symptom globally', 'error');
      }
    }
    
    setToothFindingSymptoms(selectedToothId, prev => [...prev, name]);
    setShowCustomModal(false);
    setPendingCustomSymptom('');
  };

  const fullName = patient?.name || 'Unknown Patient';
  const initials = patient?.name ? patient.name.split(' ').map(n => n[0]).join('').toUpperCase().slice(0, 2) : 'P';
  const canGenerate = Array.isArray(structuredFindings) && structuredFindings.length > 0;
  const currentAppointment = appointments?.find(item => String(item.id) === String(appointmentId));
  const examinationDate = currentAppointment?.date || currentAppointment?.appointment_date || new Date();
  const reviewedAssessments = serializeReviewedAssessments(structuredFindings || [], reviewDraft);
  const reviewedSummary = summaryDraft || '';
  const hasManualReportEdits = aiReportDraft !== aiReportBaseline;
  const previewReport = reportMode === 'ai' ? aiReportDraft : manualReportDraft;

  // ── AI Report Generation ──
  const handleGenerateReport = async (isRegeneration = false) => {
    if (!canGenerate) return;
    if (isRegeneration && hasManualReportEdits && !window.confirm(
      'Regenerating the AI report will replace your manual edits. Continue?',
    )) return;
    setIsGenerating(true);
    try {
      const savedSession = await saveCurrentSession();
      const data = buildAIReportGenerationPayload({
        patient,
        consultationId: savedSession?.consultationId || consultationId,
        examinationDate,
        reportDate: new Date().toISOString(),
        clinicalFindings: structuredFindings,
        consultationNote: savedSession?.sessionNote ?? sessionNote,
        performedProcedures: procedureSummary.items,
        doctor: { name: user?.name || 'Doctor', specialty: user?.specialization || null },
        aiInstructions,
        approvedPrescription: prescriptionWorkflow.approvedPrescription,
      });
      const result = await generateAIReport(data);
      const nextDraft = Object.fromEntries(structuredFindings.map(finding => [finding.toothId, {
        clinicalDescription: null,
        diagnosis: null,
        icd10: null,
        treatmentPlan: null,
      }]));
      setAiReportDraft(result.report);
      setAiReportBaseline(result.report);
      setHumanizedReport('');
      setReviewDraft(nextDraft);
      setSummaryDraft('');
      setIsEditingReport(false);
      setReportStep('ai_review');
      showToast('AI report generated successfully', 'success');
    } catch (err) {
      showToast('AI generation failed. Check Ollama connection.', 'error');
    } finally { setIsGenerating(false); }
  };

  const handleHumanizeReport = async () => {
    if (reportMode !== 'ai' || !aiReportDraft.trim() || reportStep === 'finalized' || isHumanizing) return;
    setIsHumanizing(true);
    try {
      const result = await humanizeReport(aiReportDraft, fullName);
      const nextHumanizedReport = result.humanized_report || '';
      if (!nextHumanizedReport.trim()) throw new Error('Humanized report content is empty.');
      let reportId = currentReportId;
      if (reportId) {
        await updateReport(reportId, { humanized_report: nextHumanizedReport });
      } else {
        const savedSession = await saveCurrentSession();
        const created = await saveReport(buildClinicalReportPayload({
          patientId: urlPatientId,
          consultationId: savedSession?.consultationId || consultationId,
          appointmentId: savedSession?.appointmentId || appointmentId,
          toothId: null,
          toothStatus: null,
          symptoms: Array.isArray(savedSession?.symptoms) ? savedSession.symptoms : reportSymptoms,
          doctorNotes: sessionNote,
          aiDraftReport: aiReportDraft,
          finalMedicalReport: aiReportDraft,
          humanizedReport: nextHumanizedReport,
          status: 'draft',
        }));
        reportId = created.id;
        setCurrentReportId(reportId);
      }
      setHumanizedReport(nextHumanizedReport);
      showToast('Patient-friendly report generated', 'success');
    } catch (err) {
      showToast(err?.message || 'Report humanization failed', 'error');
    } finally {
      setIsHumanizing(false);
    }
  };

  // ── Create the existing report row, then finalize it through Migration 020. ──
  const handleFinalizeReport = async () => {
    if (!previewReport.trim() || finalizedSnapshot) {
      showToast(reportMode === 'manual'
        ? 'Write the clinical report before finalizing.'
        : 'Generate or write the AI report before finalizing.', 'warning');
      return;
    }
    setIsSaving(true);
    try {
      const savedSession = await saveCurrentSession();
      let reportId = currentReportId;
      if (!reportId) {
        const created = await saveReport(buildClinicalReportPayload({
          patientId: urlPatientId,
          consultationId: savedSession?.consultationId || consultationId,
          appointmentId: savedSession?.appointmentId || appointmentId,
          toothId: null,
          toothStatus: null,
          symptoms: Array.isArray(savedSession?.symptoms) ? savedSession.symptoms : reportSymptoms,
          doctorNotes: sessionNote,
          aiDraftReport: reportMode === 'ai' ? aiReportDraft : '',
          finalMedicalReport: previewReport,
          status: 'approved',
        }));
        reportId = created.id;
        setCurrentReportId(reportId);
      }
      const finalized = await finalizeReport(reportId, reviewedAssessments, reviewedSummary, previewReport);
      setFinalizedSnapshot(finalized.reportSnapshot);
      setReportStep('finalized');
      showToast('Medical report finalized and locked', 'success');
    } catch (err) {
      showToast(err?.message || 'Failed to save report', 'error');
    }
    finally { setIsSaving(false); }
  };

  const handleFinishSession = async () => {
    if (!isConsultationActive) {
      setIsConsultationActive(true);
      return;
    }
    if (!completeAppointmentByPatient || !patient || finishInFlightRef.current) return;
    if (prescriptionWorkflow.reviewRequired) {
      medicationSectionRef.current?.scrollIntoView({ behavior: 'smooth', block: 'center' });
      showToast('Review and approve the Prescription Draft before finishing.', 'error');
      return;
    }
    finishInFlightRef.current = true;
    setIsFinishing(true);
    try {
      const finalNote = noteDraftDirty ? noteDraft : undefined;
      await ensureConsultationInitialized();
      await flushBeforeFinish(finalNote);
      await consultationLabs.flushBeforeFinish();
      await completeAppointmentByPatient(patient.id, appointmentId);
      markConsultationFinished();
      setIsConsultationActive(false);
      showToast("Consultation finished successfully.", 'success');
    } catch (err) {
      cancelFinishBarrier();
      showToast(err?.message || 'The consultation could not be finished.', 'error');
    } finally {
      finishInFlightRef.current = false;
      setIsFinishing(false);
    }
  };

  const handleSavePatient = async () => {
    setIsSavingPatient(true);
    const mappedEdits = { ...patientEdits };
    if (mappedEdits.bloodType) {
      mappedEdits.blood_type = mappedEdits.bloodType;
      delete mappedEdits.bloodType;
    }
    const updated = await updatePatient(patient.id, mappedEdits);
    setIsSavingPatient(false);
    if (updated) {
      setPatient(updated);
      showToast('Patient info updated', 'success');
      setEditingPatient(false);
    } else {
      showToast('Failed to update patient info', 'error');
    }
  };

  // ── Guards ──
  if (isPageLoading || loading) return (
    <Layout pageTitle="Clinical Consultation" pageSubtitle="Loading...">
      <div className="card" style={{ textAlign: 'center', padding: '80px 20px' }}>
        <Loader2 size={32} className="animate-spin" style={{ margin: '0 auto 16px', color: 'var(--clr-primary)' }} />
        <p style={{ fontSize: '1rem', fontWeight: 600 }}>Initializing Clinical Workspace...</p>
      </div>
    </Layout>
  );

  if (!patient || persistenceMode === 'error') return (
    <Layout pageTitle="Clinical Consultation" pageSubtitle="Error">
      <div className="card" style={{ textAlign: 'center', padding: '60px 20px', maxWidth: 500, margin: '40px auto' }}>
        <AlertCircle size={40} style={{ color: 'var(--clr-danger)', marginBottom: 16 }} />
        <h2 style={{ marginBottom: 8 }}>Consultation Unavailable</h2>
        <p style={{ color: 'var(--clr-subtext)', marginBottom: 24 }}>
          {!patient ? 'Patient record not found.' : (consultationError || 'The consultation could not be loaded.')}
        </p>
        <div style={{ display: 'flex', gap: 10, justifyContent: 'center' }}>
          <button className="btn btn-secondary" onClick={() => navigate('/doctor/patients')}>Back</button>
          <button className="btn btn-primary" onClick={() => window.location.reload()}>Retry</button>
        </div>
      </div>
    </Layout>
  );

  return (
    <Layout pageTitle="Clinical Consultation" pageSubtitle="Guided clinical workflow">
      <div className="consultation-page animate-fadeIn">

        <PreviousConsultationNoteCurtain previousNote={lastConsultationNote} />

        {/* ── Patient Header ── */}
        <section className="card" style={{ padding: 20, marginBottom: 20 }}>
          <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: 16 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
              <button className="btn btn-secondary btn-sm" onClick={() => navigate('/doctor/patients')} style={{ padding: 8 }}><ArrowLeft size={16} /></button>
              <div className="avatar" style={{ width: 44, height: 44, fontSize: '1rem' }}>{initials}</div>
              <div>
                <h2 style={{ margin: 0, fontSize: '1.25rem', fontWeight: 800, display: 'flex', alignItems: 'center', gap: 10 }}>
                  {fullName}
                  <span className={`badge ${persistenceMode === 'api' ? 'badge-success' : 'badge-danger'}`} style={{ fontSize: '0.65rem' }}>
                    {persistenceMode === 'api' ? '☁ Database' : '⚠ Database unavailable'}
                  </span>
                </h2>
                <p style={{ margin: 0, fontSize: '0.8rem', color: 'var(--clr-subtext)' }}>
                  ID: {patient.id} • {patient.gender || 'N/A'} • {patient.age ? `${patient.age}y` : 'N/A'}
                </p>
              </div>
            </div>
            <div style={{ display: 'flex', gap: 8 }}>
              <button
                className="btn btn-secondary btn-sm"
                onClick={() => setShowProcedures(true)}
                disabled={!isConsultationActive}
                style={{ display: 'flex', alignItems: 'center', gap: 4 }}
              >
                <ReceiptText size={13} /> {procedureSummaryError
                  ? 'Procedures unavailable'
                  : `Procedures (${procedureSummary.items.length}) · ${formatMoney(decimalToCents(procedureSummary.total))}`}
              </button>
              <button
                type="button"
                className="btn btn-secondary btn-sm"
                onClick={() => setShowLabProducts(true)}
                disabled={!isConsultationActive}
                aria-haspopup="dialog"
                style={{ display: 'flex', alignItems: 'center', gap: 4 }}
              >
                <FlaskConical size={13} /> Lab Product ({consultationLabs.items.length}){consultationLabs.dirty ? ' · Unsaved' : ''}
              </button>
              <button
                className="btn btn-secondary btn-sm"
                onClick={openConsultationNote}
                disabled={!isConsultationActive}
                style={{ display: 'flex', alignItems: 'center', gap: 4 }}
              >
                <ClipboardList size={13} /> Consultation Note
              </button>
              <button className="btn btn-secondary btn-sm" onClick={() => setEditingPatient(!editingPatient)} style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
                <Edit3 size={13} /> {editingPatient ? 'Close' : 'Edit Info'}
              </button>
              <button className={`btn btn-sm ${isConsultationActive ? 'btn-primary' : 'btn-secondary'}`} onClick={handleFinishSession} disabled={isFinishing}>
                {isFinishing ? <><Loader2 size={14} className="animate-spin" /> Saving...</> : isConsultationActive ? <><ShieldCheck size={14} /> Finish</> : <><CheckCircle2 size={14} /> Done</>}
              </button>
            </div>
          </div>

          {/* Patient Info Grid / Edit */}
          {editingPatient ? (
            <div style={{ marginTop: 14, padding: 14, background: 'var(--clr-bg)', borderRadius: 10, border: '1px solid var(--clr-border)' }}>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(160px, 1fr))', gap: 10 }}>
                <div className="form-group" style={{ marginBottom: 0 }}>
                  <label className="form-label" style={{ fontSize: '0.7rem' }}>Phone</label>
                  <input className="form-input" type="text" value={patientEdits.phone || ''} onChange={e => setPatientEdits(p => ({ ...p, phone: e.target.value }))} style={{ padding: '6px 10px', fontSize: '0.82rem' }} />
                </div>
                <div className="form-group" style={{ marginBottom: 0 }}>
                  <label className="form-label" style={{ fontSize: '0.7rem' }}>Age</label>
                  <input className="form-input" type="number" min="0" max="150" value={patientEdits.age || ''} onChange={e => setPatientEdits(p => ({ ...p, age: e.target.value }))} style={{ padding: '6px 10px', fontSize: '0.82rem' }} />
                </div>
                <div className="form-group" style={{ marginBottom: 0 }}>
                  <label className="form-label" style={{ fontSize: '0.7rem' }}>Gender</label>
                  <select className="form-select" value={patientEdits.gender || 'Unknown'} onChange={e => setPatientEdits(p => ({ ...p, gender: e.target.value }))} style={{ padding: '6px 10px', fontSize: '0.82rem', width: '100%' }}>
                    <option value="Male">Male</option>
                    <option value="Female">Female</option>
                    <option value="Other">Other</option>
                    <option value="Unknown">Unknown</option>
                  </select>
                </div>
                <div className="form-group" style={{ marginBottom: 0 }}>
                  <label className="form-label" style={{ fontSize: '0.7rem' }}>Blood Type</label>
                  <select className="form-select" value={patientEdits.bloodType || 'Unknown'} onChange={e => setPatientEdits(p => ({ ...p, bloodType: e.target.value }))} style={{ padding: '6px 10px', fontSize: '0.82rem', width: '100%' }}>
                    {['Unknown', 'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'].map(bt => (
                      <option key={bt} value={bt}>{bt}</option>
                    ))}
                  </select>
                </div>
              </div>
              <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: 14 }}>
                <button className="btn btn-primary btn-sm" onClick={handleSavePatient} disabled={isSavingPatient} style={{ fontSize: '0.75rem', gap: 6 }}>
                  {isSavingPatient ? <Loader2 size={12} className="animate-spin" /> : <Save size={12} />} Save Changes
                </button>
              </div>
            </div>
          ) : (
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(140px, 1fr))', gap: 12, marginTop: 14, padding: 14, background: 'var(--clr-bg)', borderRadius: 10, border: '1px solid var(--clr-border)' }}>
              {[
                { label: 'Phone', val: patient.phone || '—', icon: Phone },
                { label: 'Age & Gender', val: (patient.age || patient.gender) ? `${patient.age ? patient.age+'y' : ''}${patient.age && patient.gender ? ', ' : ''}${patient.gender || ''}` : '—', icon: User },
                { label: 'Blood Type', val: patient.bloodType || patient.blood_type || '—', color: (patient.bloodType || patient.blood_type) && (patient.bloodType || patient.blood_type) !== 'Unknown' ? 'var(--clr-danger)' : 'inherit', icon: Droplets },
                { label: 'Status', val: patient.status || 'Active', color: 'var(--clr-success)', icon: CheckCircle2 },
              ].map(f => (
                <div key={f.label} style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
                  <div style={{ width: 32, height: 32, borderRadius: 8, background: 'white', border: '1px solid var(--clr-border)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--clr-primary)' }}>
                    <f.icon size={16} />
                  </div>
                  <div>
                    <span style={{ fontSize: '0.65rem', color: 'var(--clr-subtext)', textTransform: 'uppercase', fontWeight: 700, letterSpacing: '0.05em' }}>{f.label}</span>
                    <p style={{ margin: '0', fontWeight: 700, fontSize: '0.85rem', color: f.color || 'var(--clr-text)' }}>{f.val}</p>
                  </div>
                </div>
              ))}
            </div>
          )}
        </section>

        {consultationError && persistenceMode === 'api' && (
          <section className="card" style={{ padding: 14, marginBottom: 20, borderLeft: '4px solid var(--clr-danger)', color: 'var(--clr-danger)' }}>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12, flexWrap: 'wrap' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 9 }}>
                <AlertCircle size={17} />
                <span style={{ fontSize: '0.82rem', fontWeight: 700 }}>{consultationError}</span>
              </div>
              {consultationError.includes('VERSION_CONFLICT') && (
                <button className="btn btn-secondary btn-sm" onClick={handleRetryConsultationSave}>
                  Retry my changes
                </button>
              )}
            </div>
          </section>
        )}

        {/* Toast */}
        {toast && (
          <div style={{ position: 'fixed', bottom: 24, left: '50%', transform: 'translateX(-50%)', background: toast.type === 'error' ? '#dc2626' : '#1e293b', color: '#fff', padding: '10px 22px', borderRadius: 20, boxShadow: '0 8px 20px rgba(0,0,0,0.2)', zIndex: 2000, display: 'flex', alignItems: 'center', gap: 8, fontSize: '0.88rem', fontWeight: 600 }} className="animate-slideUp">
            {toast.type === 'success' ? <CheckCircle2 size={15} /> : toast.type === 'error' ? <AlertCircle size={15} /> : <Loader2 size={15} />}
            {toast.msg}
          </div>
        )}

        {showConsultationNote && (
          <div
            className="modal-overlay"
            onClick={() => !isSavingNote && setShowConsultationNote(false)}
            style={{ position: 'fixed', inset: 0, zIndex: 10000, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 20, background: 'rgba(15,23,42,0.55)', backdropFilter: 'blur(4px)' }}
          >
            <div className="card animate-fadeIn" onClick={event => event.stopPropagation()} style={{ width: '100%', maxWidth: 620, padding: 0, overflow: 'hidden', borderRadius: 16 }}>
              <div style={{ padding: '18px 22px', borderBottom: '1px solid var(--clr-border)', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                <div>
                  <h2 style={{ margin: 0, fontSize: '1.05rem', fontWeight: 800 }}>Consultation Note</h2>
                  <p style={{ margin: '3px 0 0', color: 'var(--clr-subtext)', fontSize: '0.76rem' }}>General notes for this consultation</p>
                </div>
                <button disabled={isSavingNote} onClick={() => setShowConsultationNote(false)} style={{ border: 'none', background: 'transparent', cursor: 'pointer', color: 'var(--clr-subtext)' }}><X size={19} /></button>
              </div>
              <div style={{ padding: 22 }}>
                <textarea
                  autoFocus
                  className="form-input consultation-textarea"
                  value={noteDraft}
                  onChange={event => { setNoteDraft(event.target.value); setNoteDraftDirty(true); }}
                  placeholder="Document general observations, follow-up guidance, or context for the next visit..."
                  rows={9}
                  style={{ width: '100%', minHeight: 210, resize: 'vertical', whiteSpace: 'pre-wrap' }}
                />
                {noteError && (
                  <div style={{ marginTop: 10, padding: '9px 12px', borderRadius: 8, background: '#fef2f2', color: '#b91c1c', fontSize: '0.78rem', fontWeight: 600, display: 'flex', gap: 7, alignItems: 'center' }}>
                    <AlertCircle size={14} /> {noteError}
                  </div>
                )}
              </div>
              <div style={{ padding: '14px 22px', borderTop: '1px solid var(--clr-border)', display: 'flex', justifyContent: 'flex-end', gap: 10 }}>
                <button className="btn btn-secondary" disabled={isSavingNote} onClick={() => setShowConsultationNote(false)}>Cancel</button>
                <button className="btn btn-primary" disabled={isSavingNote || persistenceMode !== 'api'} onClick={handleSaveConsultationNote}>
                  {isSavingNote ? <Loader2 size={15} className="animate-spin" /> : <Save size={15} />} Save Note
                </button>
              </div>
            </div>
          </div>
        )}

        {showProcedures && (
          <ProcedureSelector
            patientId={urlPatientId}
            onClose={() => setShowProcedures(false)}
            onSaved={result => {
              setProcedureSummary(result);
              showToast('Performed procedures saved', 'success');
            }}
          />
        )}

        {showLabProducts && (
          <LabProductSelector
            items={consultationLabs.items}
            labNote={consultationLabs.labNote}
            loading={consultationLabs.loading}
            saving={consultationLabs.saving}
            error={consultationLabs.error}
            onAdd={consultationLabs.addProduct}
            onQuantity={consultationLabs.setQuantity}
            onRemove={consultationLabs.removeItem}
            onNote={consultationLabs.setLabNote}
            onClose={() => setShowLabProducts(false)}
            onSave={async () => {
              try {
                await consultationLabs.save();
                setShowLabProducts(false);
                showToast('Lab items saved', 'success');
              } catch (saveError) {
                showToast(saveError?.message || 'Lab items could not be saved.', 'error');
              }
            }}
          />
        )}

        {consultationLabs.items.length > 0 && (
          <section className="card" style={{ padding: 18, marginBottom: 20 }} aria-label="Lab Items summary">
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12 }}><div><p className="section-kicker">Current consultation</p><h3 style={{ margin: 0 }}>Lab Items</h3></div>{consultationLabs.dirty && <span className="badge" style={{ color: 'var(--clr-subtext)' }}>Draft · current catalog price</span>}</div>
            <div style={{ display: 'grid', gap: 14, marginTop: 14 }}>{consultationLabs.groups.map(group => <div key={group.labId}><strong>{group.labName}</strong>{group.items.map(item => { const unitCents = decimalToCents(item.displayPrice); const totalCents = item.isSavedSnapshot && item.totalAmount != null ? decimalToCents(item.totalAmount) : unitCents * item.quantity; return <div key={item.labProductId} style={{ display: 'grid', gridTemplateColumns: 'minmax(0,1fr) auto', gap: 12, padding: '7px 0', borderBottom: '1px solid var(--clr-border)' }}><span>{item.productName} × {item.quantity}<small style={{ display: 'block', color: 'var(--clr-subtext)' }}>{item.isSavedSnapshot ? 'Saved snapshot' : 'Draft · current price'} · Unit Price: {formatMoney(unitCents)}</small></span><strong>{formatMoney(totalCents)}</strong></div>; })}</div>)}</div>
            {consultationLabs.labNote && <div style={{ marginTop: 14 }}><strong>Lab Note</strong><p style={{ margin: '4px 0 0', whiteSpace: 'pre-wrap' }}>{consultationLabs.labNote}</p></div>}
          </section>
        )}

        {/* ── Workspace ── */}
        <section className="consultation-workspace">
          {/* 3D Model */}
          <div className="consultation-chart-card clinic-card">
            <div className="consultation-card-head">
              <div><p className="section-kicker">Step 1</p><h3>Select a tooth</h3></div>
              <div className="consultation-segmented">
                {['both', 'upper', 'lower'].map(m => (
                  <button key={m} className={viewMode === m ? 'is-selected' : ''} onClick={() => setViewMode(m)}>{m}</button>
                ))}
              </div>
            </div>
            <div className="consultation-model-wrap">
              <Dental3DModel toothData={toothData} selectedToothId={selectedToothId} onToothSelect={selectTooth} viewMode={viewMode} showNumbers />
              {!isConsultationActive && <div className="consultation-locked">Session completed</div>}
            </div>
            {/* Legend */}
            <div style={{ display: 'flex', gap: 14, padding: '10px 16px', flexWrap: 'wrap' }}>
              {CLINICAL_STATUSES.map(s => (
                <span key={s.id} style={{ display: 'flex', alignItems: 'center', gap: 5, fontSize: '0.72rem', fontWeight: 700, color: 'var(--clr-subtext)' }}>
                  <span style={{ width: 10, height: 10, borderRadius: 3, background: s.color, border: '1px solid rgba(0,0,0,0.1)' }} />
                  {s.label}: <strong style={{ color: 'var(--clr-text)' }}>{stats[s.id] || 0}</strong>
                </span>
              ))}
            </div>

            <div style={{ margin: '10px 16px 18px', padding: 16, border: '1px solid var(--clr-border)', borderRadius: 12, background: 'var(--clr-bg)' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 10 }}>
                <div><p className="section-kicker">Current examination</p><h3 style={{ margin: 0 }}>Clinical Findings</h3></div>
                <span className="badge">{structuredFindings?.length || 0} teeth</span>
              </div>
              {clinicalFindingsByTooth === null && symptoms.length > 0 && (
                <div style={{ padding: 10, marginBottom: 10, borderRadius: 8, background: '#fff7ed', color: '#9a3412', fontSize: '0.78rem' }}>
                  Legacy consultation-level symptoms: {symptoms.join(', ')}. They are not assigned to any tooth.
                </div>
              )}
              {structuredFindings?.length ? (
                <div style={{ display: 'grid', gap: 8 }}>
                  {structuredFindings.map(finding => (
                    <div key={finding.toothId} style={{ padding: 11, borderRadius: 9, background: 'white', border: '1px solid var(--clr-border)', display: 'flex', justifyContent: 'space-between', gap: 12 }}>
                      <button type="button" onClick={() => selectTooth(finding.toothId)} style={{ flex: 1, textAlign: 'left', border: 0, background: 'transparent', cursor: 'pointer', color: 'var(--clr-text)' }}>
                        <strong>Tooth {finding.toothId}</strong>
                        <div style={{ marginTop: 4, fontSize: '0.76rem', color: 'var(--clr-subtext)' }}>Status: {finding.toothStatus}</div>
                        <div style={{ fontSize: '0.76rem', color: 'var(--clr-subtext)' }}>Symptoms: {finding.symptoms.length ? finding.symptoms.join(', ') : 'None'}</div>
                        {finding.toothNote && <div style={{ fontSize: '0.76rem', color: 'var(--clr-subtext)' }}>Note: {finding.toothNote}</div>}
                      </button>
                      <button type="button" className="icon-button" aria-label={`Remove Tooth ${finding.toothId} finding`} onClick={() => removeClinicalFinding(finding.toothId)} disabled={!isConsultationActive}><X size={15}/></button>
                    </div>
                  ))}
                </div>
              ) : (
                <p style={{ margin: 0, fontSize: '0.8rem', color: 'var(--clr-subtext)' }}>Edit a tooth status, symptoms, or note to add it.</p>
              )}
            </div>

            {reportStep !== 'finalized' && (
              <div role="tablist" aria-label="Report authoring mode" style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 4, width: 'min(100%, 360px)', margin: '16px auto 10px', padding: 4, borderRadius: 999, background: 'var(--clr-bg)', border: '1px solid var(--clr-border)' }}>
                {[
                  ['ai', 'AI Report'],
                  ['manual', 'Manual Report'],
                ].map(([mode, label]) => (
                  <button
                    key={mode}
                    type="button"
                    role="tab"
                    aria-selected={reportMode === mode}
                    onClick={() => setReportMode(mode)}
                    style={{ border: 0, borderRadius: 999, padding: '9px 14px', cursor: 'pointer', font: 'inherit', fontSize: '0.82rem', fontWeight: 750, color: reportMode === mode ? 'var(--clr-primary-dark)' : 'var(--clr-subtext)', background: reportMode === mode ? 'white' : 'transparent', boxShadow: reportMode === mode ? '0 2px 8px rgba(15,23,42,0.09)' : 'none', transition: 'background 180ms ease, color 180ms ease, box-shadow 180ms ease, transform 180ms ease', transform: reportMode === mode ? 'translateY(-1px)' : 'none' }}
                  >
                    {label}
                  </button>
                ))}
              </div>
            )}

            {reportMode === 'ai' && reportStep === 'input' && (
              <div style={{ margin: '10px 16px 18px', padding: 16, background: 'var(--clr-bg)', border: '1px solid var(--clr-primary)', borderRadius: 10 }}>
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12, marginBottom: 12 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 6, color: 'var(--clr-primary)', fontWeight: 800, fontSize: '0.9rem' }}>
                    <Brain size={18} /> AI Clinical Reporter
                  </div>
                  <button className="btn btn-primary btn-sm" onClick={() => handleGenerateReport()} disabled={!canGenerate || isGenerating || !isConsultationActive}
                    style={{ display: 'flex', alignItems: 'center', gap: 5 }}>
                    {isGenerating ? <><Loader2 size={13} className="animate-spin" /> Generating...</> : <><Sparkles size={13} /> Generate One Report</>}
                  </button>
                </div>
                <label className="form-label" htmlFor="ai-report-instructions">AI Instructions (Optional)</label>
                <textarea
                  id="ai-report-instructions"
                  className="consultation-textarea"
                  value={aiInstructions}
                  onChange={event => setAiInstructions(event.target.value)}
                  placeholder="Keep the report concise and emphasize the main clinical findings."
                  disabled={!isConsultationActive}
                  style={{ minHeight: 72, marginBottom: 8 }}
                />
                <p style={{ margin: 0, fontSize: '0.8rem', color: 'var(--clr-subtext)' }}>
                  {canGenerate ? `Ready to generate one report from all ${structuredFindings.length} clinical finding${structuredFindings.length === 1 ? '' : 's'}.` : 'Add at least one Clinical Finding to generate.'}
                </p>
              </div>
            )}

            {/* ── One report authoring area; only the active draft can finalize. ── */}
            {reportStep !== 'finalized' && (reportMode === 'manual' || reportStep === 'ai_review') && (
              <div style={{ padding: '12px 20px 24px', margin: '12px 0' }} className="animate-fadeIn">
                {reportMode === 'ai' ? (
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
                    {isEditingReport ? <textarea
                      className="consultation-textarea"
                      aria-label="Medical Dental Report Markdown"
                      value={aiReportDraft}
                      onChange={event => { setAiReportDraft(event.target.value); setHumanizedReport(''); }}
                      style={{ minHeight: 560, fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace', lineHeight: 1.6 }}
                    /> : <MedicalReportMarkdown markdown={aiReportDraft}/>}
                    <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap' }}>
                      <button className="btn btn-secondary" onClick={() => setIsEditingReport(current => !current)}>
                        <Edit3 size={15} /> {isEditingReport ? 'Done Editing' : 'Edit Manually'}
                      </button>
                      <button className="btn btn-secondary" onClick={() => handleGenerateReport(true)} disabled={isGenerating}>
                        <RefreshCw size={15} /> Regenerate AI Report
                      </button>
                      <button className="btn btn-secondary" onClick={handleHumanizeReport} disabled={isHumanizing || !aiReportDraft.trim()}>
                        {isHumanizing ? <Loader2 size={15} className="animate-spin"/> : <Heart size={15}/>} Humanize Report
                      </button>
                    </div>
                    {humanizedReport && (
                      <div style={{ padding: 16, border: '1px solid var(--clr-border)', borderRadius: 10, background: 'var(--clr-bg)' }}>
                        <h3 style={{ margin: '0 0 6px' }}>Patient-Friendly Derivative</h3>
                        <p style={{ margin: '0 0 12px', color: 'var(--clr-subtext)', fontSize: '0.8rem' }}>
                          Preview only. This does not replace the report selected for approval.
                        </p>
                        <MedicalReportMarkdown markdown={humanizedReport}/>
                      </div>
                    )}
                  </div>
                ) : (
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
                    <label className="form-label" htmlFor="manual-medical-report">Manual Medical Report</label>
                    <textarea
                      id="manual-medical-report"
                      className="consultation-textarea"
                      aria-label="Manual Medical Report Markdown"
                      value={manualReportDraft}
                      onChange={event => setManualReportDraft(event.target.value)}
                      placeholder="Write the clinical report here..."
                      style={{ minHeight: 420, fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace', lineHeight: 1.6 }}
                    />
                    {manualReportDraft.trim() && (
                      <div>
                        <p className="section-kicker" style={{ marginBottom: 8 }}>Preview</p>
                        <MedicalReportMarkdown markdown={manualReportDraft}/>
                      </div>
                    )}
                  </div>
                )}
                <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: 16 }}>
                  <button className="btn btn-primary" onClick={handleFinalizeReport} disabled={isSaving || !previewReport.trim()}>
                    {isSaving ? <Loader2 size={15} className="animate-spin"/> : <ShieldCheck size={15}/>} Approve &amp; Finalize
                  </button>
                </div>
              </div>
            )}

            {reportStep === 'finalized' && (
              <div style={{ padding: '12px 20px 24px', margin: '12px 0' }} className="animate-fadeIn">
                <MedicalReportMarkdown markdown={finalizedSnapshot?.finalNarrative || ''}/>
              </div>
            )}
          </div>

          {/* ── Clinical Panel ── */}
          <aside className="consultation-side-card clinic-card">
            {selectedToothId ? (
              <>
                {/* Step 2: Status */}
                <div className="consultation-card-head">
                  <div>
                    <p className="section-kicker">Step 2</p>
                    <h3>Record finding</h3>
                    <span className="consultation-tooth-name">#{selectedToothId} {selectedTooth?.name}</span>
                  </div>
                  <button className="icon-button" onClick={() => selectTooth(null)}><X size={16} /></button>
                </div>
                <div className="consultation-status-grid">
                  {CLINICAL_STATUSES.map(s => (
                    <button key={s.id} className={`choice-button ${selectedToothData?.status === s.id ? 'is-selected' : ''}`}
                      onClick={() => updateToothStatus(selectedToothId, s.id)} disabled={!isConsultationActive}>
                      <i className="color-dot" style={{ background: s.color }} />{s.label}
                    </button>
                  ))}
                </div>

                {/* Step 3: Symptoms */}
                <div className="consultation-section">
                  <div className="consultation-mini-head">
                    <p className="section-kicker">Step 3</p>
                    <h4>Symptoms & Findings</h4>
                  </div>
                  
                  {isSymptomsLoading ? (
                    <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: 10, background: '#f8fafc', borderRadius: 8 }}>
                      <Loader2 size={16} className="animate-spin" color="var(--clr-primary)" />
                      <span style={{ fontSize: '0.8rem', color: 'var(--clr-subtext)' }}>Loading clinical symptoms...</span>
                    </div>
                  ) : symptomsError ? (
                    <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: 10, color: 'var(--clr-danger)', fontSize: '0.8rem', fontWeight: 600 }}>
                      <AlertCircle size={15} /> {symptomsError}
                    </div>
                  ) : (
                    <SymptomDropdown 
                      options={availableSymptoms} 
                      selected={selectedSymptoms}
                      onToggle={toggleSymptom}
                      onAddCustom={handleAddCustomRequest}
                      disabled={!isConsultationActive}
                    />
                  )}

                  {/* Selected Chips */}
                  <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, marginTop: 12 }}>
                    {selectedSymptoms.map(s => (
                      <div key={s} 
                        style={{ 
                          background: 'white', 
                          border: '1px solid var(--clr-primary)', 
                          color: 'var(--clr-primary)', 
                          padding: '6px 12px', 
                          borderRadius: 20, 
                          fontSize: '0.75rem', 
                          fontWeight: 700,
                          display: 'flex',
                          alignItems: 'center',
                          gap: 6,
                          boxShadow: '0 2px 5px rgba(0,0,0,0.02)'
                        }}
                      >
                        {s}
                        <X 
                          size={12} 
                          style={{ cursor: 'pointer', opacity: 0.7 }} 
                          onClick={() => isConsultationActive && toggleSymptom(s)} 
                        />
                      </div>
                    ))}
                    {selectedSymptoms.length === 0 && !isSymptomsLoading && !symptomsError && (
                      <div style={{ fontSize: '0.75rem', color: 'var(--clr-subtext)', fontStyle: 'italic', padding: '4px 0' }}>
                        No symptoms selected yet.
                      </div>
                    )}
                  </div>
                </div>

                {/* Custom Symptom Confirmation Modal */}
                {showCustomModal && (
                  <div style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.4)', backdropFilter: 'blur(4px)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 1000 }}>
                    <div className="card animate-fadeIn" style={{ maxWidth: 400, padding: 24, borderRadius: 20 }}>
                      <div style={{ width: 48, height: 48, borderRadius: 14, background: 'rgba(var(--clr-primary-rgb), 0.1)', color: 'var(--clr-primary)', display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: 16 }}>
                        <PlusCircle size={24} />
                      </div>
                      <h3 style={{ marginBottom: 12 }}>Add Custom Symptom</h3>
                      <p style={{ color: 'var(--clr-subtext)', fontSize: '0.9rem', lineHeight: 1.6, marginBottom: 24 }}>
                        Do you want to save <strong>"{pendingCustomSymptom}"</strong> to the global symptoms list for future consultations?
                      </p>
                      <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                        <button className="btn btn-primary" style={{ width: '100%', height: 48 }} onClick={() => handleCustomSymptomAction(true)}>
                          Yes, save for future
                        </button>
                        <button className="btn btn-secondary" style={{ width: '100%', height: 48 }} onClick={() => handleCustomSymptomAction(false)}>
                          No, use only this session
                        </button>
                        <button className="btn btn-ghost" style={{ width: '100%' }} onClick={() => { setShowCustomModal(false); setPendingCustomSymptom(''); }}>
                          Cancel
                        </button>
                      </div>
                    </div>
                  </div>
                )}

                {/* Doctor Notes */}
                <div className="consultation-section">
                  <label className="form-label">Clinical Notes</label>
                  <textarea className="consultation-textarea" placeholder="Additional findings..."
                    value={selectedToothData?.notes || ''} onChange={e => updateToothNotes(selectedToothId, e.target.value)}
                    disabled={!isConsultationActive} style={{ minHeight: 50 }} />
                </div>

              </>
            ) : (
              <div className="consultation-empty-state">
                <Stethoscope size={42} />
                <h3>Select a tooth to begin</h3>
                <p>Click on any tooth in the 3D model to start recording findings.</p>
              </div>
            )}
            <MedicationSection
              sectionRef={medicationSectionRef}
              workflow={prescriptionWorkflow}
              disabled={!isConsultationActive}
            />
          </aside>
        </section>
      </div>
    </Layout>
  );
}
