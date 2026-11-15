# Diablo II Decomp — TrimUI Smart Pro port layer

Experimental, **unverified on real hardware**, work toward running
[D2Decomp](https://github.com/psi29a/d2decomped) — an open-source,
GPL-3.0-or-later reimplementation of the Diablo II: Lord of Destruction
1.14d game engine — on the TrimUI Smart Pro / Brick (Allwinner A133P,
PowerVR GE8300).

This repo is **not** a fork of D2Decomp's source. It's a thin overlay — one
build script and one doc page — meant to sit on top of an unmodified
`d2decomped` checkout, plus [Handkit](https://github.com/code-beans/handkit)
(the project that already solved the hard part: getting SDL3 to draw on the
TrimUI's closed GPU driver). Keeping it separate means it can track upstream
D2Decomp without carrying a stale copy of their 1.6 MB+ of engine source
around, and keeps license/attribution unambiguous.

## Status

Nobody has run this on a TrimUI yet. The cross-compile plan is reasoned from:

- D2Decomp's existing PS Vita and Nintendo Switch builds (`tools/d2vita.sh`
  upstream), which already prove the "d2d alone, cross-compiled, SDL3 +
  OpenAL + bundled StormLib + a Bink-only FFmpeg" recipe works on far more
  exotic SDKs than plain Linux/aarch64.
- Handkit's own platform table, which lists the TrimUI Smart Pro and Brick
  (NextUI, stock, CrossMix, spruce) as "expected" — same system and GPU
  drivers as the Brick Pro, which Handkit has tested with its own demo app,
  just not with this game yet.

See [`overlay/docs/trimui.md`](overlay/docs/trimui.md) for the full
reasoning, the open risks, and what "not there yet" means concretely.

## Legal: bring your own game

**No Diablo II or Lord of Destruction files live in this repo, ever** — not
here, not in D2Decomp upstream. You need your own legally owned copy (a
1.14d install; see `overlay/docs/trimui.md` for where to get one) and you
copy its MPQ files onto your own SD card yourself. This project reads them
at runtime; it does not include, mirror, or help acquire them. See
D2Decomp's own [`LEGAL.md`](https://github.com/psi29a/d2decomped/blob/main/LEGAL.md)
for the EU interoperability basis this whole effort relies on.

## Layout

```
diablo2-trimui/
├── overlay/              Files meant to be copied into a d2decomped checkout
│   ├── tools/trimui.sh     Cross-compile + package script (Handkit toolchain)
│   ├── docs/trimui.md      Status, risks, build/deploy instructions
│   ├── patches/            Small patches onto d2decomped's own source
│   └── assets/             Port icons and box art
├── scripts/
│   └── apply-overlay.sh   Copies overlay/ onto upstream/ (or any d2decomped checkout)
└── upstream/              git submodule: fork github.com/metalpapa/d2decomped (branch trimui, from psi29a/d2decomped)
```

## Quick start

```sh
git clone --recurse-submodules https://github.com/metalpapa/diablo2-trimui.git
cd diablo2-trimui
./scripts/apply-overlay.sh

# once: clone and configure Handkit (needs Conan 2.33+, CMake, Ninja)
git clone https://github.com/code-beans/handkit ../handkit
(cd ../handkit && ./tools/handkit configure)

export HANDKIT_SDK=$PWD/../handkit
cd upstream
tools/trimui.sh all      # build/trimui-pak/ comes out the other end
```

Then follow `upstream/docs/trimui.md` ("Where its files go") to copy the
result and your own MPQs to the SD card.

## Copying files to the console's SD card (macOS, mtools)

This is the method used for every install and update of this port. The SD
shows up as a FAT32 volume called `CROSSMIX`, but nothing is mounted in
Finder: files are read and written straight on the raw disk with
[mtools](https://www.gnu.org/software/mtools/) (`brew install mtools`).
Details and gotchas are in `PORTMASTER-NOTES.md` (in Spanish).

```sh
# The disk number changes between connections: ask, never assume.
DEVICE=$(diskutil info "CROSSMIX" | awk -F': *' '/Device Node/ {print $2}')
RDEVICE=$(echo "$DEVICE" | sed 's#/dev/disk#/dev/rdisk#')   # raw disk: rdisk, not disk

sudo mdir  -i "$RDEVICE" "::/Data/ports/diablo2decomp/"                       # list
sudo mdel  -i "$RDEVICE" "::/Data/ports/diablo2decomp/d2d"                    # delete first...
sudo mcopy -i "$RDEVICE" "build/trimui-pak/Diablo II Decomp/d2d" \
                         "::/Data/ports/diablo2decomp/d2d" </dev/null         # ...then copy in
sudo mcopy -n -i "$RDEVICE" "::/Data/ports/diablo2decomp/.config/d2d/d2d.cfg" /tmp/d2d.cfg   # copy out
```

Rules that keep it from hanging:

- `::` before a path means "the drive given with `-i`".
- Always `mdel` the destination before `mcopy`. If the file exists, `mcopy`
  asks "overwrite y/n?", and when the script's output goes to a log file
  that question is invisible and the script looks frozen. Also redirect
  stdin from `/dev/null` on `mcopy`.
- Never call `mmd` (make folder) blindly: if the folder exists it loops on
  a hidden menu. Check first: `mdir ... >/dev/null 2>&1 || mmd ...`.
- Run `sudo -v` once at the top of a script so every later `sudo` reuses
  the password, and send the script's whole output to a log file
  (`{ ...; } > /tmp/name.log 2>&1`) so a result can be read afterwards
  without pasting anything.
- Eject the SD in Finder before putting it back in the console; the game
  writes `d2d.log`, `launcher.log` and saves under
  `Data/ports/diablo2decomp/` and they can be read back the same way.

Where things go on the SD (see `overlay/docs/trimui.md` for the rest):

| What | SD path |
|---|---|
| Launcher | `Roms/PORTS/Diablo II Decomp.sh` |
| Game folder (binary, `data/` with your MPQs) | `Data/ports/diablo2decomp/` |
| Config, saves, game log | `Data/ports/diablo2decomp/.config/d2d/` |
| Box art shown in the Ports list | `Imgs/PORTS/<script name>.png` |

## Estado del trabajo y contexto de la sesión (2026-11-15)

Esta sección es para retomar el trabajo en otra sesión (o con otro agente).
Todo lo de abajo se hizo y se probó en una TrimUI Smart Pro real con CrossMix
OS, salvo lo marcado como "sin probar".

### Repos y ramas

- Este repo: rama de trabajo `experimental/sdl-3.4` (sale de
  `experimental/deps-update`; `main` quedó con SDL 3.2.10 y sin lo de abajo).
- `upstream/` es un **submódulo apuntando a un fork propio**,
  `github.com/metalpapa/d2decomped`, con las mismas ramas (`trimui`,
  `experimental/deps-update`, `experimental/sdl-3.4`). El remoto `fork` es el
  fork; `origin` sigue siendo `psi29a/d2decomped`. Los cambios de código viven
  en el fork; `overlay/patches/` guarda además un parche de respaldo.
- `vendor/handkit` (Handkit de code-beans) tiene cambios locales sin commitear
  para SDL 3.4.20; están guardados como `overlay/handkit-patches/handkit-sdl-3.4.20.patch`
  y `scripts/apply-overlay.sh` los aplica. Si `git status` muestra `m vendor/handkit`
  es esperado.

### Compilar y desplegar

```sh
export HANDKIT_SDK=$PWD/vendor/handkit
cd upstream
TRIMUI_PERF=1 tools/trimui.sh build      # -mcpu=cortex_a53; sin TRIMUI_PERF compila genérico
tools/trimui.sh package                  # build/trimui-pak (binario ya sin símbolos de depuración)
# el binario completo, con símbolos, queda en build/trimui/d2d/apps/d2d/d2d (para llvm-addr2line)
cd .. && overlay/tools/sd-install.sh --binary "upstream/build/trimui-pak/Diablo II Decomp/d2d" \
    --launcher "upstream/build/trimui-pak/Diablo II Decomp.sh" --cfg show_fps=1
```

`overlay/tools/sd-install.sh` es el método de copia a la SD (mtools, ver sección
anterior). Los scripts y binarios sueltos de `/tmp` (`trimui-test-fps.sh`,
`d2d-*-*`) se pierden al apagar la Mac: se regeneran con los comandos de arriba.
La SD debe estar conectada y con la etiqueta `CROSSMIX`.

### Qué se hizo

- **Guardar:** fila "Save" en el menú de pausa (seleccionada por defecto), `sync()`
  tras escribir el `.d2s` (un guardado se perdía por corte de energía), etiqueta
  `SAVE`/`SALVAR` en `overlay/assets/labels/` metida en `trimui_save_patch.mpq`
  (`overlay/tools/mpq_add.c` y `encode_dc6.py` la arman).
- **Idioma:** `lang = ESP` en `d2d.cfg`; textos y arte de menús salen en español.
- **Controles:** A sobre salidas de nivel (cuevas, escaleras); R1 muestra/oculta
  el mapa y los nombres de ítems (`automap_items = 1`); B cierra paneles (también
  el árbol de habilidades) cuando el cursor no está sobre un ítem o habilidad;
  con un ítem en la mano B lo suelta; mantener A con el inventario abierto equipa
  (armadura, armas, escudos, anillos, cinturones); con el baúl abierto mueve el
  ítem entre inventario y baúl (barra de progreso); el cursor salta a huecos
  donde el ítem cabe; el Nigromante levanta esqueletos del cadáver más cercano.
- **Velocidad del juego:** Start > Options > Video Options > Game Speed
  (0.5x-1.5x, el medio es normal; `game_speed` en `d2d.cfg`).
- **Salir:** el launcher arranca `gptokeyb` como Fallout/DevilutionX, así que
  Menu + Start cierra el juego. El botón Menu no llega a SDL (lo toma el
  sistema); dentro del juego hay además un respaldo con Select + Start.
- **Visual:** `scalemode = linear` se ve mejor que `nearest`.
- **Dependencias:** SDL 3.4.20 (Handkit compila sin cambios), zlib 1.3.2.
  OpenAL se queda en 1.24.3 (1.25 necesita módulos C++20 que no funcionan aquí).
- **Rendimiento:** binario sin símbolos (316 MB a 11 MB); suelo con luz con una
  sola escritura de 32 bits por píxel (`Lighting::rgba`, comparado byte a byte
  con el original en `tests/test_tile_blit.cpp`); limpieza del cuadro y lluvia
  más rápidas. De 22 a 27-32 fps en el campamento.
- **Memoria:** los niveles construidos nunca se liberan y se precargan todos los
  vecinos; en 1 GB de RAM la sesión se arrastraba a 3 fps tras ir por un portal.
  Ahora no se precarga con menos de 220 MB libres.

### Diagnóstico (lo que escribe `d2d.log`, en `Data/ports/diablo2decomp/.config/d2d/`)

- `alive: ... (N fps) | render avg=... present avg=...` cada 5 s.
- `phases (ms/frame): clear floor+shadow walls+units post-world hud rain labels wide-copy automap`
  dónde se va el tiempo de dibujado.
- `sys: cpu0=... kHz gov=... temp0=... memavail=... rss=... load=...`: frecuencia,
  temperatura (mili°C), memoria libre y del proceso.
- `pad button N down` / `joystick button N down`: qué botones llegan al juego.
- `show_fps = 1` en `d2d.cfg` dibuja fps y ms arriba a la izquierda.
- Medidas del equipo: CPU fija a 2 GHz en `performance`, 57-67 °C jugando,
  la memoria es lenta (cada pasada completa por el cuadro cuesta ~3 ms).

### Sin probar todavía en la consola

Binario V (el último): mantener A para equipar armas/anillos, B para soltar,
guardar/sacar del baúl con A, B cierra el árbol de habilidades, esqueletos del
Nigromante, Game Speed, Menu + Start (el launcher con `gptokeyb`; `launcher.log`
terminó con `Killed`, que parece ser eso), y que el límite de memoria evite la
caída de fps tras un portal (buscar `memory tight` en el log).

### Pendiente / ideas

- Etiqueta "GUARDAR" real para la fila Save del menú en español (hoy cae a `SAVE`).
- Videos de intro y `keyconfig` siguen fijos en `ENG`.
- Aviso en pantalla cuando falla un guardado (hoy solo va al log).
- El cierre normal del juego aborta en OpenAL (`double free` al destruir el
  contexto); no afecta al guardado. Idea: `alcSuspendContext` antes de destruir.
- Liberar niveles lejanos en vez de solo no precargar (requiere revisar el
  estado por nivel; hoy los niveles construidos se quedan).
- Optimizar paneles (inventario/baúl cuestan 12-20 ms con todo abierto) y los
  ~10 ms de dibujado que aún no están medidos (antes de `render_ingame`).
- Calibración de batería: no hay herramienta conocida en CrossMix; se puede
  loguear voltaje y porcentaje desde `/sys/class/power_supply` si hace falta.
- Subir `main` a SDL 3.4.20 y zlib 1.3.2 cuando haya sesiones largas sin problemas.

## Experimentos: resultados hasta ahora y qué probar después

Protocolo para comparar binarios: mismo lugar (campamento, parado, sin lluvia),
2-3 minutos, `show_fps = 1`, y promediar las líneas `alive:` de `d2d.log`
(`fps`, `render avg`, `present avg`) y `phases`. Sin esto las comparaciones
se confunden con la lluvia, los paneles abiertos y el calor.

### Resultados medidos en la consola

| Prueba | Resultado |
|---|---|
| SDL 3.2.10 a 3.2.30 / 3.4.20 | Funciona con el backend de Handkit sin cambios. El tiempo de dibujado no cambia (CPU); la lluvia se ve más fina y sin tirones. |
| `scalemode = linear` contra `nearest` | `linear` se ve mejor. El escalado `pixelart` de SDL 3.4 existe pero **no se ha probado**. |
| Binario sin símbolos | 316 MB a 11 MB; el `.zip` de 78 MB a 5 MB; copia a la SD mucho más rápida. Sin efecto en fps. |
| Suelo con luz: una escritura de 32 bits por píxel | Mac: 11,5 a 5,7 ms en el benchmark. Consola: render 33-34 a 30-33 ms (5-10 %), menos de lo esperado: no es solo cálculo. |
| Limpiar el cuadro con 32 bits + lluvia por línea | Render promedio 37,4 a 28 ms; 22,7 a 27 fps en el campamento. |
| Perfil en el Mac | El suelo con luz era ~65 % del tiempo de CPU; paredes y sprites poco. |
| Fases en la consola (ms/cuadro, campamento) | limpiar 3,3 · suelo 8-11 · paredes+unidades 4-5 · interfaz 3,5 · copia ancha 2,8 · automapa 1 · presentación 7. Con inventario y baúl abiertos el "post-world" sube a 12-24 ms. |
| CPU / temperatura / memoria | 2 GHz fijo, gobernador `performance`; 57-67 °C jugando; sin throttling visible. Memoria lenta: llenar 2 MB cuesta ~3 ms. |
| Memoria tras ir por portal | RSS 324, 489 y luego 649 MB; libre 473 a 175 MB; después del portal 3 fps y presentación de 96 ms (el sistema sin memoria). Arreglo: no precargar con menos de 220 MB libres. **Sin confirmar en la consola.** |
| LTO | Falla: `libstorm.a` no se puede archivar (el `ar` de Handkit no entiende bitcode). Descartado. |
| Botón Menu | No llega a SDL: solo aparecen los botones normales. Lo toma el sistema; la salida la da `gptokeyb` desde el launcher. |
| `-mcpu=cortex_a53` contra genérico | **Nunca se midió aislado** (siempre cambió algo más a la vez). Pendiente. |

### Pendientes de probar (de más a menos prometedor)

1. **Quitar `--widescreen` del launcher** (o `widescreen = 0`). Menos píxeles
   para suelo, paredes y limpieza, y desaparece la copia ancha: estimado -5 ms
   por cuadro (~15 % más de fps). Costo: franjas negras a los lados.
2. **Evitar la copia ancha sin quitar el widescreen**: dibujar la interfaz con
   desplazamiento directamente en el buffer ancho. Estimado -2,8 ms.
3. **Medir los ~10 ms que faltan**: la suma de fases da ~24 ms y el render
   promedio ~34. Falta separar lo que pasa antes de `render_ingame`
   (`frame_light`, armado de unidades, dibujo del cursor y del contador).
4. **Interfaz y paneles**: `blit_sprite` y `blit_dcc_frame` aplican gamma por
   píxel. Una tabla de 32 bits por paleta (como la del suelo) debería bajar la
   interfaz de 3,5 a ~1,5 ms y los paneles abiertos de 12-24 ms a mucho menos.
5. **Limpiar solo lo que no cubre el suelo**: estimado -2 ms.
6. **Paridad de fps con el procesador**: comparar `-mcpu=cortex_a53` contra
   genérico con el protocolo de arriba; esperado 0-5 %. Si no gana, quitarlo.
7. **Liberar niveles lejanos** en vez de solo no precargarlos (cada nivel
   construido son ~30 MB y no se libera nunca). Hay que revisar qué guarda el
   `World` por nivel antes de borrar uno (punteros `Level*`, monstruos
   muertos, objetos en el suelo).
8. **Subida de la textura (7 ms de `present`)**: probar `SDL_LockTexture` para
   renderizar directo en la textura, o subir solo las filas que cambian. Riesgo:
   la memoria de la textura puede ser lenta para accesos al azar.
9. **Escalado `pixelart` de SDL 3.4** (`scalemode = pixelart`): más nítido que
   `linear` en teoría; solo cuesta tiempo de GPU.
10. **Aviso de tiempos al cargar un nivel** (primer cuadro 1,5-4 s): medir qué
    parte es construir el mapa y cuál es leer los MPQ de la SD; quizá ayude
    guardar una copia de las tablas en un archivo.
11. **Cierre del juego con `alcSuspendContext`** antes de destruir el contexto
    de OpenAL para evitar el abort al salir.
12. **Batería**: loguear voltaje y porcentaje desde `/sys/class/power_supply`
    junto con la temperatura, para ver a qué voltaje se apaga y qué marcaba.

### Cómo anotar los resultados

Cada prueba nueva: una fila en la tabla de arriba con binario/cambio,
promedio de fps y de `render`, y la zona usada. Si algo no mejora, dejarlo
anotado igual (como LTO y el límite de memoria) para no repetirlo.

## Credits

- [D2Decomp](https://github.com/psi29a/d2decomped) by psi29a and
  contributors — GPL-3.0-or-later.
- [Handkit](https://github.com/code-beans/handkit) by code-beans — MIT
  license, for the TrimUI toolchain and SDL3 display backend.

## License

`overlay/tools/trimui.sh` and `overlay/docs/trimui.md` are derived from and
meant to be merged into D2Decomp's own `tools/` and `docs/`, and are licensed
the same way: GPL-3.0-or-later (see [`LICENSE`](LICENSE)). The submodule
under `upstream/` keeps its own license from the psi29a/d2decomped project.
