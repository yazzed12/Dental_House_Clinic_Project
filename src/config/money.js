export const CLINIC_CURRENCY = Object.freeze({
  code: 'EGP',
  locale: 'en-EG',
});

const formatter = new Intl.NumberFormat(CLINIC_CURRENCY.locale, {
  style: 'currency',
  currency: CLINIC_CURRENCY.code,
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

export const formatMoney = cents => formatter.format(Number(cents) / 100);

export const decimalToCents = value => {
  if (typeof value !== 'string' && typeof value !== 'number') return null;
  const normalized = String(value).trim();
  if (!/^\d+(?:\.\d{1,2})?$/.test(normalized)) return null;
  const [whole, fraction = ''] = normalized.split('.');
  const cents = Number(whole) * 100 + Number(fraction.padEnd(2, '0'));
  return Number.isSafeInteger(cents) ? cents : null;
};

export const centsToDecimal = cents => `${Math.floor(cents / 100)}.${String(cents % 100).padStart(2, '0')}`;
