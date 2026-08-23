import assert from 'node:assert/strict';
import test from 'node:test';
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { createLogger, createServer } from 'vite';

const narrative = `
# Clinical Dental Report

## Clinical Findings & Diagnosis

| FDI Tooth Number | Clinical Description | ICD-10 Code | Diagnosis |
| --- | --- | --- | --- |
| 17 | Acute pulpitis | K04.0 | Pulpitis |
`;

async function renderHistoryCard(report) {
  const originalStorage = globalThis.localStorage;
  globalThis.localStorage = { getItem: () => null, setItem: () => undefined };
  const logger = createLogger();
  const logError = logger.error;
  logger.error = (message, options) => {
    if (!String(message).includes('WebSocket server error')) logError(message, options);
  };
  const server = await createServer({
    server: { middlewareMode: true, hmr: false },
    appType: 'custom',
    optimizeDeps: { noDiscovery: true },
    customLogger: logger,
  });
  try {
    const [{ ExpandableConsultationCard }, { LanguageProvider }] = await Promise.all([
      server.ssrLoadModule('/src/pages/Doctor/ConsultationsHistory.jsx'),
      server.ssrLoadModule('/src/context/LanguageContext.jsx'),
    ]);
    return renderToStaticMarkup(React.createElement(
      LanguageProvider,
      null,
      React.createElement(ExpandableConsultationCard, {
        report,
        isExpanded: true,
        onToggle: () => undefined,
        onUpdate: () => undefined,
        readOnly: true,
      }),
    ));
  } finally {
    await server.close();
    globalThis.localStorage = originalStorage;
  }
}

const baseReport = {
  id: 'report-1', reportId: 'report-1', patient_id: 'patient-1',
  patientDisplayId: 'P-0826-00001',
  patient_name: 'Patient', created_at: '2026-08-14T10:00:00Z',
  status: 'finalized', symptoms: [], procedures: [], clinicalFindings: [],
};

test('actual Consultation History card renders finalized snapshot Markdown as semantic DOM', async () => {
  const html = await renderHistoryCard({
    ...baseReport,
    reportSnapshot: { schemaVersion: 1, finalNarrative: narrative },
  });
  assert.match(html, /<h1[^>]*>Clinical Dental Report<\/h1>/);
  assert.match(html, /<h2[^>]*>Clinical Findings &amp; Diagnosis<\/h2>/);
  assert.match(html, /<table[^>]*class="medical-report-table"/);
  assert.match(html, /<td[^>]*>17<\/td>/);
  assert.doesNotMatch(html, /\| FDI Tooth Number \|/);
  assert.doesNotMatch(html, /## Clinical Findings &amp; Diagnosis/);
});

test('actual Consultation History card renders a patient display ID without exposing the stored ID', async () => {
  const html = await renderHistoryCard({
    ...baseReport,
    reportSnapshot: { schemaVersion: 1, finalNarrative: narrative },
  });

  assert.match(html, /P-0826-00001/);
  assert.doesNotMatch(html, /ID:\s*#?patient-1/);
});

test('finalized history renders the stored humanized derivative separately and remains read-only', async () => {
  const html = await renderHistoryCard({
    ...baseReport,
    reportSnapshot: { schemaVersion: 1, finalNarrative: narrative },
    humanized_report: '## Patient-Friendly Summary\n\nYour tooth needs care.',
  });
  assert.match(html, />Humanized Report</);
  assert.match(html, /<h2[^>]*>Patient-Friendly Summary<\/h2>/);
  assert.match(html, /Your tooth needs care\./);
  assert.doesNotMatch(html, />Edit Report</);
});

test('actual legacy/fallback report branch also renders Markdown instead of pre-wrapped text', async () => {
  const html = await renderHistoryCard({
    ...baseReport,
    reportSnapshot: null,
    final_medical_report: narrative,
  });
  assert.match(html, /<h1[^>]*>Clinical Dental Report<\/h1>/);
  assert.match(html, /<table[^>]*class="medical-report-table"/);
  assert.doesNotMatch(html, /\| FDI Tooth Number \|/);
  assert.doesNotMatch(html, /white-space:\s*pre-wrap/);
});

test('legacy non-finalized report exposes the existing report editor even in a scoped history view', async () => {
  const html = await renderHistoryCard({
    ...baseReport,
    status: 'draft',
    reportSnapshot: null,
    final_medical_report: narrative,
  });
  assert.match(html, /Edit Report/);
});

test('actual Consultation History card groups stored Lab snapshots and renders one consultation note', async () => {
  const html = await renderHistoryCard({
    ...baseReport,
    reportSnapshot: { schemaVersion: 1, finalNarrative: narrative },
    labItems: [
      { labId: 'lab-1', labProductId: 'p-1', labName: 'Yazeed Lab', productName: 'Zircon Crown', unitPrice: 500, quantity: 2, totalAmount: 1000 },
      { labId: 'lab-2', labProductId: 'p-2', labName: 'Mohamed Lab', productName: 'Night Guard', unitPrice: '300.00', quantity: 1, totalAmount: '300.00' },
    ],
    labNote: 'Shade A2\nDeliver before next visit.',
  });
  assert.match(html, /aria-label="Lab Items"/);
  assert.match(html, />Yazeed Lab</);
  assert.match(html, />Mohamed Lab</);
  assert.match(html, />Zircon Crown</);
  assert.match(html, />Night Guard</);
  assert.match(html, /Qty: 2/);
  assert.match(html, /Unit Price:[^<]*EGP/);
  assert.match(html, /Total:[^<]*EGP/);
  assert.equal((html.match(/>Lab Note</g) || []).length, 1);
  assert.match(html, /Shade A2\nDeliver before next visit\./);
});

test('legacy missing Lab fields render no Lab section and do not affect the medical report', async () => {
  const html = await renderHistoryCard({
    ...baseReport,
    reportSnapshot: { schemaVersion: 1, finalNarrative: narrative },
    labItems: null,
    labNote: null,
  });
  assert.doesNotMatch(html, /aria-label="Lab Items"/);
  assert.match(html, /<h1[^>]*>Clinical Dental Report<\/h1>/);
  assert.match(html, /<table[^>]*class="medical-report-table"/);
});
