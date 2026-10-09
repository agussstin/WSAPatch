'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { decide } = require('../src/planner');

// Estado base: vivo, sin amenazas, de día, sin mesa ni cama, sin nada en el inventario.
const base = (over = {}) => ({
  food: 20, foodItems: 0, inv: {}, hostileNear: false, animalNear: false, sheepNear: false,
  isNight: false, bedNear: false, bedKnown: false, tableNear: false, tableKnown: false, tableInInv: false,
  ...over,
});

test('come cuando hay hambre y comida en el inventario', () => {
  assert.deepEqual(decide(base({ food: 8, foodItems: 2 })), { type: 'eat' });
});

test('pelea si hay un mob hostil cerca, aunque tenga hambre', () => {
  assert.deepEqual(decide(base({ food: 5, hostileNear: true, foodItems: 1 })), { type: 'fight' });
});

test('caza un animal si tiene hambre y no tiene comida', () => {
  assert.deepEqual(decide(base({ food: 6, animalNear: true })), { type: 'hunt' });
});

test('sin madera, recolecta troncos', () => {
  assert.deepEqual(decide(base()), { type: 'gather', block: 'log' });
});

test('con troncos y pocas tablas, fabrica tablas', () => {
  assert.deepEqual(decide(base({ inv: { oak_log: 8 } })), { type: 'craft', item: 'planks' });
});

test('con tablas y palos, fabrica un pico de madera junto a la mesa', () => {
  const s = base({ inv: { oak_log: 6, oak_planks: 8, stick: 4 }, tableNear: true });
  assert.deepEqual(decide(s), { type: 'craft', item: 'wooden_pickaxe' });
});

test('sin mesa en el mundo ni en el inventario, fabrica una mesa', () => {
  const s = base({ inv: { oak_log: 6, oak_planks: 8, stick: 4 } });
  assert.deepEqual(decide(s), { type: 'craft', item: 'crafting_table' });
});

test('con mesa en el inventario y lejos de cualquier mesa, la coloca', () => {
  const s = base({ inv: { oak_log: 6, oak_planks: 8, stick: 4, crafting_table: 1 }, tableInInv: true });
  assert.deepEqual(decide(s), { type: 'place_table' });
});

test('con mesa conocida pero lejos, va hacia ella', () => {
  const s = base({ inv: { oak_log: 6, oak_planks: 8, stick: 4 }, tableKnown: true });
  assert.deepEqual(decide(s), { type: 'goto_table' });
});

test('con pico de madera y sin piedra, recolecta piedra', () => {
  const s = base({ inv: { oak_log: 6, oak_planks: 8, stick: 4, wooden_pickaxe: 1, wooden_axe: 1 }, tableNear: true });
  assert.deepEqual(decide(s), { type: 'gather', block: 'stone' });
});

test('con piedra suficiente y mesa cerca, fabrica el pico de piedra', () => {
  const s = base({ inv: { oak_log: 6, oak_planks: 8, stick: 4, wooden_pickaxe: 1, wooden_axe: 1, cobblestone: 8 }, tableNear: true });
  assert.deepEqual(decide(s), { type: 'craft', item: 'stone_pickaxe' });
});

test('de noche con cama cerca, duerme', () => {
  const s = base({ food: 20, isNight: true, bedNear: true, bedKnown: true, inv: { oak_log: 8 } });
  assert.deepEqual(decide(s), { type: 'sleep' });
});

test('sin pendientes, explora', () => {
  const s = base({
    inv: { oak_log: 6, oak_planks: 8, stick: 4, wooden_pickaxe: 1, wooden_axe: 1, stone_pickaxe: 1, stone_axe: 1, stone_sword: 1, white_bed: 1 },
    bedKnown: true,
  });
  assert.deepEqual(decide(s), { type: 'explore' });
});

test('sin lana para la cama, caza ovejas', () => {
  const s = base({
    inv: { oak_log: 6, oak_planks: 8, stick: 4, wooden_pickaxe: 1, wooden_axe: 1, stone_pickaxe: 1, stone_axe: 1, stone_sword: 1 },
    sheepNear: true,
  });
  assert.deepEqual(decide(s), { type: 'hunt', kind: 'sheep' });
});
