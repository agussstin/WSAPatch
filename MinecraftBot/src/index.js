'use strict';

// Punto de entrada: conecta el bot a tu servidor y lo deja vivir.
const mineflayer = require('mineflayer');
const { pathfinder, Movements } = require('mineflayer-pathfinder');
const { plugin: collectBlock } = require('mineflayer-collectblock');
const { decide } = require('./planner');
const A = require('./actions');

const OPTS = {
  host: process.env.MC_HOST || '127.0.0.1',
  port: Number(process.env.MC_PORT || 25565),
  username: process.env.MC_USERNAME || 'Vida',
  auth: process.env.MC_AUTH || 'offline',       // 'offline' para servidores sin cuentas premium
  ...(process.env.MC_VERSION ? { version: process.env.MC_VERSION } : {}),
};

// Ejecuta una decisión del planificador. Devuelve false si no se pudo.
async function act(bot, a, home) {
  switch (a.type) {
    case 'eat':         return A.eat(bot);
    case 'fight':       return A.combatNearest(bot, A.hostileMob, 6);
    case 'hunt':        return A.combatNearest(bot, A.huntMob(a.kind), 24);
    case 'sleep':       return A.sleepInBed(bot);
    case 'gather':      return A.gather(bot, a.block);
    case 'craft':       return A.craft(bot, a.item);
    case 'place_table': return A.placeFromInventory(bot, 'crafting_table');
    case 'place_bed':   return A.placeFromInventory(bot, 'white_bed');
    case 'goto_table':  return A.goToTable(bot);
    case 'explore':     return A.explore(bot, home);
    default:            return false;
  }
}

function status(bot) {
  const inv = bot.inventory.items().map(i => `${i.count} ${i.name}`).join(', ') || 'vacío';
  A.log(`📊 vida ${bot.health}/20 · comida ${bot.food}/20 · inventario: ${inv}`);
}

function start() {
  const bot = mineflayer.createBot(OPTS);
  const session = { alive: true };
  bot.loadPlugin(pathfinder);
  bot.loadPlugin(collectBlock);

  bot.once('spawn', async () => {
    bot.pathfinder.setMovements(new Movements(bot));
    const home = bot.entity.position.clone();
    A.log('🌍 spawn en', home.floored().toString());
    const statusTimer = setInterval(() => status(bot), 30000);
    await loop(bot, home, session);
    clearInterval(statusTimer);
  });
  bot.on('death', () => A.log('💀 morí; reaparezco en mi cama o en el spawn'));
  bot.on('kicked', reason => A.log('expulsado del servidor:', JSON.stringify(reason)));
  bot.on('error', err => A.log('error:', err.message));
  bot.on('end', reason => {
    session.alive = false;
    A.log('desconectado (' + reason + '); reintento en 10 s');
    setTimeout(start, 10000);
  });
}

async function loop(bot, home, session) {
  while (session.alive) {
    try {
      if (bot.health <= 0) { await A.sleep(1000); continue; }
      const decision = decide(A.snapshot(bot));
      const ok = await act(bot, decision, home);
      if (!ok) await A.explore(bot, home);   // si no pudo, camina un poco y reintenta
    } catch (err) {
      A.log('error en el ciclo:', err.message);
      bot.pathfinder.setGoal(null);
      await A.sleep(1000);
    }
    await A.sleep(100);
  }
}

start();
