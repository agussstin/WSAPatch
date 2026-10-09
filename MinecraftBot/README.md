# Bot de supervivencia para Minecraft (Java)

Un bot que vive en un servidor de Minecraft Java: come, combate, duerme, fabrica herramientas,
recolecta madera y piedra, y explora el mundo. Funciona con reglas en código, así que **no consume tokens**.

## Qué hace

Cada ciclo decide la primera acción aplicable, en este orden:

1. **Combatir** si hay un mob hostil a menos de 6 bloques.
2. **Comer** si el hambre está por debajo de 12 y tiene comida.
3. **Cazar** si tiene hambre, no tiene comida y hay animales cerca.
4. **Dormir** de noche si hay una cama cerca.
5. **Madera:** recolecta troncos hasta juntar 8 (troncos + tablas/4).
6. **Fabricar:** tablas, palos, mesa de crafteo (la coloca junto a él), pico y hacha de madera.
7. **Piedra:** recolecta piedra y fabrica pico, hacha y espada de piedra.
8. **Cama:** caza ovejas por la lana y fabrica una cama para dormir.
9. **Explorar:** camina al azar hasta 40 bloques desde donde nació.

Si una acción falla (no encuentra árbol, no puede caminar), el bot explora y vuelve a decidir.
Si lo matan, reaparece solo. Si se desconecta, reintenta cada 10 segundos.

## Requisitos

- **Node.js 18+**
- **Java 21** (para Minecraft 1.20.5 o superior; revisa la versión de tu servidor)
- Un servidor de Minecraft Java en tu PC. Recomendado: [PaperMC](https://papermc.io/downloads).

## Pasos

1. **Servidor.** Crea una carpeta, pon el `.jar` de PaperMC y ejecútalo una vez.
   Acepta el EULA en `eula.txt` (`eula=true`) y arranca otra vez.
   En `server.properties`:
   - `online-mode=false` para una prueba local sin cuenta premium. **Solo en tu red**: cualquiera que llegue al puerto podría entrar.
   - `white-list=true` para que solo entren los nombres que tú agregues.
2. **Bot.** En esta carpeta:
   ```sh
   npm install
   MC_HOST=127.0.0.1 MC_PORT=25565 MC_USERNAME=Vida npm start
   ```
   En Windows (PowerShell): `$env:MC_HOST="127.0.0.1"; $env:MC_USERNAME="Vida"; npm start`
3. Mira la consola: verás cada acción, como `🔨 fabriqué wooden_pickaxe` o `⚔️ combate con zombie`.
   Cada 30 segundos imprime vida, comida e inventario.

### Variables de entorno

| Variable | Por defecto | Para qué |
|---|---|---|
| `MC_HOST` | `127.0.0.1` | Dirección del servidor |
| `MC_PORT` | `25565` | Puerto |
| `MC_USERNAME` | `Vida` | Nombre del bot (debe estar en la lista blanca) |
| `MC_AUTH` | `offline` | `offline` o `microsoft` (si el servidor exige cuenta premium) |
| `MC_VERSION` | (auto) | Versión, por ejemplo `1.21.4`, si la detección automática falla |

## Pruebas

```sh
npm test
```

Las pruebas revisan el planificador (las decisiones) sin servidor. **No prueban la conexión ni el juego real.**

## Límites

- **Sin hierro ni fundición:** no mina hierro, no usa horno ni carbón. Es el siguiente paso natural.
- **Sin refugio:** de noche solo duerme si ya tiene cama cerca; no construye muros.
- **Combate básico:** golpea y persigue, pero no esquiva ni usa escudo ni arco.
- **Cama:** la lana sale de matar ovejas, no de esquilarlas.
- **No probado en partida:** el entorno donde se escribió no podía descargar un servidor de Minecraft.
  Es probable que haya que ajustar algún detalle en la primera partida real.
- **Servidores públicos:** la mayoría prohíbe bots y puede banear la cuenta. Úsalo en tu servidor.

## Estructura

- `src/planner.js`: reglas de decisión (puro, sin juego).
- `src/actions.js`: acciones dentro del juego (mineflayer).
- `src/index.js`: conexión y bucle principal.
- `test/planner.test.js`: pruebas de las reglas.
