import assert from 'node:assert/strict';
import test from 'node:test';
import { labTransactionRange } from './labTransactionDates.js';

const localParts = iso => { const d = new Date(iso); return [d.getFullYear(), d.getMonth() + 1, d.getDate()]; };

test('Daily range is one local calendar day and half-open', () => {
  const range = labTransactionRange('daily', '2026-08-15');
  assert.deepEqual(localParts(range.dateFrom), [2026, 8, 15]); assert.deepEqual(localParts(range.dateTo), [2026, 8, 16]);
});
test('Weekly range is Monday through next Monday', () => {
  const range = labTransactionRange('weekly', '2026-08-15');
  assert.deepEqual(localParts(range.dateFrom), [2026, 8, 10]); assert.deepEqual(localParts(range.dateTo), [2026, 8, 17]);
});
test('Monthly range defaults to the selected calendar month', () => {
  const range = labTransactionRange('monthly', '2026-08-15');
  assert.deepEqual(localParts(range.dateFrom), [2026, 8, 1]); assert.deepEqual(localParts(range.dateTo), [2026, 9, 1]);
});
test('Yearly range covers one calendar year', () => {
  const range = labTransactionRange('yearly', '2026-08-15');
  assert.deepEqual(localParts(range.dateFrom), [2026, 1, 1]); assert.deepEqual(localParts(range.dateTo), [2027, 1, 1]);
});
test('Custom range includes the end day by sending the next day exclusively', () => {
  const range = labTransactionRange('custom', '2026-08-03', '2026-08-09');
  assert.deepEqual(localParts(range.dateFrom), [2026, 8, 3]); assert.deepEqual(localParts(range.dateTo), [2026, 8, 10]);
  assert.equal(labTransactionRange('custom', '2026-08-10', '2026-08-09'), null);
});
