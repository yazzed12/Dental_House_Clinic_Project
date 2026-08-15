import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';

const source = await readFile(new URL('./ConsultationsHistory.jsx', import.meta.url), 'utf8');

test('history report editing is gated by a real report id and Migration 020 finalization state', () => {
  assert.match(source, /const hasReport = Boolean\(reportId\)/);
  assert.match(source, /Boolean\(report\.reportSnapshot \|\| report\.finalizedAt\)/);
  assert.match(source, /canEditReport = hasReport && !isStructuredFinalized && !immutabilityLocked/);
  assert.match(source, /\{canEditReport && \(/);
});

test('Edit Report loads one Markdown draft from the current saved report text', () => {
  assert.match(source, /savedReportText = report\.final_medical_report \|\| report\.ai_draft_report \|\| ''/);
  assert.match(source, /beginReportEdit[\s\S]*setReportDraft\(savedReportText\)/);
  assert.match(source, /aria-label="Clinical Report Markdown"/);
  assert.doesNotMatch(source, /Symptoms & Findings \(Comma separated\)|Completion Status|Doctor Personal Notes[\s\S]*isEditing/);
});

test('dirty state controls the single-submit Save Changes action', () => {
  assert.match(source, /isReportDirty = reportDraft !== savedReportText/);
  assert.match(source, /disabled=\{loading \|\| !isReportDirty \|\| immutabilityLocked\}/);
  assert.match(source, /if \(!canEditReport \|\| !isReportDirty \|\| loading\) return/);
  assert.match(source, /\{loading \? 'Saving\.\.\.' : 'Save Changes'\}/);
});

test('save persists only final_medical_report and preserves the separate humanized field', () => {
  assert.match(source, /updateReport\(reportId, \{ final_medical_report: reportDraft \}\)/);
  assert.match(source, /onUpdate\(\{ \.\.\.report, final_medical_report: reportDraft \}\)/);
  assert.doesNotMatch(source, /updateReport\(reportId, \{ final_medical_report: reportDraft,[^}]*humanized_report/);
  assert.match(source, /updateReport\(reportId, \{ humanized_report: approvedText \}\)/);
});

test('failed saves preserve the draft and finalized rejection locks the editor read-only', () => {
  const saveHandler = source.slice(source.indexOf('const handleSave'), source.indexOf('const cancelReportEdit'));
  assert.doesNotMatch(saveHandler, /setReportDraft\(/);
  assert.match(saveHandler, /err\?\.code === 'REPORT_FINALIZED'/);
  assert.match(saveHandler, /setImmutabilityLocked\(true\)/);
  assert.match(saveHandler, /This report has been finalized and is read-only\./);
});

test('Cancel restores saved text and confirms only when discarding dirty edits', () => {
  const start = source.indexOf('const cancelReportEdit');
  const cancelHandler = source.slice(start, source.indexOf('  return (', start));
  assert.match(cancelHandler, /isReportDirty && !window\.confirm\('Discard unsaved report changes\?'\)/);
  assert.match(cancelHandler, /setReportDraft\(savedReportText\)/);
  assert.match(cancelHandler, /setIsEditing\(false\)/);
});

test('saved report display remains safe Markdown and no migration transport is introduced', () => {
  assert.match(source, /<MedicalReportMarkdown markdown=\{report\.final_medical_report\} \/>/);
  assert.doesNotMatch(source, /clinic_token|get_or_initialize_consultation|save_current_consultation/);
});
