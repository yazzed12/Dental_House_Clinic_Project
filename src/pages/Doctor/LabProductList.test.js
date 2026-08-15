import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';

const [page, app, sidebar] = await Promise.all([
  readFile(new URL('./LabProductList.jsx', import.meta.url), 'utf8'),
  readFile(new URL('../../App.jsx', import.meta.url), 'utf8'),
  readFile(new URL('../../components/Sidebar.jsx', import.meta.url), 'utf8'),
]);

test('Doctor-only navigation and protected route expose Lab Product List', () => {
  assert.match(app, /path="\/doctor\/lab-products"[\s\S]*allowedRoles=\{\['doctor'\]\}/);
  assert.doesNotMatch(app, /path="\/admin\/lab-products"/);
  assert.equal((sidebar.match(/label: 'Lab Product List'/g) || []).length, 1);
  assert.doesNotMatch(sidebar.split('admin:')[1].split('receptionist:')[0], /Lab Product List/);
  assert.doesNotMatch(sidebar.split('receptionist:')[1].split('patient:')[0], /Lab Product List/);
});

test('page implements Labs switch, archived toggle, and required empty states', () => {
  assert.match(page, /role="tablist" aria-label="Labs"/);
  assert.match(page, /aria-selected=\{lab\.id === selectedLabId\}/);
  assert.match(page, /Show Archived/);
  assert.match(page, /No labs added yet\./);
  assert.match(page, /No products added for this lab yet\./);
  assert.match(page, /No matching lab products\./);
  assert.match(page, /chooseLabAfterRefresh\(rows, current/);
});

test('all Lab and product mutations use focused service operations and refresh authoritative data', () => {
  for (const operation of ['createLab', 'archiveLab', 'createLabProduct', 'updateLabProductPrice', 'archiveLabProduct']) {
    assert.match(page, new RegExp(`await ${operation}\\(`));
  }
  assert.match(page, /await refreshLabs\(created\.id\)/);
  assert.match(page, /await refreshProducts\(\)/);
});

test('archived Labs and products cannot expose mutation actions', () => {
  assert.match(page, /if \(!selectedLab\?\.isActive\) return/);
  assert.match(page, /!selectedLab\?\.isActive \|\| !product\.isActive/);
  assert.match(page, /selectedLab\?\.isActive && product\.isActive/);
  assert.match(page, /disabled=\{!selectedLab\.isActive \|\| saving\}/);
  assert.doesNotMatch(page, /reactivate|hard.?delete/i);
});

test('page preserves Lab isolation from consultation, billing, and medical reports', () => {
  assert.doesNotMatch(page, /consultation_lab_items|lab_note|clinic_procedures|consultation_procedures|financial_|clinical_reports|report_snapshot|finalNarrative|Ollama/);
});
