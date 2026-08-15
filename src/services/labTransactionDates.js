export const LAB_TRANSACTION_FILTERS = Object.freeze(['daily', 'weekly', 'monthly', 'yearly', 'custom']);

const startOfLocalDay = value => new Date(value.getFullYear(), value.getMonth(), value.getDate());
const dateInput = value => {
  const date = startOfLocalDay(value);
  const offset = date.getTimezoneOffset();
  return new Date(date.getTime() - offset * 60000).toISOString().slice(0, 10);
};
const parseDateInput = value => {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value || '');
  return match ? new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3])) : null;
};

export const currentLocalDateInput = (now = new Date()) => dateInput(now);

export function labTransactionRange(filter, anchorValue, customEndValue, now = new Date()) {
  const anchor = parseDateInput(anchorValue) || startOfLocalDay(now);
  let from = startOfLocalDay(anchor);
  let to;
  if (filter === 'daily') to = new Date(from.getFullYear(), from.getMonth(), from.getDate() + 1);
  else if (filter === 'weekly') {
    const mondayOffset = (from.getDay() + 6) % 7;
    from = new Date(from.getFullYear(), from.getMonth(), from.getDate() - mondayOffset);
    to = new Date(from.getFullYear(), from.getMonth(), from.getDate() + 7);
  } else if (filter === 'yearly') {
    from = new Date(from.getFullYear(), 0, 1);
    to = new Date(from.getFullYear() + 1, 0, 1);
  } else if (filter === 'custom') {
    const end = parseDateInput(customEndValue);
    if (!end || end < from) return null;
    to = new Date(end.getFullYear(), end.getMonth(), end.getDate() + 1);
  } else {
    from = new Date(from.getFullYear(), from.getMonth(), 1);
    to = new Date(from.getFullYear(), from.getMonth() + 1, 1);
  }
  return { dateFrom: from.toISOString(), dateTo: to.toISOString(), startInput: dateInput(from), endInput: dateInput(new Date(to.getTime() - 86400000)) };
}
