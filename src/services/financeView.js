export const financialPosition = balance => {
  const value = Number(balance || 0);
  if (value > 0) return Object.freeze({ kind: 'credit', label: 'Paid Extra', color: 'success' });
  if (value < 0) return Object.freeze({ kind: 'outstanding', label: 'Outstanding', color: 'danger' });
  return Object.freeze({ kind: 'settled', label: 'Settled', color: 'neutral' });
};

export const hasOutstandingBalance = summary => Number(summary?.totalOutstanding || 0) > 0;

const ROLE_CAPABILITIES = Object.freeze({
  doctor: Object.freeze([
    'finance.catalog.read', 'finance.catalog.manage', 'finance.billing.read',
    'finance.billing.write', 'finance.payment.read', 'finance.payment.record',
    'finance.payment.correct', 'finance.patient_history.read',
  ]),
});

export const canUseFinance = (user, capability) => ROLE_CAPABILITIES[user?.role]?.includes(capability) === true;
