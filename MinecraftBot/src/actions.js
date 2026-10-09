'use strict';

// Acciones que ejecutan el plan dentro del juego (mineflayer). Cada una devuelve true si tuvo éxito.
const { goals } = require('mineflayer-pathfinder');
const { Vec3 } = require('vec3');

const sleep = ms => new Promise(r => setTimeout(r, ms));
const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);

// Nombres de bloques que cuentan como cada recurso.
const BLOCK_SETS = {
  log: b => /_log$/.test(b.name) && !/stripped/.test(b.name),
  stone: b => b.name === 'stone',
};
const ANIMALS = ['cow', 'pig', 'sheep', 'chicken', 'rabbit'];

function snapshot(bot) {
  const reg = bot.registry;
  const items = bot.inventory.items();
  const inv = {};
  let foodItems = 0;
  for (const it of items) {
    inv[it.name] = (inv[it.name] || 0) + it.count;
    if (reg.foods && reg.foods[it.type]) foodItems += it.count;
  }
  const me = bot.entity.position;
  const near = (pred, range) => Object.values(bot.entities).some(e => e !== bot.entity && pred(e) && e.position.distanceTo(me) <= range);
  const tableId = reg.blocksByName.crafting_table.id;
  const findTable = range => bot.findBlock({ matching: tableId, maxDistance: range });
  const timeOfDay = bot.time.timeOfDay;
  return {
    food: bot.food,
    foodItems,
    inv,
    hostileNear: near(e => e.type === 'hostile', 6),
    animalNear: near(e => e.type === 'animal' && ANIMALS.includes(e.name), 24),
    sheepNear: near(e => e.name === 'sheep', 24),
    isNight: timeOfDay >= 12541 && timeOfDay <= 23458,
    bedNear: !!bot.findBlock({ matching: b => bot.isABed(b), maxDistance: 16 }),
    bedKnown: !!bot.findBlock({ matching: b => bot.isABed(b), maxDistance: 48 }),
    tableNear: !!findTable(4),
    tableKnown: !!findTable(48),
    tableInInv: (inv.crafting_table || 0) > 0,
  };
}

// Mejor arma o herramienta en la mano.
async function equipBest(bot, words = ['sword', 'axe']) {
  const item = bot.inventory.items().find(i => words.some(w => i.name.endsWith(w)));
  if (item) await bot.equip(item, 'hand').catch(() => {});
}

async function eat(bot) {
  const reg = bot.registry;
  const food = bot.inventory.items()
    .filter(i => reg.foods && reg.foods[i.type])
    .sort((a, b) => reg.foods[b.type].foodPoints - reg.foods[a.type].foodPoints)[0];
  if (!food) return false;
  await bot.equip(food, 'hand');
  await bot.consume();
  log('🍖 comí', food.name);
  return true;
}

// Combate contra un mob (hostil o animal) hasta que muera, se aleje o pasen 15 s.
async function fight(bot, mob) {
  await equipBest(bot);
  const end = Date.now() + 15000;
  while (mob.isValid && bot.entity && bot.health > 0 && Date.now() < end) {
    const d = bot.entity.position.distanceTo(mob.position);
    if (d > 24) break;
    if (d > 3) {
      bot.pathfinder.setGoal(new goals.GoalFollow(mob, 2), true);
      await sleep(250);
      continue;
    }
    bot.pathfinder.setGoal(null);
    await bot.lookAt(mob.position.offset(0, mob.height * 0.8, 0));
    bot.attack(mob);
    await sleep(650);
  }
  bot.pathfinder.setGoal(null);
  return true;
}

function nearestMob(bot, pred, range) {
  let best = null, bestD = range;
  for (const e of Object.values(bot.entities)) {
    if (e === bot.entity || !pred(e)) continue;
    const d = e.position.distanceTo(bot.entity.position);
    if (d < bestD) { best = e; bestD = d; }
  }
  return best;
}
async function combatNearest(bot, pred, range) {
  const mob = nearestMob(bot, pred, range);
  if (!mob) return false;
  log('⚔️ combate con', mob.name || mob.displayName);
  return fight(bot, mob);
}
const hostileMob = e => e.type === 'hostile';
const huntMob = kind => e => (kind ? e.name === kind : e.type === 'animal' && ANIMALS.includes(e.name));

// Recolecta el bloque más cercano de una familia (troncos o piedra). Usa el plugin de recolección,
// que elige la herramienta correcta y camina hasta el bloque.
async function gather(bot, kind) {
  const matches = BLOCK_SETS[kind];
  const block = bot.findBlock({ matching: b => matches(b), maxDistance: 40 });
  if (!block) return false;
  try {
    await bot.collectBlock.collect(block, { ignoreNoPath: true });
    return true;
  } catch (err) {
    log('no pude recolectar', kind, '-', err.message);
    return false;
  }
}

// Fabrica un objeto. Si necesita mesa, la busca cerca; si no, falla y el planificador decide otra cosa.
async function craft(bot, name) {
  const reg = bot.registry;
  let itemName = name;
  if (name === 'planks') {
    const log = bot.inventory.items().find(i => /_log$/.test(i.name));
    if (!log) return false;
    itemName = log.name.replace(/_log$/, '_planks');
  }
  const item = reg.itemsByName[itemName];
  if (!item) return false;
  const table = bot.findBlock({ matching: reg.blocksByName.crafting_table.id, maxDistance: 4 });
  const recipe = bot.recipesFor(item.id, null, 1, table)[0];
  if (!recipe) return false;
  if (recipe.requiresTable && !table) return false;
  await bot.craft(recipe, 1, table || undefined);
  log('🔨 fabriqué', itemName);
  return true;
}

// Coloca un bloque o mueble (mesa, cama) del inventario junto al bot.
async function placeFromInventory(bot, itemName) {
  const item = bot.inventory.items().find(i => i.name === itemName);
  if (!item) return false;
  await bot.equip(item, 'hand');
  const pos = bot.entity.position.floored();
  const dirs = [[1, 0], [-1, 0], [0, 1], [0, -1]];
  for (const [dx, dz] of dirs) {
    const target = pos.offset(dx * 2, 0, dz * 2);
    const ground = bot.blockAt(target.offset(0, -1, 0));
    const air = bot.blockAt(target), airAbove = bot.blockAt(target.offset(0, 1, 0));
    if (!ground || !air || !airAbove || air.boundingBox !== 'empty' || airAbove.boundingBox !== 'empty' || ground.boundingBox !== 'block') continue;
    try {
      await bot.lookAt(target.offset(0.5, 0.5, 0.5));
      await bot.placeBlock(ground, new Vec3(0, 1, 0));
      log('📦 coloqué', itemName);
      return true;
    } catch (err) { /* prueba otra dirección */ }
  }
  return false;
}

async function goToTable(bot) {
  const table = bot.findBlock({ matching: bot.registry.blocksByName.crafting_table.id, maxDistance: 48 });
  if (!table) return false;
  await bot.pathfinder.goto(new goals.GoalNear(table.position.x, table.position.y, table.position.z, 2));
  return true;
}

async function sleepInBed(bot) {
  const bed = bot.findBlock({ matching: b => bot.isABed(b), maxDistance: 16 });
  if (!bed) return false;
  await bot.pathfinder.goto(new goals.GoalNear(bed.position.x, bed.position.y, bed.position.z, 1));
  await bot.sleep(bed);
  log('🛏️ dormí');
  return true;
}

// Vaga por el mundo, sin alejarse mucho del punto donde nació.
async function explore(bot, home) {
  const r = 40;
  const x = home.x + (Math.random() * 2 - 1) * r;
  const z = home.z + (Math.random() * 2 - 1) * r;
  await bot.pathfinder.goto(new goals.GoalNearXZ(Math.floor(x), Math.floor(z), 3));
  return true;
}

module.exports = {
  snapshot, eat, combatNearest, hostileMob, huntMob, gather, craft,
  placeFromInventory, goToTable, sleepInBed, explore, log, sleep,
};
