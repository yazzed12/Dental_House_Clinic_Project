import React from 'react';
import { Pill } from 'lucide-react';

export default function PrescriptionHistorySection({ prescription }) {
  if (!prescription || prescription.status !== 'approved' || !prescription.items?.length) return null;
  return <section aria-label="Approved Prescription">
    <h3 style={{ display: 'flex', alignItems: 'center', gap: 8 }}><Pill size={18}/> Approved Prescription</h3>
    <p style={{ color: 'var(--clr-text-muted)', fontSize: '.78rem' }}>Immutable clinician-approved snapshot</p>
    <div style={{ display: 'grid', gap: 9 }}>{prescription.items.map((item, index) => <div key={item.id || index} style={{ padding: 12, border: '1px solid var(--clr-border)', borderRadius: 10 }}>
      <strong>{item.brandName}</strong> — {item.genericName || 'Generic not supplied'} — {item.strength} — {item.dosageForm} — {item.route}
      <div style={{ marginTop: 5, fontSize: '.8rem' }}><strong>Dose:</strong> {item.dose} · <strong>Frequency:</strong> {item.frequency} · <strong>Duration:</strong> {item.duration}</div>
      {item.instructions && <div style={{ marginTop: 4, fontSize: '.8rem' }}><strong>Instructions:</strong> {item.instructions}</div>}
      {item.doctorNotes && <div style={{ marginTop: 4, fontSize: '.8rem' }}><strong>Doctor Notes:</strong> {item.doctorNotes}</div>}
    </div>)}</div>
  </section>;
}
