import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';

const source = await readFile(new URL('../pages/Doctor/ConsultationFlow.jsx', import.meta.url), 'utf8');

test('AI and Manual segmented modes preserve independent local drafts with AI default', () => {
  assert.match(source, /const \[reportMode, setReportMode\] = useState\('ai'\)/);
  assert.match(source, /const \[aiReportDraft, setAiReportDraft\] = useState\(''\)/);
  assert.match(source, /const \[manualReportDraft, setManualReportDraft\] = useState\(''\)/);
  assert.match(source, /role="tablist" aria-label="Report authoring mode"/);
  assert.match(source, /\['ai', 'AI Report'\]/);
  assert.match(source, /\['manual', 'Manual Report'\]/);
  assert.match(source, /onClick=\{\(\) => setReportMode\(mode\)\}/);
  assert.doesNotMatch(source, /setReportMode\(mode\)[\s\S]{0,100}set(?:Ai|Manual)ReportDraft/);
});

test('Manual mode is one Markdown editor and never invokes AI generation', () => {
  const manualBranch = source.slice(
    source.indexOf("reportMode === 'ai' ? (", source.indexOf('One report authoring area')),
    source.indexOf('<div style={{ display: \'flex\', justifyContent: \'flex-end\'', source.indexOf('One report authoring area')),
  );
  assert.match(manualBranch, /aria-label="Manual Medical Report Markdown"/);
  assert.match(manualBranch, /value=\{manualReportDraft\}/);
  assert.match(manualBranch, /placeholder="Write the clinical report here\.\.\."/);
  assert.match(manualBranch, /MedicalReportMarkdown markdown=\{manualReportDraft\}/);
  assert.doesNotMatch(manualBranch.split(') : (')[1], /generateAIReport|handleGenerateReport|humanizeReport/);
});

test('only the active draft is saved and finalized through one report path', () => {
  assert.match(source, /const previewReport = reportMode === 'ai' \? aiReportDraft : manualReportDraft/);
  assert.match(source, /finalMedicalReport: previewReport/);
  assert.match(source, /aiDraftReport: reportMode === 'ai' \? aiReportDraft : ''/);
  assert.match(source, /finalizeReport\(reportId, reviewedAssessments, reviewedSummary, previewReport\)/);
  assert.equal((source.match(/await saveReport\(/g) || []).length, 2);
  assert.equal((source.match(/await finalizeReport\(/g) || []).length, 1);
});

test('Humanize is AI-only and all authoring controls disappear after finalization', () => {
  assert.match(source, /reportMode !== 'ai' \|\| !aiReportDraft\.trim\(\)/);
  assert.match(source, /reportStep !== 'finalized'/);
  assert.match(source, /reportStep === 'finalized'/);
  assert.match(source, /finalizedSnapshot\?\.finalNarrative/);
  assert.match(source, /await updateReport\(reportId, \{ humanized_report: nextHumanizedReport \}\)/);
  assert.match(source, /humanizedReport: nextHumanizedReport/);
  assert.match(source, /status: 'draft'/);
  assert.doesNotMatch(source, /Finalize this report\? It cannot be edited after approval\./);
});

test('Approve and Finalize validates then finalizes directly without a confirmation dialog', () => {
  const finalizeHandler = source.slice(
    source.indexOf('const handleFinalizeReport'),
    source.indexOf('const handleFinishSession'),
  );
  assert.match(finalizeHandler, /if \(!previewReport\.trim\(\) \|\| finalizedSnapshot\)/);
  assert.match(finalizeHandler, /await finalizeReport\(/);
  assert.doesNotMatch(finalizeHandler, /window\.confirm|confirm\(/);
});
