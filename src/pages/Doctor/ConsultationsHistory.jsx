import React, { useState, useEffect } from 'react';
import { useSearchParams } from 'react-router-dom';
import Layout from '../../components/Layout';
import { useLanguage } from '../../context/LanguageContext';
import { useAuth } from '../../context/AuthContext';
import { 
  Search, Calendar, User, ClipboardList, Eye, 
  ArrowRight, FileText, Activity, AlertCircle, X, CheckCircle2, Edit3, Save, Clock, ChevronDown, ChevronUp, Sparkles, Loader2, Heart, ThumbsUp, ThumbsDown
} from 'lucide-react';
import { humanizeReport, updateReport } from '../../services/reportApi';
import { listDoctorConsultationHistory } from '../../services/consultationHistoryApi.js';
import { decimalToCents, formatMoney } from '../../config/money';
import FinalReportSnapshot from '../../components/consultation/FinalReportSnapshot.jsx';
import MedicalReportMarkdown from '../../components/consultation/MedicalReportMarkdown.jsx';
import ConsultationLabHistorySection from '../../components/consultation/ConsultationLabHistorySection.jsx';
import PrescriptionHistorySection from '../../components/consultation/PrescriptionHistorySection.jsx';

export default function ConsultationsHistory() {
  const [searchParams] = useSearchParams();
  const requestedConsultationId = searchParams.get('consultationId');
  const requestedPatientId = searchParams.get('patientId');
  const historicalReadOnly = Boolean(requestedConsultationId || requestedPatientId);
  const { t } = useLanguage();
  const { user } = useAuth();
  const [history, setHistory] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [search, setSearch] = useState('');
  const [expandedId, setExpandedId] = useState(null);

  useEffect(() => {
    let active = true;
    const run = async () => {
      await Promise.resolve();
      if (!active) return;
      setHistory([]);
      setError(null);
      setLoading(true);
      try {
        const data = await listDoctorConsultationHistory();
        if (!active) return;
        const scoped = requestedPatientId
          ? data.filter(item => String(item.patient_id) === requestedPatientId)
          : data;
        setHistory(scoped);
        const match = requestedConsultationId
          ? scoped.find(item => String(item.consultationId) === requestedConsultationId)
          : scoped[0];
        if (match) setExpandedId(match.id);
      } catch (err) {
        if (active) setError(err.message);
      } finally {
        if (active) setLoading(false);
      }
    };
    run();
    return () => { active = false; };
  }, [requestedConsultationId, requestedPatientId, user?.id]);

  const filtered = history.filter(h => 
    h.patient_name.toLowerCase().includes(search.toLowerCase()) ||
    (h.final_medical_report && h.final_medical_report.toLowerCase().includes(search.toLowerCase())) ||
    (h.sessionNote && h.sessionNote.toLowerCase().includes(search.toLowerCase())) ||
    (h.tooth_status && h.tooth_status.toLowerCase().includes(search.toLowerCase())) ||
    (h.tooth_id && h.tooth_id.toString().includes(search))
  );

  const handleUpdate = (updatedReport) => {
    setHistory(prev => prev.map(h => h.id === updatedReport.id ? { ...h, ...updatedReport } : h));
  };

  const toggleExpand = (id) => {
    setExpandedId(prev => (prev === id ? null : id));
  };

  return (
    <Layout pageTitle={t('consultationHistory')} pageSubtitle="Review and manage your previous clinical sessions.">
      <div className="page-stack animate-fadeIn">
        
        {/* Header Actions */}
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 24 }}>
          <div style={{ position: 'relative', width: '100%', maxWidth: 400 }}>
            <Search size={18} style={{ position: 'absolute', left: 14, top: '50%', transform: 'translateY(-50%)', color: 'var(--clr-text-muted)' }} />
            <input 
              className="form-input" 
              style={{ paddingLeft: 44, borderRadius: 14, height: 48, border: '1px solid var(--clr-border)' }}
              placeholder="Search by patient name, diagnosis, or tooth..." 
              value={search}
              onChange={e => setSearch(e.target.value)}
            />
          </div>
        </div>

        {loading ? (
          <div style={{ padding: 100, textAlign: 'center' }}>
            <div className="spinner" style={{ margin: '0 auto 20px' }}></div>
            <p style={{ color: 'var(--clr-text-muted)' }}>Loading history...</p>
          </div>
        ) : error ? (
          <div className="card" style={{ padding: 40, textAlign: 'center', border: '1px solid #fee2e2', background: '#fef2f2' }}>
            <AlertCircle size={40} color="#ef4444" style={{ marginBottom: 16 }} />
            <h3 style={{ color: '#991b1b', marginBottom: 8 }}>Error</h3>
            <p style={{ color: '#b91c1c' }}>{error}</p>
          </div>
        ) : filtered.length === 0 ? (
          <div className="card" style={{ padding: 60, textAlign: 'center' }}>
            <ClipboardList size={60} style={{ color: 'var(--clr-text-muted)', marginBottom: 20, opacity: 0.2 }} />
            <h3 style={{ marginBottom: 10 }}>No history found</h3>
            <p style={{ color: 'var(--clr-text-muted)' }}>You haven't completed any consultations yet or none match your search.</p>
          </div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
            {filtered.map(report => (
              <ExpandableConsultationCard 
                key={report.id} 
                report={report} 
                isExpanded={expandedId === report.id}
                onToggle={() => toggleExpand(report.id)}
                onUpdate={handleUpdate}
                readOnly={historicalReadOnly}
              />
            ))}
          </div>
        )}
      </div>
    </Layout>
  );
}

export function ExpandableConsultationCard({ report, isExpanded, onToggle, onUpdate, readOnly = false }) {
  const { formatDateTime } = useLanguage();
  const reportId = report.reportId
    || (!String(report.id || '').startsWith('consultation:') ? report.id : null);
  const hasReport = Boolean(reportId);
  const isStructuredFinalized = Boolean(report.reportSnapshot || report.finalizedAt);
  const [isEditing, setIsEditing] = useState(false);
  const [loading, setLoading] = useState(false);
  const [reportDraft, setReportDraft] = useState(report.final_medical_report || report.ai_draft_report || '');
  const [editError, setEditError] = useState('');
  const [editSuccess, setEditSuccess] = useState('');
  const [immutabilityLocked, setImmutabilityLocked] = useState(false);
  const [isHumanizing, setIsHumanizing] = useState(false);
  const [draftHumanizedReport, setDraftHumanizedReport] = useState(null);
  const savedReportText = report.final_medical_report || report.ai_draft_report || '';
  const isReportDirty = reportDraft !== savedReportText;
  const canEditReport = hasReport && !isStructuredFinalized && !immutabilityLocked;

  useEffect(() => {
    if (!isEditing) setReportDraft(savedReportText);
  }, [isEditing, savedReportText]);

  const beginReportEdit = () => {
    setReportDraft(savedReportText);
    setEditError('');
    setEditSuccess('');
    setIsEditing(true);
  };

  const handleHumanize = async (e) => {
    if (e) e.stopPropagation();
    if (!hasReport || !report.final_medical_report) {
      alert("Please provide a medical report first.");
      return;
    }
    setIsHumanizing(true);
    setDraftHumanizedReport(null);
    try {
      const result = await humanizeReport(report.final_medical_report, report.patient_name);
      setDraftHumanizedReport(result.humanized_report);
    } catch (err) {
      alert("Failed to humanize: " + err.message);
    } finally {
      setIsHumanizing(false);
    }
  };

  const approveHumanizedReport = async (approvedText) => {
    setLoading(true);
    try {
      await updateReport(reportId, { humanized_report: approvedText });
      
      onUpdate({ ...report, humanized_report: approvedText });
      setDraftHumanizedReport(null);
    } catch (err) {
      alert("Failed to save approved report: " + err.message);
    } finally {
      setLoading(false);
    }
  };

  const handleSave = async (e) => {
    e.stopPropagation();
    if (!canEditReport || !isReportDirty || loading) return;
    setLoading(true);
    setEditError('');
    setEditSuccess('');
    try {
      await updateReport(reportId, { final_medical_report: reportDraft });
      onUpdate({ ...report, final_medical_report: reportDraft });
      setIsEditing(false);
      setEditSuccess('Report changes saved.');
    } catch (err) {
      if (err?.code === 'REPORT_FINALIZED') {
        setImmutabilityLocked(true);
        setEditError('This report has been finalized and is read-only.');
      } else {
        setEditError(err?.message || 'Report changes could not be saved.');
      }
    } finally {
      setLoading(false);
    }
  };

  const cancelReportEdit = () => {
    if (isReportDirty && !window.confirm('Discard unsaved report changes?')) return;
    setReportDraft(savedReportText);
    setEditError('');
    setIsEditing(false);
  };



  return (
    <div className={`card transition-all ${isExpanded ? 'shadow-lg is-expanded' : 'hover-scale'}`} 
      style={{ 
        padding: 0, 
        overflow: 'hidden', 
        borderRadius: 20, 
        cursor: 'pointer',
        border: isExpanded ? '2px solid var(--clr-primary)' : '1px solid var(--clr-border)',
        transform: isExpanded ? 'none' : undefined,
        transition: 'all 0.3s cubic-bezier(0.4, 0, 0.2, 1)'
      }}
      onClick={onToggle}
    >
      {/* Compact Header */}
      <div style={{ padding: '20px 24px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
          <div style={{ width: 40, height: 40, borderRadius: 10, background: 'rgba(16, 185, 129, 0.1)', color: '#10b981', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <User size={20} />
          </div>
          <div>
            <div style={{ fontWeight: 800, fontSize: '0.95rem', color: 'var(--clr-text)' }}>{report.patient_name}</div>
            <div style={{ fontSize: '0.7rem', color: 'var(--clr-text-muted)', fontWeight: 600 }}>ID: {report.patientDisplayId || '—'}</div>
          </div>
          <div style={{ width: 1, height: 20, background: 'var(--clr-border)', margin: '0 4px' }} />
          <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: '0.75rem', color: '#64748b', fontWeight: 700 }}>
             <Clock size={14} style={{ color: 'var(--clr-primary)' }} />
             <span>{formatDateTime(report.created_at, 'full')}</span>
          </div>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <div style={{ display: 'flex', gap: 6 }}>
            <span className="badge" style={{ background: '#f1f5f9', color: '#64748b', fontSize: '0.65rem', fontWeight: 700, padding: '4px 8px' }}>{report.tooth_id ? `Tooth #${report.tooth_id}` : 'General Session'}</span>
            <span className="badge" style={{ background: 'rgba(16, 185, 129, 0.1)', color: '#10b981', fontSize: '0.65rem', fontWeight: 700, padding: '4px 8px', textTransform: 'uppercase' }}>{report.status}</span>
          </div>
          <div style={{ width: 32, height: 32, borderRadius: 8, background: isExpanded ? 'rgba(var(--clr-primary-rgb), 0.1)' : '#f8fafc', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            {isExpanded ? <ChevronUp size={18} color="var(--clr-primary)" /> : <ChevronDown size={18} color="var(--clr-text-muted)" />}
          </div>
        </div>
      </div>

      {!isExpanded && (
        <div style={{ padding: '0 24px 20px 80px' }}>
          <p style={{ 
            fontSize: '0.8rem', 
            color: 'var(--clr-text-muted)', 
            lineHeight: 1.4, 
            display: '-webkit-box', 
            WebkitLineClamp: 1, 
            WebkitBoxOrient: 'vertical', 
            overflow: 'hidden'
          }}>
            {report.final_medical_report || report.ai_draft_report || 'Clinical session completed.'}
          </p>
        </div>
      )}

      {/* Expanded Content */}
      {isExpanded && (
        <div style={{ padding: '0 24px 32px 24px' }} onClick={e => e.stopPropagation()}>
          <div style={{ height: 1, background: 'var(--clr-border)', marginBottom: 32 }} />
          
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: 24, marginBottom: 40 }}>
            <InfoBlock icon={User} label="Patient" value={report.patient_name} sub={`ID: ${report.patientDisplayId || '—'}`} color="#3b82f6" />
            <InfoBlock icon={Activity} label="Clinical Target" value={report.tooth_id ? `Tooth #${report.tooth_id}` : 'General Session'} sub={isEditing ? 'FDI Number (Locked)' : report.tooth_status} color="#8b5cf6" />
            <InfoBlock icon={CheckCircle2} label="Status" value={isEditing ? 'Editing...' : report.status.toUpperCase()} color="#10b981" />
          </div>

          <div className="page-stack" style={{ gap: 32 }}>
            <ConsultationLabHistorySection labItems={report.labItems} labNote={report.labNote} />
            <PrescriptionHistorySection prescription={report.prescription} />
            {isStructuredFinalized ? (
              <>
                <FinalReportSnapshot snapshot={report.reportSnapshot} />
                {report.humanized_report && (
                  <Section title="Humanized Report">
                    <MedicalReportMarkdown markdown={report.humanized_report} />
                  </Section>
                )}
              </>
            ) : isEditing ? (
              <>
                <div className="form-group">
                  <label className="form-label" htmlFor={`history-report-editor-${reportId}`}>Clinical Report Markdown</label>
                  <textarea
                    id={`history-report-editor-${reportId}`}
                    aria-label="Clinical Report Markdown"
                    className="form-input"
                    style={{ minHeight: 420, fontSize: '0.95rem', lineHeight: 1.65, fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace' }}
                    value={reportDraft}
                    onChange={event => setReportDraft(event.target.value)}
                    disabled={loading || immutabilityLocked}
                  />
                </div>

                {editError && <div className="alert alert-danger" role="alert">{editError}</div>}
                <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 12, marginTop: 16 }}>
                  <button className="btn btn-ghost" onClick={cancelReportEdit} disabled={loading}>Cancel</button>
                  <button className="btn btn-primary" onClick={handleSave} disabled={loading || !isReportDirty || immutabilityLocked} style={{ borderRadius: 12, height: 48, padding: '0 32px', fontWeight: 700 }}>
                    {loading ? 'Saving...' : 'Save Changes'}
                  </button>
                </div>
              </>
            ) : (
              <>
                {report.sessionNote && (
                  <Section title="Consultation Note">
                    <div style={{ padding: 18, borderRadius: 12, background: 'var(--clr-primary-light)', borderLeft: '4px solid var(--clr-primary)', whiteSpace: 'pre-wrap', lineHeight: 1.65, color: 'var(--clr-text)' }}>
                      {report.sessionNote}
                    </div>
                  </Section>
                )}
                {report.procedures?.length > 0 && (
                  <Section title="Performed Procedures">
                    <div style={{ border: '1px solid var(--clr-border)', borderRadius: 14, overflow: 'hidden' }}>
                      {report.procedures.map(item => (
                        <div key={item.id} style={{ display: 'grid', gridTemplateColumns: 'minmax(0,1fr) auto auto', gap: 16, padding: '12px 16px', borderBottom: '1px solid var(--clr-border)' }}>
                          <strong>{item.name}</strong>
                          <span style={{ color: 'var(--clr-subtext)' }}>{item.quantity} × {formatMoney(decimalToCents(item.unitPrice))}</span>
                          <strong>{formatMoney(decimalToCents(item.lineTotal))}</strong>
                        </div>
                      ))}
                      <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 16, padding: '13px 16px', background: 'var(--clr-primary-light)' }}>
                        <span>Total</span>
                        <strong>{formatMoney(report.procedures.reduce((sum, item) => sum + decimalToCents(item.lineTotal), 0))}</strong>
                      </div>
                    </div>
                  </Section>
                )}
                {Array.isArray(report.clinicalFindings) ? (
                  <Section title="Clinical Findings">
                    <ClinicalFindingsReadOnly findings={report.clinicalFindings} />
                  </Section>
                ) : (
                  <Section title="Legacy Consultation Symptoms">
                    <div style={{ display: 'flex', flexWrap: 'wrap', gap: 10, marginTop: 4 }}>
                      {report.symptoms?.length > 0 ? report.symptoms.map((s, i) => (
                        <span key={i} className="badge" style={{ background: 'white', border: '1px solid var(--clr-border)', color: 'var(--clr-text)', padding: '6px 12px', fontSize: '0.8rem', fontWeight: 600 }}>{s}</span>
                      )) : <p style={{ color: 'var(--clr-text-muted)', fontSize: '0.9rem' }}>No legacy consultation-level symptoms recorded.</p>}
                    </div>
                  </Section>
                )}

                {report.doctor_notes && (
                  <Section title="Doctor Personal Notes">
                    <div style={{ padding: 20, borderRadius: 16, background: '#f8fafc', border: '1px solid var(--clr-border)' }}>
                      <p style={{ fontSize: '0.925rem', lineHeight: 1.7, color: 'var(--clr-text)' }}>{report.doctor_notes}</p>
                    </div>
                  </Section>
                )}

                <Section title="Final Saved Clinical Report">
                  <div style={{ padding: 24, borderRadius: 20, background: 'rgba(16, 185, 129, 0.03)', border: '1px solid rgba(16, 185, 129, 0.1)', position: 'relative' }}>
                    <FileText size={24} style={{ position: 'absolute', right: 24, top: 24, opacity: 0.1, color: '#10b981' }} />
                    {report.final_medical_report
                      ? <MedicalReportMarkdown markdown={report.final_medical_report} />
                      : <p>No final report content was saved for this session.</p>}
                  </div>
                </Section>

                {hasReport && (report.humanized_report || (canEditReport && (report.ai_draft_report || !report.humanized_report || draftHumanizedReport))) && (
                  <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))', gap: 24 }}>
                    {report.humanized_report ? (
                      <Section title="Humanized Patient View">
                        <div style={{ padding: 24, borderRadius: 20, background: 'rgba(59, 130, 246, 0.04)', border: '1px solid rgba(59, 130, 246, 0.1)', position: 'relative' }}>
                           <Heart size={20} style={{ position: 'absolute', right: 20, top: 20, color: '#3b82f6', opacity: 0.2 }} />
                           <MedicalReportMarkdown markdown={report.humanized_report} />
                        </div>
                      </Section>
                    ) : draftHumanizedReport ? (
                      <Section title="Review AI Humanization">
                        <div className="animate-fadeIn" style={{ padding: 24, borderRadius: 20, background: 'rgba(16, 185, 129, 0.04)', border: '2px dashed var(--clr-primary)' }}>
                           <p style={{ 
                             fontSize: '1.05rem', 
                             lineHeight: 1.8, 
                             color: 'var(--clr-text)', 
                             fontStyle: 'italic', 
                             fontFamily: '"Outfit", sans-serif',
                             fontWeight: 500,
                             marginBottom: 20
                           }}>
                             "{draftHumanizedReport}"
                           </p>
                           <div style={{ display: 'flex', gap: 12, justifyContent: 'center', paddingTop: 16, borderTop: '1px solid rgba(16,185,129,0.1)' }}>
                              <button 
                                className="btn btn-sm btn-primary" 
                                style={{ height: 40, padding: '0 20px', borderRadius: 10, gap: 8 }}
                                onClick={() => approveHumanizedReport(draftHumanizedReport)}
                                disabled={loading}
                              >
                                <ThumbsUp size={16} /> Approve & Save
                              </button>
                              <button 
                                className="btn btn-sm btn-ghost" 
                                style={{ height: 40, padding: '0 20px', borderRadius: 10, gap: 8, color: 'var(--clr-danger)' }}
                                onClick={() => setDraftHumanizedReport(null)}
                                disabled={loading}
                              >
                                <ThumbsDown size={16} /> Discard
                              </button>
                           </div>
                        </div>
                      </Section>
                    ) : (
                      <Section title="Humanized Patient View">
                        <div style={{ 
                          padding: 24, 
                          borderRadius: 20, 
                          background: 'rgba(255, 107, 107, 0.03)', 
                          border: '1px dashed rgba(255, 107, 107, 0.2)',
                          textAlign: 'center'
                        }}>
                          <Heart size={24} style={{ color: '#ff6b6b', opacity: 0.5, marginBottom: 12 }} />
                          <p style={{ fontSize: '0.85rem', color: 'var(--clr-text-muted)', marginBottom: 16 }}>
                            No patient-friendly explanation found for this session.
                          </p>
                          <button 
                            className="btn btn-sm" 
                            style={{ background: 'rgba(255, 107, 107, 0.1)', color: '#ff6b6b', border: 'none', gap: 6 }}
                            onClick={handleHumanize}
                            disabled={isHumanizing || !report.final_medical_report}
                          >
                            {isHumanizing ? <><Loader2 size={14} className="animate-spin" /> Generating...</> : <><Sparkles size={14} /> Generate for Patient</>}
                          </button>
                        </div>
                      </Section>
                    )}
                    {report.ai_draft_report && !report.final_medical_report && (
                      <Section title="Original AI Draft">
                        <div style={{ padding: 20, borderRadius: 16, background: '#f8fafc', border: '1px solid var(--clr-border)' }}>
                           <p style={{ fontSize: '0.9rem', lineHeight: 1.7, color: 'var(--clr-text-muted)' }}>
                             {report.ai_draft_report}
                           </p>
                        </div>
                      </Section>
                    )}
                  </div>
                )}

                <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 12, marginTop: 16 }}>
                  {editSuccess && <span role="status" style={{ alignSelf: 'center', color: 'var(--clr-success)', marginRight: 'auto' }}>{editSuccess}</span>}
                  {canEditReport && (
                    <button
                      className="btn btn-secondary"
                      aria-label={readOnly ? 'Edit historical clinical report' : 'Edit clinical report'}
                      style={{ borderRadius: 12, height: 48, gap: 8 }}
                      onClick={beginReportEdit}
                    >
                      <Edit3 size={18} /> Edit Report
                    </button>
                  )}
                  <button className="btn btn-ghost" onClick={onToggle}>Collapse Card</button>
                </div>
              </>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

function InfoBlock({ icon: Icon, label, value, sub, color }) {
  return (
    <div style={{ display: 'flex', gap: 16 }}>
      <div style={{ width: 52, height: 52, borderRadius: 16, background: 'white', border: '1px solid var(--clr-border)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: color || 'var(--clr-primary)', boxShadow: '0 4px 12px rgba(0,0,0,0.03)' }}>
        <Icon size={24} />
      </div>
      <div>
        <div style={{ fontSize: '0.75rem', color: 'var(--clr-text-muted)', fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.05em', marginBottom: 4 }}>{label}</div>
        <div style={{ fontSize: '1.1rem', fontWeight: 800, color: 'var(--clr-text)' }}>{value}</div>
        {sub && <div style={{ fontSize: '0.8rem', color: 'var(--clr-text-muted)', fontWeight: 500 }}>{sub}</div>}
      </div>
    </div>
  );
}

function ClinicalFindingsReadOnly({ findings }) {
  if (findings.length === 0) {
    return <p style={{ color: 'var(--clr-text-muted)' }}>No tooth findings were recorded.</p>;
  }
  return (
    <div style={{ display: 'grid', gap: 10 }}>
      {findings.map(finding => (
        <div key={finding.toothId} style={{ padding: 14, border: '1px solid var(--clr-border)', borderRadius: 12, background: '#fff' }}>
          <strong>Tooth {finding.toothId}</strong>
          <div style={{ marginTop: 5, fontSize: '0.84rem' }}>Status: {finding.toothStatus}</div>
          <div style={{ fontSize: '0.84rem' }}>Symptoms: {finding.symptoms?.length ? finding.symptoms.join(', ') : 'None'}</div>
          <div style={{ fontSize: '0.84rem', whiteSpace: 'pre-wrap' }}>Tooth Note: {finding.toothNote || 'None'}</div>
        </div>
      ))}
    </div>
  );
}

function Section({ title, children }) {
  return (
    <div>
      <h3 style={{ fontSize: '0.85rem', fontWeight: 800, textTransform: 'uppercase', letterSpacing: '0.1em', color: 'var(--clr-text-muted)', display: 'flex', alignItems: 'center', gap: 10, marginBottom: 16 }}>
        <span style={{ height: 1, flex: 1, background: 'var(--clr-border)' }} />
        {title}
        <span style={{ height: 1, flex: 1, background: 'var(--clr-border)' }} />
      </h3>
      {children}
    </div>
  );
}
