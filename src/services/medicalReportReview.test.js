import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { serializeReviewedAssessments } from './medicalReportReview.js';

const findings = [
  { toothId: '11', toothStatus: 'problem', symptoms: ['Pain'], toothNote: 'Deep lesion' },
  { toothId: '24', toothStatus: 'healthy', symptoms: [], toothNote: '' },
];
test('Migration 020 receives one null structured assessment per finding beside the Markdown narrative', () => {
  const state = Object.fromEntries(findings.map(item => [item.toothId, {
    clinicalDescription: null, diagnosis: null, icd10: null, treatmentPlan: null,
  }]));
  const assessments = serializeReviewedAssessments(findings, state);
  assert.deepEqual(assessments.map(item => item.toothId), ['11', '24']);
  assert.ok(assessments.every(item => item.clinicalDescription === null
    && item.diagnosis === null && item.icd10 === null && item.treatmentPlan === null));
});

test('Doctor review is one Markdown preview or one whole-report textarea', () => {
  const flow = readFileSync(new URL('../pages/Doctor/ConsultationFlow.jsx', import.meta.url), 'utf8');
  const renderer = readFileSync(new URL('../components/consultation/MedicalReportMarkdown.jsx', import.meta.url), 'utf8');
  assert.match(flow, /MedicalReportMarkdown markdown=\{aiReportDraft\}/);
  assert.match(flow, /aria-label="Medical Dental Report Markdown"/);
  assert.equal((flow.match(/aria-label="Medical Dental Report Markdown"/g) || []).length, 1);
  assert.match(flow, /Edit Manually/);
  assert.match(flow, /Done Editing/);
  assert.match(flow, /Regenerate AI Report/);
  assert.match(flow, /Humanize Report/);
  assert.match(flow, /humanizeReport\(aiReportDraft, fullName\)/);
  assert.match(flow, /Patient-Friendly Derivative/);
  assert.match(flow, /does not replace the report selected for approval/);
  assert.match(flow, /Approve &amp; Finalize/);
  assert.match(flow, /Regenerating the AI report will replace your manual edits\. Continue\?/);
  assert.doesNotMatch(flow, /ProfessionalDentalReport|DoctorReportReview|onAssessmentEdit/);
  assert.doesNotMatch(flow, /AI-generated Medical Report — Doctor review required|#fef3c7/);
  assert.doesNotMatch(flow, /dateOfBirth|date_of_birth/);
  assert.doesNotMatch(renderer, /input|textarea|button|Consultation Note/);
});

test('Markdown renderer supports the exact professional findings table layout', () => {
  const renderer = readFileSync(new URL('../components/consultation/MedicalReportMarkdown.jsx', import.meta.url), 'utf8');
  assert.match(renderer, /medical-report-table/);
  assert.match(renderer, /borderCollapse: 'collapse'/);
  assert.match(renderer, /\['14%', '38%', '18%', '30%'\]/);
  assert.match(renderer, /padding: '14px'/);
  assert.match(renderer, /borderBottom: '1px solid var\(--clr-border\)'/);
});

test('finalized history displays stored finalNarrative and legacy branches remain', () => {
  const snapshot = readFileSync(new URL('../components/consultation/FinalReportSnapshot.jsx', import.meta.url), 'utf8');
  const history = readFileSync(new URL('../pages/Doctor/ConsultationsHistory.jsx', import.meta.url), 'utf8');
  const patientHistory = readFileSync(new URL('../components/PatientModals.jsx', import.meta.url), 'utf8');
  assert.match(snapshot, /const finalNarrative = snapshot\?\.finalNarrative/);
  assert.match(snapshot, /<MedicalReportMarkdown markdown=\{finalNarrative\} \/>/);
  assert.doesNotMatch(snapshot, /<pre|<textarea|whiteSpace|dangerouslySetInnerHTML/);
  assert.match(history, /isStructuredFinalized \?/);
  assert.match(history, /FinalReportSnapshot/);
  assert.match(patientHistory, /FinalReportSnapshot/);
});

test('history Markdown renderer converts headings and findings pipes into semantic elements', () => {
  const renderer = readFileSync(new URL('../components/consultation/MedicalReportMarkdown.jsx', import.meta.url), 'utf8');
  assert.match(renderer, /line\.startsWith\('# '\)/);
  assert.match(renderer, /<h1/);
  assert.match(renderer, /line\.startsWith\('## '\)/);
  assert.match(renderer, /<h2/);
  assert.match(renderer, /line\.startsWith\('\|'\)/);
  assert.match(renderer, /<table className="medical-report-table"/);
  assert.match(renderer, /<thead><tr>/);
  assert.match(renderer, /<tbody>/);
  assert.doesNotMatch(renderer, /dangerouslySetInnerHTML/);
});

test('finalized snapshot wrapper passes stored Markdown unchanged and does not rebuild it', () => {
  const snapshot = readFileSync(new URL('../components/consultation/FinalReportSnapshot.jsx', import.meta.url), 'utf8');
  assert.match(snapshot, /markdown=\{finalNarrative\}/);
  assert.doesNotMatch(snapshot, /replace\(|split\(|trim\(|substring\(|final_medical_report|patient_name/);
});

test('finalization keeps structured metadata and the current complete Markdown narrative', () => {
  const flow = readFileSync(new URL('../pages/Doctor/ConsultationFlow.jsx', import.meta.url), 'utf8');
  assert.match(flow, /finalizeReport\(reportId, reviewedAssessments, reviewedSummary, previewReport\)/);
  assert.match(flow, /const previewReport = reportMode === 'ai' \? aiReportDraft : manualReportDraft/);
  assert.match(flow, /aiDraftReport: reportMode === 'ai' \? aiReportDraft : ''/);
  assert.doesNotMatch(flow, /result\.assessments|result\.clinicalSummary|normalizeAISuggestions/);
});
