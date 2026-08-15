import test from 'node:test';
import assert from 'node:assert/strict';
import AppointmentFinancialButton, { billingForAppointment, consultationBillingDisplay } from './AppointmentFinancialButton.js';

const consultationA = { consultationId:'consultation-a', appointmentId:'appointment-a', paidTotal:'200.00', outstandingTotal:'300.00', creditTotal:'0.00', balance:'-300.00' };
const consultationB = { consultationId:'consultation-b', appointmentId:'appointment-b', paidTotal:'50.00', outstandingTotal:'100.00', creditTotal:'0.00', balance:'-100.00' };

test('financial button renders only for an appointment with consultation billing', () => {
  assert.equal(AppointmentFinancialButton({ billing:null, onOpen(){} }), null);
  const element = AppointmentFinancialButton({ billing:consultationA, onOpen(){} });
  assert.equal(element.type, 'button');
  assert.match(element.props.title, /Consultation Billing/);
  assert.doesNotMatch(String(element.props.children), /Outstanding Balance/);
});

test('click opens the exact appointment consultation and cannot select another', () => {
  const cards = [consultationA, consultationB];
  const selected = billingForAppointment(cards, 'appointment-a');
  assert.equal(selected.consultationId, 'consultation-a');
  let opened = null;
  AppointmentFinancialButton({ billing:selected, onOpen:value=>{opened=value;} }).props.onClick();
  assert.equal(opened.consultationId, 'consultation-a');
  assert.notEqual(opened.consultationId, 'consultation-b');
});

test('selected consultation retains its paid and remaining values', () => {
  const selected = billingForAppointment([consultationA, consultationB], 'appointment-a');
  const display = consultationBillingDisplay(selected);
  assert.equal(display.paid, '200.00');
  assert.equal(display.balanceLabel, 'Remaining');
  assert.equal(display.balanceAmount, '300.00');
});
