import test from 'node:test';
import assert from 'node:assert/strict';
import { canUseFinance, financialPosition, hasOutstandingBalance } from './financeView.js';

test('financial position distinguishes debt, settlement, and credit', () => {
  assert.equal(financialPosition('-150.00').kind, 'outstanding');
  assert.equal(financialPosition('0.00').kind, 'settled');
  assert.equal(financialPosition('50.00').kind, 'credit');
});

test('financial capabilities are centralized and receptionist remains disabled', () => {
  assert.equal(canUseFinance({ role: 'doctor' }, 'finance.patient_history.read'), true);
  assert.equal(canUseFinance({ role: 'receptionist' }, 'finance.patient_history.read'), false);
});

test('outstanding action is conditional while history can remain permanent', () => {
  assert.equal(hasOutstandingBalance({ totalOutstanding: '0.00' }), false);
  assert.equal(hasOutstandingBalance({ totalOutstanding: '100.00' }), true);
  assert.equal(hasOutstandingBalance(undefined), false);
});
