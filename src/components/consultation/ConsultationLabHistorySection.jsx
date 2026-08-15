import React, { useMemo } from 'react';
import { decimalToCents, formatMoney } from '../../config/money.js';

export const groupLabSnapshotItems = items => Object.values(
  (Array.isArray(items) ? items : []).reduce((groups, item) => {
    const key = `${item?.labId || ''}:${item?.labName || 'Lab'}`;
    if (!groups[key]) groups[key] = { key, labName: item?.labName || 'Lab', items: [] };
    groups[key].items.push(item);
    return groups;
  }, {}),
);

const snapshotMoney = value => {
  const cents = decimalToCents(value);
  return cents === null ? String(value ?? '—') : formatMoney(cents);
};

export default function ConsultationLabHistorySection({ labItems, labNote }) {
  const note = typeof labNote === 'string' ? labNote : '';
  const groups = useMemo(() => groupLabSnapshotItems(labItems), [labItems]);
  if (groups.length === 0 && !note.trim()) return null;

  return (
    <section aria-label="Lab Items" style={{ display: 'grid', gap: 14 }}>
      <h3 style={{ margin: 0, fontSize: '1rem', fontWeight: 800 }}>Lab Items</h3>
      {groups.map(group => (
        <div key={group.key} style={{ border: '1px solid var(--clr-border)', borderRadius: 14, overflow: 'hidden' }}>
          <div style={{ padding: '10px 14px', background: 'var(--clr-primary-light)', fontWeight: 800 }}>{group.labName}</div>
          {group.items.map((item, index) => (
            <div key={`${item?.labProductId || 'product'}:${index}`} style={{ display: 'grid', gridTemplateColumns: 'minmax(0,1fr)', gap: 7, padding: '12px 14px', borderTop: '1px solid var(--clr-border)' }}>
              <strong>{item?.productName || 'Lab product'}</strong>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: '6px 18px', fontSize: '.84rem' }}>
                <span style={{ color: 'var(--clr-subtext)' }}>Qty: {item?.quantity}</span>
                <span style={{ color: 'var(--clr-subtext)' }}>Unit Price: {snapshotMoney(item?.unitPrice)}</span>
                <strong>Total: {snapshotMoney(item?.totalAmount)}</strong>
              </div>
            </div>
          ))}
        </div>
      ))}
      {note.trim() && (
        <div>
          <h4 style={{ margin: '0 0 7px', fontSize: '.86rem', fontWeight: 800 }}>Lab Note</h4>
          <div style={{ padding: 14, borderRadius: 12, background: 'var(--clr-bg)', borderLeft: '4px solid var(--clr-primary)', whiteSpace: 'pre-wrap', lineHeight: 1.65 }}>
            {note}
          </div>
        </div>
      )}
    </section>
  );
}
