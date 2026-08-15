import assert from 'node:assert/strict';
import test from 'node:test';
import { chooseLabAfterRefresh, filterLabProducts } from './labView.js';

const labs = [
  { id: 'archived', isActive: false },
  { id: 'active-1', isActive: true },
  { id: 'active-2', isActive: true },
];

test('first active Lab auto-selects and valid explicit selections are preserved', () => {
  assert.equal(chooseLabAfterRefresh(labs, null), 'active-1');
  assert.equal(chooseLabAfterRefresh(labs, 'active-2'), 'active-2');
  assert.equal(chooseLabAfterRefresh(labs, null, 'archived'), 'archived');
  assert.equal(chooseLabAfterRefresh([], null), null);
});

test('product search is local, case-insensitive, and non-mutating', () => {
  const products = [{ name: 'Ceramic Crown' }, { name: 'Bridge' }];
  assert.deepEqual(filterLabProducts(products, 'CROWN'), [products[0]]);
  assert.deepEqual(filterLabProducts(products, ' bridge '), [products[1]]);
  assert.equal(filterLabProducts(products, ''), products);
});
