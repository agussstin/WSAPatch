'use strict';

// Planificador por reglas: a partir de un resumen del estado decide la siguiente acción.
// No toca el juego, así que se puede probar sin servidor (ver test/).
// No usa modelos de lenguaje: no consume tokens.

const FOOD_LOW = 12;          // hambre (0-20) por debajo de la cual come o caza
const HOSTILE_RANGE = 6;      // bloques: un mob hostil más cerca que esto activa el combate
const WOOD_TARGET = 8;        // troncos + tablas/4 que intenta juntar antes de fabricar
const STONE_TARGET = 8;       // piedra que intenta juntar para herramientas de piedra
const SHEEP_TARGET = 3;       // lana para una cama

const sumNames = (inv, re) => Object.entries(inv).reduce((a, [k, v]) => a + (re.test(k) ? v : 0), 0);
const have = (inv, name) => inv[name] || 0;
const planks = inv => sumNames(inv, /_planks$/);
const logs = inv => sumNames(inv, /_log$/);

// Herramientas en orden. `need` son ingredientes: 'planks', 'stick', 'cobblestone', 'white_wool'.
const TOOLS = [
  { item: 'wooden_pickaxe', need: { planks: 3, stick: 2 } },
  { item: 'wooden_axe',     need: { planks: 3, stick: 2 } },
  { item: 'stone_pickaxe',  need: { cobblestone: 3, stick: 2 } },
  { item: 'stone_axe',      need: { cobblestone: 3, stick: 2 } },
  { item: 'stone_sword',    need: { cobblestone: 2, stick: 1 } },
];

// Qué hacer para tener `tool`, o null si aún faltan materiales que no se pueden conseguir ya.
function toolStep(s, tool) {
  const inv = s.inv;
  if (have(inv, tool.item) > 0) return null;
  for (const [mat, n] of Object.entries(tool.need)) {
    const owned = mat === 'planks' ? planks(inv) : have(inv, mat);
    if (owned >= n) continue;
    if (mat === 'stick' && planks(inv) >= 2) return { type: 'craft', item: 'stick' };
    if (mat === 'planks' && logs(inv) > 0) return { type: 'craft', item: 'planks' };
    if (mat === 'cobblestone') return { type: 'gather', block: 'stone' };
    return null;
  }
  return withTable(s, { type: 'craft', item: tool.item });
}

// Una acción que necesita mesa de crafteo: va a la mesa, la coloca o fabrica una nueva.
function withTable(s, action) {
  if (s.tableNear) return action;
  if (s.tableKnown) return { type: 'goto_table' };
  if (have(s.inv, 'crafting_table') > 0) return { type: 'place_table' };
  if (planks(s.inv) >= 4) return { type: 'craft', item: 'crafting_table' };
  return null;
}

// Devuelve la primera acción aplicable, en orden de prioridad.
function decide(s) {
  const inv = s.inv, p = planks(inv), l = logs(inv);
  const hasFood = s.foodItems > 0;

  // 1. Supervivencia inmediata
  if (s.hostileNear) return { type: 'fight' };          // primero defenderse, luego comer
  if (s.food <= FOOD_LOW && hasFood) return { type: 'eat' };
  if (s.food <= FOOD_LOW && s.animalNear) return { type: 'hunt' };
  if (s.isNight && s.bedNear) return { type: 'sleep' };

  // 2. Madera y tablas
  if (l + p / 4 < WOOD_TARGET) return { type: 'gather', block: 'log' };
  if (p < 4 && l > 0) return { type: 'craft', item: 'planks' };
  if (have(inv, 'stick') < 2 && p >= 2) return { type: 'craft', item: 'stick' };

  // 3. Herramientas de madera y piedra
  for (const tool of TOOLS) {
    if (tool.item.startsWith('stone_') && have(inv, 'wooden_pickaxe') === 0) break;
    const step = toolStep(s, tool);
    if (step) return step;
  }

  // 4. Cama: lana de ovejas + tablas, luego dormir de noche
  if (have(inv, 'white_bed') === 0 && !s.bedKnown) {
    if (sumNames(inv, /^white_wool$/) >= SHEEP_TARGET && p >= 3) {
      const step = withTable(s, { type: 'craft', item: 'white_bed' });
      if (step) return step;
    } else if (s.sheepNear && sumNames(inv, /^white_wool$/) < SHEEP_TARGET) {
      return { type: 'hunt', kind: 'sheep' };
    }
  }
  if (have(inv, 'white_bed') > 0 && !s.bedKnown) return { type: 'place_bed' };

  // 5. Sin nada urgente: explorar el mundo
  return { type: 'explore' };
}

module.exports = { decide, FOOD_LOW, HOSTILE_RANGE, WOOD_TARGET, STONE_TARGET, SHEEP_TARGET, planks, logs, TOOLS };
