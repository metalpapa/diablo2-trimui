# TrimUI / CrossMix OS — notas de cómo funcionan los "ports" (PortMaster)

Aprendido instalando y debuggeando el port de Diablo II Decomp
(`~/Documents/diablo2-trimui`) en una TrimUI Smart Pro real con CrossMix OS.
Sirve como referencia para instalar/debuggear CUALQUIER port en esta misma
consola, no solo ese proyecto. Incluye también CÓMO laburamos (el flujo con
el agente), no solo QUÉ aprendimos del dispositivo.

## El dispositivo y cómo acceder a su SD desde la Mac

- La SD aparece como volumen FAT32 llamado **CROSSMIX**, normalmente en
  `/dev/disk14` (el número puede cambiar si se desconecta/reconecta —
  confirmar siempre con `diskutil list external physical` antes de asumir
  el identificador; si no aparece nada, la SD no está conectada).
- **No hace falta montarla en Finder.** Se lee/escribe directo con
  `mtools` (`brew install mtools`), apuntando al disco raw (nota el
  `r` de `rdisk`, no `disk`):
  ```sh
  sudo mdir -i /dev/rdisk14s1 "::/ruta/en/la/sd/"
  sudo mcopy -i /dev/rdisk14s1 "::/ruta/sd/archivo" /tmp/destino
  sudo mdel -i /dev/rdisk14s1 "::/ruta/sd/archivo"
  ```
  El `::` antes de la ruta es la sintaxis de mtools para "la unidad que
  pasé con -i". `sudo -v` al principio del script cachea el password una
  sola vez para todos los `sudo` que vengan después.
- **Gotcha importante:** si el archivo destino ya existe, `mcopy` pregunta
  interactivamente "overwrite y/n?". Si ese comando corre dentro de un
  bloque `{ ... } > log.txt 2>&1`, la pregunta queda enterrada en el log y
  el script parece colgado para siempre (nunca se ve el prompt, nunca se
  puede contestar — esto nos pasó literalmente en esta sesión). Solución:
  **borrar el destino antes de copiar** (`sudo mdel ...; sudo mcopy ...`)
  en vez de confiar en `-o`/`-n`, y redirigir `stdin` desde `/dev/null` en
  el `mcopy` como cinturón y tirantes (`</dev/null` al final del comando).

## Flujo de trabajo con el agente (por qué lo hacemos así)

Patrón que usamos TODA la sesión para no depender de copiar/pegar texto de
la Terminal (el usuario pidió esto explícitamente porque romper/pegar
salidas largas en el chat es molesto y a veces se corrompe):

1. El agente escribe un script `.sh` en `/tmp/` que redirige TODA su
   salida (`stdout` + `stderr`) a un archivo, con un bloque como:
   ```sh
   sudo -v
   {
       echo "haciendo tal cosa..."
       sudo mdir -i /dev/rdisk14s1 "::/algo/"
       echo "Listo."
   } > /tmp/nombre-del-log.log 2>&1
   echo "TERMINADO -- resultado en /tmp/nombre-del-log.log"
   ```
2. Le pide al usuario UNA sola línea para pegar en su Terminal:
   `bash /tmp/script.sh`
3. El usuario corre eso y contesta simplemente "listo" en el chat (no
   pega nada).
4. El agente lee el archivo de resultado directo del disco con su
   herramienta de lectura de archivos (misma Mac, mismo filesystem) — así
   nunca hace falta que el usuario copie/pegue texto largo.
5. Para comandos de build/compilación largos, se usa el mismo truco pero
   en segundo plano (`background: true` en la herramienta de shell del
   agente) y se va revisando el log con `tail`/lectura parcial cada tanto,
   en vez de bloquear esperando.

**Importante**: si el script interactivo necesita que alguien conteste
algo (como el prompt de overwrite de arriba), eso rompe este patrón
completo, porque el prompt queda invisible dentro del archivo de log y
nadie lo puede contestar. Por eso la regla es: **ningún script para el
usuario debe poder quedar esperando un input interactivo** — todo tiene
que ser no-interactivo de punta a punta (borrar antes de copiar, usar
flags de "sí a todo", etc.).

## Estructura real en la SD (confirmada leyendo un port que ya andaba)

```
/Roms/PORTS/<Nombre del Port>.sh      <- launcher, lo que ves en el menú Ports
/Data/ports/<nombrecorto>/            <- AHÍ van los archivos reales del juego
    <binario>
    data/                             <- assets/datos del juego
    .config/<juego>/                  <- saves, config, logs (si el juego usa $HOME)
/Apps/PortMaster/PortMaster/          <- control.txt, funcs.txt, mod_<CFW>.txt
```

**El `.sh` en `Roms/PORTS/` es solo un lanzador finito**, no una carpeta de
juego. `GAMEDIR` casi siempre es una ruta fija tipo
`/mnt/SDCARD/Data/ports/<nombrecorto>` codeada en el script — NO
`$(dirname "$0")`. Esto lo confirmamos leyendo el `.sh` real de
DevilutionX que ya funcionaba en este dispositivo ANTES de tocar nada del
port nuevo — la lección general es: **cuando un port nuevo no sabe dónde
van sus archivos, el atajo es copiar el `.sh` de un port que ya funciona
en esa misma consola y leerlo**, no adivinar ni asumir convenciones
genéricas de PortMaster de internet.

## El launcher típico de un port (PortMaster)

Todos siguen más o menos esta plantilla:

```sh
GAMEDIR="/mnt/SDCARD/Data/ports/<nombre>"
controlfolder="/mnt/SDCARD/Apps/PortMaster/PortMaster"   # o variantes según CFW
. "$controlfolder/control.txt"
. "$controlfolder/mod_${CFW_NAME}.txt"
get_controls
pm_platform_helper "$GAMEDIR/<binario>"
cd "$GAMEDIR" || exit 1
export HOME="$GAMEDIR"
# ... correr el binario, idealmente con salida a un log propio ...
./mibinario --flags > "$GAMEDIR/launcher.log" 2>&1
command -v pm_finish >/dev/null 2>&1 && pm_finish
```

`CFW_NAME` identifica el firmware (CrossMix, NextUI, muOS, knulli, etc.) —
cada uno puede necesitar su propio `mod_<CFW_NAME>.txt`. `gptokeyb`/
`gptokeyb2` traducen el gamepad a teclado/mouse, pero **solo hace falta si
el juego no lee gamepad nativo por SDL** — si ya usa
`SDL_GameControllerX`/`SDL_Gamepad` o similar, no se necesita nada de eso
(confirmado: no lo necesitamos para d2d porque ya lee gamepad SDL3 nativo).

## Gotchas de hardware/Handkit (SDL en esta consola)

- El backend SDL de TrimUI (vía Handkit) **exige una ventana OpenGL ES o
  Vulkan** — crear una ventana "plana" sin flag `SDL_WINDOW_OPENGL` falla
  con `"handkit: requires an OpenGL ES or Vulkan window"`. Si un juego usa
  un renderer por software, hay que forzar ese flag igual al crear la
  ventana cuando el video driver activo es `"handkit"`
  (`SDL_GetCurrentVideoDriver()` == `"handkit"`).
- **No hay teclado físico ni teclado en pantalla (OSK)** para
  `SDL_StartTextInput`. Cualquier pantalla que pida escribir texto (nombre
  de personaje, usuario, etc.) deja al usuario trabado sin forma de
  escribir, y en esta consola eso NO se ve como un error, se ve como que
  el juego "no responde". Si el juego tiene flags de arranque para
  saltear eso (crear perfil/personaje por default), usarlos desde el
  launcher la primera vez (ej: detectar con `[ -z "$(ls -A save-dir)" ]`
  si es la primera corrida y pasar flags tipo `--start-name Foo`).
- Un cross-compilador genérico (`aarch64-linux-gnu-gcc` de cualquier
  distro) casi siempre linkea contra un glibc más nuevo que el del
  firmware → falla al arrancar con `GLIBC_2.NN not found`. Esta consola
  necesita **glibc 2.33** específicamente (confirmado contra la tabla
  propia de `harbourmaster`, el instalador real de PortMaster). Para
  compilar cosas nuevas para esta consola usamos el toolchain de
  [Handkit](https://github.com/code-beans/handkit) (Zig/Clang 19 pinned),
  no un gcc cualquiera.

## Empaquetado PortMaster (formato real, no el de la doc pública)

Reverse-engineered leyendo el `harbourmaster` real que viene en CrossMix OS
(`Apps/PortMaster/PortMaster/pylibs/harbourmaster/`), no solo la doc:

- Un zip de port = una o más carpetas de primer nivel + uno o más `.sh` de
  primer nivel (ningún `.sh` puede estar DENTRO de la carpeta).
- `<nombre>.port.json` adentro de la carpeta es el manifest (`name` e
  `items` se recalculan solos al instalar, no hace falta declararlos).
- Poner el zip en `Apps/PortMaster/PortMaster/autoinstall/` y abrir
  PortMaster lo instala solo al siguiente arranque de la app — así aparece
  "mágicamente" en el catálogo sin tocar nada más.
- Alternativa sin PortMaster (la que usamos para iterar rápido mientras
  developábamos): copiar el `.sh` + su carpeta directo a mano a
  `Roms/PORTS/` con mtools. CrossMix, NextUI, muOS y knulli escanean esa
  carpeta igual, sin pasar por PortMaster para nada.

## Pendiente / no confirmado todavía

- **Carátulas/preview en el menú de Ports**: todavía no sabemos con certeza
  qué convención usa CrossMix OS para mostrar una imagen linda en la lista
  de Ports (¿`Roms/PORTS/Imgs/<nombre>.png`? ¿algo del propio
  `port.json`/`gameinfo.xml`?). Ninguno de los dos ports de Diablo que
  probamos tiene esto resuelto. Si se investiga, documentar acá el
  resultado.

## Debuggeando crashes sin herramientas de verdad en la consola

Esta consola no tiene gdb ni muestra ningún cartel de error al explotar un
programa — simplemente el proceso muere y el juego "se cierra solo", sin
ningún aviso visual ni sonido. Esto nos pasó real: un crash pasaba siempre
al hacer "Guardar y salir" y el usuario ni se había dado cuenta de que era
un crash, pensaba que el juego había cerrado normal. **Regla general: en
esta consola, "el juego se cerró solo" = sospechar crash silencioso hasta
que el log diga lo contrario.**

Receta que funcionó para diagnosticarlo:

1. El launcher `.sh` redirige TODO el stdout/stderr del binario a un
   archivo de log propio (`> "$GAMEDIR/launcher.log" 2>&1`, con un solo
   `>` — importante que sea UNO, no `>>`, para que se pise en cada
   corrida y así cada log que bajamos es garantizado de la última sesión,
   nunca mezclado con una vieja).
2. Si el crash es un segfault y hace falta saber DÓNDE pasó, agregarle al
   programa un handler de señal. Primer intento con el `signal()` clásico
   + `backtrace()`/`backtrace_symbols_fd()` SIRVIÓ PARA DETECTAR el crash
   (vimos `Segmentation fault` y que coincidía con el cambio de pantalla),
   pero NO sirvió para ubicar la línea exacta: el backtrace solo traía 2
   frames (el handler mismo y el trampolín de la señal del kernel), no
   podía cruzar para llegar a la instrucción real que explotó.
3. La solución que sí funcionó: usar `sigaction(..., SA_SIGINFO, ...)`
   (NO el `signal()` viejo) para que el handler reciba un tercer
   parámetro `void* ucontext`, castearlo a `ucontext_t*` y leer
   `uc_mcontext.pc` (en Linux/aarch64) — esa SÍ es la dirección exacta de
   la instrucción que explotó, sin depender de que el unwinder pueda
   caminar la pila. Patrón en C (válido para cualquier port en Linux):
   ```c
   #include <signal.h>
   #include <ucontext.h>
   #include <execinfo.h>
   #include <unistd.h>

   void crash_handler(int sig, siginfo_t *info, void *ucontext_ptr) {
       ucontext_t *uc = (ucontext_t *)ucontext_ptr;
       unsigned long fault_pc = uc->uc_mcontext.pc;   // la direccion real
       // escribir fault_pc a stderr acá con write() (async-signal-safe,
       // nada de printf/malloc adentro de un signal handler)
       signal(sig, SIG_DFL);
       raise(sig);   // para que el proceso siga muriendo normal después
   }

   struct sigaction sa = {0};
   sa.sa_sigaction = crash_handler;
   sa.sa_flags = SA_SIGINFO;
   sigemptyset(&sa.sa_mask);
   sigaction(SIGSEGV, &sa, NULL);
   ```
4. Compilar sin stripear símbolos (build Release normal ya alcanza,
   mientras no se pase `-s`/`strip` al final).
5. Con la dirección cruda que apareció en el log (ej. `0x1363434`),
   resolver el nombre de función + archivo + línea en la Mac contra el
   binario SIN stripear del build local (el mismo binario, antes de
   copiarlo a la SD):
   ```sh
   # brew install llvm   (si no está instalado)
   /opt/homebrew/opt/llvm/bin/llvm-addr2line -f -C \
       -e /ruta/al/binario/sin_strip \
       0x1363434
   ```
   `llvm-addr2line` no necesita que la Mac sea aarch64 ni nada especial —
   solo lee la tabla de símbolos/DWARF del binario, funciona cross-arch.

## Gotcha de macOS al correr scripts bash (nada que ver con TrimUI)

El bash que trae macOS por default (`/bin/bash`, el único que encuentra el
agente si no hay homebrew bash en el `PATH`) es la **versión 3.2.57**
(Apple la congeló ahí por licencia GPL). Con `set -u`/`nounset` activado,
esa versión tiene un bug conocido: `"${array[@]}"` sobre un array
declarado vacío (`array=()`) tira `"array[@]: unbound variable"` en vez de
expandir a nada. Si un script de build de terceros usa ese patrón y
revienta con ese error random, no es un bug del script — es este bug
viejo de bash 3.2. Soluciones: correr el script con un bash más nuevo
(`brew install bash`) o parchear esa línea a
`"${array[@]+"${array[@]}"}"`.

## Comandos sueltos que sirven siempre

```sh
# Ver qué disco es la SD (el identificador puede cambiar)
diskutil list external physical

# Listar una carpeta de la SD sin montarla
sudo mdir -i /dev/rdisk14s1 "::/Data/ports/"

# Copiar un archivo DESDE la SD (borrando destino antes, sin prompts)
rm -f /tmp/destino.log
sudo mcopy -i /dev/rdisk14s1 "::/Data/ports/juego/archivo.log" /tmp/destino.log </dev/null

# Copiar un archivo HACIA la SD (idem, borrar destino en la SD antes)
sudo mdel -i /dev/rdisk14s1 "::/Roms/PORTS/Juego.sh" 2>&1 || true
sudo mcopy -i /dev/rdisk14s1 "/ruta/local/Juego.sh" "::/Roms/PORTS/Juego.sh" </dev/null

# Resolver una dirección de crash contra un binario ARM sin stripear, desde la Mac
/opt/homebrew/opt/llvm/bin/llvm-addr2line -f -C -e ./binario_sin_strip 0xDIRECCION
```

---
_Escrito 2026-11-14 durante el port de Diablo II Decomp a TrimUI. Actualizar
este archivo si se aprende algo nuevo instalando otros ports en la misma
consola — es la idea, que crezca con cada port nuevo._
