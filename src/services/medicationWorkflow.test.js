import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { createLogger, createServer } from 'vite';

test('Medication editor clones catalog and preset data instead of mutating them', async () => {
  const logger = createLogger();
  const server = await createServer({ server: { middlewareMode: true, hmr: false }, appType: 'custom', optimizeDeps: { noDiscovery: true }, customLogger: logger });
  try {
    const {
      createPrescriptionEditor, removePrescriptionItem, updatePrescriptionItems,
    } = await server.ssrLoadModule('/src/components/consultation/MedicationSection.jsx');
    const details = { medication: { id: 'm-1', brandName: 'Master', strength: '1', dosageForm: 'Form', route: 'Route' }, effectivePreset: { dose: 'Preset dose' } };
    const editor = createPrescriptionEditor(details);
    editor.brandName = 'Consultation override'; editor.dose = 'Edited dose';
    assert.equal(details.medication.brandName, 'Master');
    assert.equal(details.effectivePreset.dose, 'Preset dose');
    const second = { ...editor, medicationId: 'm-2', brandName: 'Second' };
    const multiple = updatePrescriptionItems([editor], second);
    assert.deepEqual(multiple.map(item => item.brandName), ['Consultation override', 'Second']);
    const edited = updatePrescriptionItems(multiple, { ...second, brandName: 'Second edited' }, 1);
    assert.deepEqual(edited.map(item => item.brandName), ['Consultation override', 'Second edited']);
    assert.deepEqual(removePrescriptionItem(edited, 0).map(item => item.brandName), ['Second edited']);
  } finally { await server.close(); }
});

test('Medication is consultation-level, debounced, and finish requires review', async () => {
  const [flow, component] = await Promise.all([
    readFile(new URL('../pages/Doctor/ConsultationFlow.jsx', import.meta.url), 'utf8'),
    readFile(new URL('../components/consultation/MedicationSection.jsx', import.meta.url), 'utf8'),
  ]);
  const conditionalEnd = flow.indexOf('<MedicationSection');
  assert.ok(conditionalEnd > flow.indexOf('Clinical Notes'));
  assert.match(flow, /\)\}\s*<MedicationSection/);
  assert.match(flow, /prescriptionWorkflow\.reviewRequired[\s\S]*Review and approve/);
  assert.match(flow, /approvedPrescription: prescriptionWorkflow\.approvedPrescription/);
  assert.match(component, /setTimeout\(\(\) => \{/);
  assert.match(component, /\}, 300\)/);
  assert.match(component, /Review Full Prescription/);
  assert.match(component, /Approve Prescription/);
  assert.match(component, /workflow\.items\.map/);
  assert.match(component, /editItem/);
  assert.match(component, /deleteItem/);
});
