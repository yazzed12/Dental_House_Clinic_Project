import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';

const [page, app, sidebar, service] = await Promise.all([
  readFile(new URL('./LabTransactions.jsx', import.meta.url), 'utf8'),
  readFile(new URL('../../App.jsx', import.meta.url), 'utf8'),
  readFile(new URL('../../components/Sidebar.jsx', import.meta.url), 'utf8'),
  readFile(new URL('../../services/labTransactionsApi.js', import.meta.url), 'utf8'),
]);

test('Doctor-only route and sidebar expose the official Lab Transactions name', () => {
  assert.match(app, /path="\/doctor\/lab-transactions"[\s\S]*allowedRoles=\{\['doctor'\]\}/);
  assert.doesNotMatch(app, /path="\/admin\/lab-transactions"/);
  assert.equal((sidebar.match(/label: 'Lab Transactions'/g) || []).length, 1);
  assert.doesNotMatch(sidebar.split('admin:')[1].split('receptionist:')[0], /Lab Transactions/);
  assert.doesNotMatch(sidebar.split('receptionist:')[1].split('patient:')[0], /Lab Transactions/);
  assert.doesNotMatch(page + sidebar, /Lab Financials|Lab Accounting/);
});

test('page loads archived Labs, defaults monthly, and preserves selection in URL params', () => {
  assert.match(page, /listLabs\(true\)/);
  assert.match(page, /: 'monthly'/);
  assert.match(page, /next\.set\('labId', selectedLabId\)/);
  assert.match(page, /next\.set\('period', filter\)/);
  assert.match(page, /Archived/);
});

test('server summary values and immutable transaction snapshots render directly', () => {
  for (const field of ['totalPurchases', 'totalPaid', 'remainingBalance', 'transactionCount', 'itemCount']) assert.match(page, new RegExp(`summary\\?\\.${field}`));
  for (const field of ['labName', 'productName', 'unitPrice', 'quantity', 'totalAmount', 'transactionTotal']) assert.match(page, new RegExp(`transaction\\.${field}|item\\.${field}`));
  assert.doesNotMatch(page, /listLabProducts|currentPrice/);
  assert.match(page, /consultations-history\?consultationId=\$\{transaction\.consultationId\}/);
  assert.match(page, /transaction\.consultationDisplayId/);
  assert.doesNotMatch(page, /formatDisplayId\(transaction\.consultationId, 'CON'\)/);
  assert.doesNotMatch(page, /transaction\.consultationId\.slice\(/);
});

test('payment flows append revisions, refresh independently, and block archived creation', () => {
  assert.match(page, /disabled=\{!selectedLab\?\.isActive\}/);
  assert.match(page, /if \(saving\) return/);
  assert.match(page, /await createLabPayment/);
  assert.match(page, /await correctLabPayment/);
  assert.match(page, /expectedRevision: payment\.revision/);
  assert.match(page, /Promise\.all\(\[refreshSection\('payments'\), refreshSection\('summary'\)\]\)/);
  assert.doesNotMatch(page + service, /deleteLabPayment|updateLabPayment|\.from\(/);
});

test('independent loading/error/empty states remain and Medical Report is isolated', () => {
  for (const message of ['No Labs available.', 'No Lab transactions for this period.', 'No Lab payments for this period.']) assert.match(page, new RegExp(message.replace('.', '\\.')));
  assert.match(page, /sectionState\.transactions/); assert.match(page, /sectionState\.summary/); assert.match(page, /sectionState\.payments/);
  assert.doesNotMatch(page + service, /httpClient|clinic_token|\/api\/|clinical_reports|reportSnapshot|finalNarrative|MedicalReportMarkdown|Humanize|Ollama/);
});
