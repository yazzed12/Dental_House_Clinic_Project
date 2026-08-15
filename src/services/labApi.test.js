import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { createLabService, saveLabDraft } from './labApi.js';

const UUIDS = Object.freeze({ lab: '11111111-1111-4111-8111-111111111111', product: '22222222-2222-4222-8222-222222222222' });

test('Lab service uses Migration 022 Supabase RPCs with exact arguments', async () => {
  const calls = [];
  const service = createLabService({ supabaseClient: { rpc: async (name, args) => {
    calls.push([name, args]);
    return { data: name.startsWith('list_') ? [] : { id: 'created' }, error: null };
  } } });
  await service.listLabs(true);
  await service.createLab('Yazeed Lab');
  await service.archiveLab(UUIDS.lab);
  await service.listLabProducts(UUIDS.lab, true);
  await service.createLabProduct(UUIDS.lab, 'Crown', '500.00');
  await service.updateLabProductPrice(UUIDS.product, '525.00');
  await service.archiveLabProduct(UUIDS.product);
  await service.getConsultationLabItems('consultation-id');
  await service.saveConsultationLabItems('consultation-id', [{ labProductId: UUIDS.product, quantity: 2, currentPrice: '999.00', labName: 'Never sent' }], 'Shade A2', true);
  assert.deepEqual(calls, [
    ['list_labs', { p_include_archived: true }],
    ['create_lab', { p_name: 'Yazeed Lab' }],
    ['archive_lab', { p_lab_id: UUIDS.lab }],
    ['list_lab_products', { p_lab_id: UUIDS.lab, p_include_archived: true }],
    ['create_lab_product', { p_lab_id: UUIDS.lab, p_name: 'Crown', p_current_price: '500.00' }],
    ['update_lab_product_price', { p_lab_product_id: UUIDS.product, p_current_price: '525.00' }],
    ['archive_lab_product', { p_lab_product_id: UUIDS.product }],
    ['get_consultation_lab_items', { p_consultation_id: 'consultation-id' }],
    ['save_consultation_lab_items', {
      p_consultation_id: 'consultation-id',
      p_items: [{ labProductId: UUIDS.product, quantity: 2 }],
      p_lab_note: 'Shade A2',
      p_lab_note_supplied: true,
    }],
  ]);
});

test('JSONB list arrays are preserved instead of being collapsed to the first item', async () => {
  const rows = [{ id: 'lab-1' }, { id: 'lab-2' }];
  const service = createLabService({ supabaseClient: { rpc: async () => ({ data: rows, error: null }) } });
  assert.deepEqual(await service.listLabs(false), rows);
});

test('RPC authorization and duplicate failures map to readable errors', async () => {
  const denied = createLabService({ supabaseClient: { rpc: async () => ({ data: null, error: { code: '42501' } }) } });
  await assert.rejects(denied.listLabs(), error => error.code === 'LAB_FORBIDDEN' && error.status === 403);
  const duplicate = createLabService({ supabaseClient: { rpc: async () => ({ data: null, error: { code: '23505', message: 'LAB_PRODUCT_NAME_DUPLICATE' } }) } });
  await assert.rejects(duplicate.createLabProduct(UUIDS.lab, 'Crown', '500.00'), error => error.code === 'LAB_PRODUCT_DUPLICATE');
});

test('Supabase Lab transport has no table queries, FastAPI, clinic token, or medical report coupling', async () => {
  const source = await readFile(new URL('./labApi.js', import.meta.url), 'utf8');
  assert.doesNotMatch(source, /\.from\(|fetch\(|API_URL|clinic_token|clinical_reports|report_snapshot|finalNarrative/);
  for (const rpc of ['list_labs', 'create_lab', 'archive_lab', 'list_lab_products', 'create_lab_product', 'update_lab_product_price', 'archive_lab_product', 'get_consultation_lab_items', 'save_consultation_lab_items']) {
    assert.match(source, new RegExp(`['"]${rpc}['"]`));
  }
});

test('Lab draft save initializes when needed and passes the returned UUID to the RPC exactly once', async () => {
  const calls = [];
  let initializationCalls = 0;
  const result = await saveLabDraft({
    consultationId: null,
    ensureConsultationInitialized: async () => {
      initializationCalls += 1;
      return { consultationId: '33333333-3333-4333-8333-333333333333' };
    },
    items: [{ labProductId: UUIDS.product, quantity: 2 }],
    labNote: 'Shade A2',
    save: async (...args) => { calls.push(args); return { items: [] }; },
  });
  assert.deepEqual(result, { items: [] });
  assert.equal(initializationCalls, 1);
  assert.deepEqual(calls, [[
    '33333333-3333-4333-8333-333333333333',
    [{ labProductId: UUIDS.product, quantity: 2 }],
    'Shade A2',
    true,
  ]]);
});

test('existing consultation skips initialization and Lab save failures preserve caller-owned intent', async () => {
  const items = [{ labProductId: UUIDS.product, quantity: 4 }];
  let initializationCalls = 0;
  await assert.rejects(saveLabDraft({
    consultationId: '44444444-4444-4444-8444-444444444444',
    ensureConsultationInitialized: async () => { initializationCalls += 1; },
    items,
    labNote: 'Urgent',
    save: async () => { throw new Error('Lab RPC unavailable'); },
  }), /Lab RPC unavailable/);
  assert.equal(initializationCalls, 0);
  assert.deepEqual(items, [{ labProductId: UUIDS.product, quantity: 4 }]);
});
