import React from 'react';
import { CreditCard } from 'lucide-react';

export const billingForAppointment = (cards, appointmentId) => (
  cards.find(card => String(card.appointmentId) === String(appointmentId)) || null
);

export const consultationBillingDisplay = card => {
  const balance = Number(card.balance || 0);
  return Object.freeze({
    paid: card.paidTotal,
    balanceLabel: balance > 0 ? 'Paid Extra' : balance < 0 ? 'Remaining' : 'Settled',
    balanceAmount: balance > 0 ? card.creditTotal : card.outstandingTotal,
  });
};

export default function AppointmentFinancialButton({ billing, onOpen }) {
  if (!billing) return null;
  return React.createElement('button', {
    type: 'button',
    className: 'btn btn-sm',
    onClick: () => onOpen(billing),
    title: 'Open Consultation Billing',
    style: {
      background: 'var(--clr-primary-light)',
      border: '1px solid rgba(16,185,129,.25)',
      color: 'var(--clr-primary-dark)',
      fontWeight: 800,
      gap: 4,
    },
  }, React.createElement(CreditCard, { size: 13 }), ' Financial');
}
