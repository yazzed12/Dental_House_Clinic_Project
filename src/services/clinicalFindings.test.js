import assert from 'node:assert/strict';
import test from 'node:test';

import {
  hydrateClinicalFindings, removeClinicalFinding, serializeClinicalFindings,
  unionFindingSymptoms, upsertClinicalFinding,
} from './clinicalFindings.js';

test('one and multiple findings serialize in deterministic FDI order', () => {
  let findings = upsertClinicalFinding({}, '24', { status: 'treated', notes: 'Stable' }, { symptoms: [] });
  findings = upsertClinicalFinding(findings, '11', { status: 'problem', notes: 'Caries' }, { symptoms: ['Pain'] });
  assert.deepEqual(serializeClinicalFindings(findings).map(item => item.toothId), ['11', '24']);
});

test('editing the same tooth updates without duplication and isolates symptoms', () => {
  let findings = upsertClinicalFinding({}, '11', { status: 'problem', notes: '' }, { symptoms: ['Pain'] });
  findings = upsertClinicalFinding(findings, '11', { status: 'treated', notes: 'Restored' }, { symptoms: ['Sensitivity'] });
  findings = upsertClinicalFinding(findings, '24', { status: 'healthy', notes: '' }, { symptoms: [] });
  assert.equal(serializeClinicalFindings(findings).length, 2);
  assert.deepEqual(findings['11'], { toothId: '11', toothStatus: 'treated', symptoms: ['Sensitivity'], toothNote: 'Restored' });
  assert.deepEqual(findings['24'].symptoms, []);
});

test('removing a finding does not require or mutate dental-state data', () => {
  const toothData = { 11: { status: 'problem', notes: 'Keep' } };
  const findings = removeClinicalFinding(upsertClinicalFinding({}, '11', toothData[11]), '11');
  assert.deepEqual(findings, {});
  assert.equal(toothData[11].notes, 'Keep');
});

test('NULL legacy and explicit empty snapshots remain distinct', () => {
  assert.equal(hydrateClinicalFindings(null), null);
  assert.deepEqual(hydrateClinicalFindings([]), {});
});

test('flat compatibility symptoms are a deterministic case-insensitive union', () => {
  const findings = {
    24: { toothId: '24', toothStatus: 'treated', symptoms: ['Sensitivity'], toothNote: '' },
    11: { toothId: '11', toothStatus: 'problem', symptoms: ['pain', 'Pain'], toothNote: '' },
  };
  assert.deepEqual(unionFindingSymptoms(findings), ['pain', 'Sensitivity']);
});
