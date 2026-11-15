# STATUS — resume-from-here notes

Written mid-session because the agent session can die at any point and this
is the single source of truth for "what's done" vs "what's left". Read this
before re-reading chat history.

**This machine already has everything installed** to resume immediately:
Homebrew, `cmake`, `ninja`, `conan` 2.34, a cloned+configured Handkit at
`~/Documents/handkit`, and this repo at `~/Documents/diablo2-trimui` (`origin`
= `https://github.com/metalpapa/diablo2-trimui.git`). Also installed this
session: `openal-soft` (brew, keg-only) and Pillow (`pip3 install --user`),
for the native-build smoke test in Milestone 4 below -- neither is needed for
the actual TrimUI cross-build, only for testing d2d natively on this Mac.
"Resuming on a fresh machine" below has from-scratch steps if this
machine/session is gone.

## Milestone: `tools/trimui.sh all` succeeds end to end

As of 2026-11-14, a full `./tools/trimui.sh build && ./tools/trimui.sh package`
run completes with **no errors**, producing a real aarch64 Linux ELF binary:

```
upstream/build/trimui/d2d/apps/d2d/d2d
  ELF 64-bit LSB executable, ARM aarch64, ... for GNU/Linux 2.0.0
upstream/build/trimui-pak/
  Diablo II Decomp/d2d          (301.7 MB, unstripped/debug build)
  Diablo II Decomp.sh           (PortMaster launcher)
  README-trimui.txt             (first-run setup instructions)
```

This is everything described as "proven so far" in earlier revisions of this
file, **plus** the FFmpeg cross-compile bug below is now fixed, **plus**
`tools/trimui.sh package` (previously untested) works.

**Still true: nobody has run this on real TrimUI hardware.** The build
compiling and linking cleanly is strong evidence, not proof — see "What
hasn't been attempted at all" below for what real verification still needs.

## The four build bugs found and fixed (all applied in `overlay/`)

1. **Conan context bug**: `handkit-toolchain` must be `[tool_requires]`, not
   `[requires]` (`overlay/tools/trimui.sh`'s generated `conanfile.txt`).
2. **CMake C++20 module scanning**: fixed by pinning OpenAL Soft to 1.24.3
   instead of 1.25.x (see VERSIONS.md for why).
3. **C++ standard downgrade**: Conan's toolchain sets `CMAKE_CXX_STANDARD 17`
   as a plain variable, shadowing D2Decomp's own C++23 requirement. Fixed
   with a tiny generated wrapper toolchain file in `overlay/tools/trimui.sh`
   (`include()`s Conan's toolchain, then raises the standard back to 23).
4. **FFmpeg's `sys/sysctl.h` false positive** (the one this session fixed —
   see next section).

Also: `-DD2D_WERROR=OFF` sidesteps an unrelated harmless warning (Conan's
toolchain passes an explicit `-stdlib=libc++` Zig's driver already defaults
to; D2D's own code is `-Werror` otherwise). Sanctioned escape hatch per
D2Decomp's own CONTRIBUTING.md.

### Bug #4 in detail: FFmpeg's `sys/sysctl.h`, fixed via `overlay/patches/`

`libavutil/cpu.c` does `#if HAVE_SYSCTL / #include <sys/sysctl.h>`. FFmpeg's
`configure` sets `HAVE_SYSCTL=1` from a **link-only** test (`check_func
sysctl`, no header check) that false-positives against some aarch64-linux-gnu
toolchains' glibc stub — including Zig's (targeting glibc 2.33, what the
TrimUI firmware has) — even though `sys/sysctl.h` doesn't exist for that
target. D2Decomp's own `apps/d2d/CMakeLists.txt` already solves this exact
false positive for `NINTENDO_SWITCH` (libnx has the same symbol-without-
header situation) by writing an **empty** `sys/sysctl.h` into a generated
include dir and passing it via `--extra-cflags=-I...`. The fix applied here
mirrors that, in the generic `CMAKE_SYSTEM_NAME=Linux` branch (the one any
aarch64-linux-gnu cross target, not just TrimUI, takes):

```cmake
if(ffmpeg_os STREQUAL "linux")
    file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/linux-no-sysctl-include/sys/sysctl.h" "")
    list(APPEND ffmpeg_options
        "--extra-cflags=-I${CMAKE_CURRENT_BINARY_DIR}/linux-no-sysctl-include")
endif()
```

It's safe: `av_cpu_count()`'s `sysctl()` branches in `cpu.c` are gated on
`HW_NCPU`/`HW_NCPUONLINE`, macros only a *real* `sys/sysctl.h` would define,
so the empty header never makes that code path compile in — and Linux always
takes the `HAVE_SCHED_GETAFFINITY` branch above it in `cpu.c` anyway.

**Dead end tried first, for the record**: `--disable-sysctl` /
`--disable-sysctlbyname` on FFmpeg's configure command line. These look like
valid flags (`sysctl` is in FFmpeg's internal `HAVE_LIST`) but FFmpeg's
`configure` only accepts `--enable-X`/`--disable-X` for names in
`$COMPONENT_LIST` or `$CMDLINE_SELECT` — plain `HAVE_LIST` items aren't
configurable from the command line at all, so this fails with `Unknown
option "--disable-sysctl"`. Don't redo this.

**Why this is a patch, not a `trimui.sh` flag**: there's no existing
`D2D_FFMPEG_EXTRA_OPTIONS`-style CMake hook to inject this from outside, and
patching FFmpeg's own *source* (vs. D2Decomp's small, well-commented
`CMakeLists.txt`) would break the checksum story in VERSIONS.md. The patch
lives in `overlay/patches/d2d-ffmpeg-no-sysctl.patch`, applied automatically
and idempotently by `scripts/apply-overlay.sh` (safe to re-run; it checks
`git apply --reverse --check` first and skips if already applied). This is
exactly the kind of one-line, additive, well-justified change D2Decomp's own
`NINTENDO_SWITCH` branch already demonstrates they're open to upstreaming —
worth offering as a PR once hardware testing confirms the rest works.

### Also fixed this session: a stale-absolute-path build cache

Unrelated bug, not a code fix: `build/trimui/d2d/` (gitignored, pure cache)
still had `/private/tmp/d2port/...` absolute paths baked into its
`CMakeCache.txt`/subbuild dirs from before this repo moved to
`~/Documents/diablo2-trimui` on 2026-11-14 (see VERSIONS.md commit history).
`cmake --fresh` only resets the *top-level* cache, not FetchContent's nested
subbuild dirs (e.g. `_deps/stormlib-subbuild`), so it errored with "current
CMakeCache.txt directory is different than...". Fixed by moving (not
deleting — build caches are safe to lose, but this was also just quicker)
`build/trimui/d2d` out of the way and letting the next build regenerate it
from scratch. If this resurfaces: delete/move `build/trimui/d2d` (NOT the
whole `build/trimui/`, which still has the slower-to-rebuild OpenAL/zlib/
bzip2 pieces cached) before rebuilding.

## Milestone 2: real PortMaster packaging, verified against real PortMaster code (2026-11-14)

The user asked how this compares to installing a normal PortMaster port
(e.g. DevilutionX, where you drop a file and PortMaster auto-installs it
into its own catalog) and pointed out they have a real CrossMix OS build
locally (`~/Downloads/CrossMix-OS_v1.3.0.zip`/`CrossMix-OS_v1.3.0/`). That
turned out to be the single best resource available: it bundles PortMaster's
actual Python backend (`harbourmaster`), so instead of guessing the on-disk
format from scattered public docs, **the real install-validation code could
be run directly** against this repo's own package output.

**What changed**: `tools/trimui.sh package` now also writes:

- `Diablo II Decomp/diablo2decomp.port.json` -- the PortMaster v3 manifest
  (`title`, `desc`, `inst`, `genres`, `porter`, `min_glibc: "2.33"`, `exp:
  true`, `rtr: false`).
- A rewritten `Diablo II Decomp.sh` using PortMaster's own generic
  controlfolder-detection (copied verbatim from its `PortMaster.sh`), so it
  works identically whether PortMaster installed it or it was hand-copied.
  Gracefully degrades (plain `echo`/direct launch) if PortMaster isn't
  present at all. No `gptokeyb`/`gptokeyb2` -- see below.
- `Diablo II Decomp.zip` -- the real installable artifact: drop it in
  `PortMaster/autoinstall/` and opening PortMaster installs it automatically,
  same UX as any other port (including DevilutionX, what the user compared
  it to). The unzipped folder + script are still written too, for a manual
  `Roms/PORTS/` copy without PortMaster at all.

**How this was verified without hardware** (as close to real validation as
possible from a dev machine): the user's CrossMix build's
`Apps/PortMaster/PortMaster/pylibs/harbourmaster/` was used directly --

```python
import sys; sys.path.insert(0, ".../CrossMix-OS_v1.3.0/Apps/PortMaster/PortMaster/pylibs")
from harbourmaster.captain import check_port          # the real zip validator
from harbourmaster.util import match_requirements, version_parse

info = check_port("Diablo II Decomp.zip", "Diablo II Decomp.zip")   # parses clean
# ... simulated TrimUI Smart Pro capabilities + glibc 2.33 ...
# -> "would be shown to a TrimUI Smart Pro user: True"
```

(needed `pip install loguru requests colorama ansimarkup` on the host to
import harbourmaster standalone -- these are PortMaster's own runtime deps,
nothing added to this repo).

**Key findings from reading the real source** (full citations and
reasoning in `docs/trimui.md`'s new "PortMaster packaging" section and
inline in `trimui_package()`):

1. A port zip = 1+ top-level dirs + 1+ top-level `*.sh` scripts; the
   `<name>.port.json` manifest sits inside the dir. `name`/`items` in it
   are always recomputed by harbourmaster from the zip itself.
2. `min_glibc` is checked against a real per-device table that has
   `"trimui-*": "2.33"` -- **independent confirmation from PortMaster's own
   code that Handkit's glibc 2.33 pin (VERSIONS.md) is exactly correct**,
   not just an assumption this project made on its own.
3. **No gptokeyb/gptokeyb2 needed.** That tool translates gamepad input
   into synthetic keyboard/mouse events, for ports of PC games that only
   understand a keyboard. Confirmed by reading `apps/d2d/gamepad_map.hpp`:
   d2d already reads SDL3 gamepad input natively (same as its Vita/Switch
   builds), so there's no translation layer to add. This also means no
   `gamecontrollerdb.txt` entry or `.gptk` mapping file was needed -- SDL3
   itself handles controller mapping.
4. `PortMaster/autoinstall/` (literally a folder containing
   `place-zips-here-for-autoinstallation.txt` in the real install) is where
   you drop a zip for the next PortMaster launch to auto-install it --
   confirmed straight from `PortMaster.sh`'s own "Autoinstallation Code"
   section, not inferred.

**Still not there**: nothing blocking, genuinely cosmetic only -- a nicer
(non-placeholder) icon if someone wants to commission/draw one later.

**Not done, and can't be done without hardware**: actually running the
install. Everything above is "PortMaster's own code says this is a valid,
installable, compatible port" -- which is much stronger evidence than
before, but still not the same as a confirmed install + launch on a real
TrimUI.

## Milestone 3: first real boot on actual TrimUI hardware (2026-11-14)

The user had a real TrimUI (Smart Pro/Brick, CrossMix OS) connected over USB.
Mac's corporate policy blocks writing to mounted USB volumes, so the whole
session wrote to the SD card's **raw device** (`/dev/rdiskNsN`, after
`diskutil unmount`) via Homebrew's `mtools` (`mdir`/`mcopy`/`mmove`/`mmd`),
never a normal mount. User ran every privileged command themselves in their
own Terminal (scripts redirect output to `/tmp/*.log` for the agent to read
back directly, since there's no TTY for `sudo` from this session otherwise).

**Found and fixed four real bugs, all by reading this exact device's own
real, already-working files (CrossMix's `control.txt`, a working
`Devilutionx.sh`, Handkit's own video driver source, and d2d's own source)
instead of guessing:**

1. **Wrong `Roms/PORTS` layout.** Initially assumed a self-contained
   `Roms/PORTS/Diablo II Decomp.sh` + `Roms/PORTS/Diablo II Decomp/` (binary
   + data together) -- the generic PortMaster convention. **Wrong for this
   device**: reading a real, working `Devilutionx.sh` off the SD showed
   `Roms/PORTS/*.sh` is only a thin launcher stub; the actual game folder
   lives at a **fixed, separate path**, `/mnt/SDCARD/Data/ports/<name>/`
   (`control.txt`'s `directory="mnt/SDCARD/Data"` + `/ports/<name>`).
   Likely why the first real launch attempt just silently closed instantly.
   Fixed: `GAMEDIR` in the generated `.sh` is now the fixed absolute path
   `/mnt/SDCARD/Data/ports/diablo2decomp` (not `$(dirname "$0")/...`).
   Manual-copy instructions now say to copy the `.sh` to `Roms/PORTS/` and
   the folder's **contents** to `Data/ports/diablo2decomp/` separately.
   **Not yet re-verified for the PortMaster-autoinstall `.zip` path** --
   `harbourmaster`'s `PlatformTrimUI` code moves things around on install
   too (`platform.py`'s `add_port_script`/`trimui-port-mode` config), unclear
   if it lands in the exact same place; only the manual-copy path has been
   hardware-tested so far.
2. **Handkit requires an OpenGL ES/Vulkan window, always.** Real crash log
   (`.config/d2d/d2d.log`, pulled off the SD): `SDL_CreateWindow: handkit:
   requires an OpenGL ES or Vulkan window`. Confirmed in Handkit's own
   source (`sdl_handkit_video.c`'s `HkCreateWindow`): it rejects any window
   without `SDL_WINDOW_OPENGL`/`SDL_WINDOW_VULKAN` -- no software/framebuffer
   path exists at all. d2d's `window.hpp` created a plain window (fine on
   every other platform, where `SDL_CreateRenderer(window, nullptr)` picks
   software automatically). Fixed with a new overlay patch,
   `overlay/patches/d2d-handkit-gl-window.patch`: adds `SDL_WINDOW_OPENGL`
   to the window's flags **only** when `SDL_GetCurrentVideoDriver()` returns
   `"handkit"`, so every other platform is untouched. This is a genuine
   upstream-worthy fix (small, additive, well-justified) -- same spirit as
   the FFmpeg sysctl patch.
3. **No on-screen keyboard under Handkit.** Character creation needs to type
   a name (`SDL_StartTextInput`); confirmed by grep that Handkit has no
   on-screen-keyboard implementation at all (d2d's own comment: "A Steam
   Deck has no keyboard: SDL_StartTextInput opens Steam's own [OSK]" --
   Handkit has nothing equivalent). The game would hang on that screen with
   no way to type and no way to back out (see bug #4). Worked around, not
   fixed: the generated launcher now checks if `$GAMEDIR/.config/d2d/save/`
   is empty, and if so passes d2d's own `--start-screen charcreate
   --start-class 0 --start-name Kain` (same flags d2d already documents for
   Steam Deck/console builds) to auto-create one character with no typing.
   Every later launch sees that save and goes to the normal, gamepad-only
   character-select screen. A real on-screen keyboard (in Handkit, or a
   gamepad-driven one in d2d itself) is the actual fix, not attempted here.
4. **No visible error on crash at all.** This frontend shows nothing on
   screen if the launched game exits early -- the first crash (bug #1) was
   invisible, "it just closed," with no on-screen message. The only reason
   it was diagnosable at all was pulling `.config/d2d/d2d.log` off the raw
   SD card after the fact. Fixed going forward: the launcher now redirects
   `./d2d ...` to `$GAMEDIR/launcher.log` (stdout+stderr), alongside d2d's
   own log, for next time.

**Confirmed working on real hardware after the fixes above**: the game
boots, loads all MPQs, builds the world (Blood Moor), renders on screen,
auto-creates a character, and is playable with a controller.

**Two known issues found during this same real-hardware session, not yet
fixed (logged here, not blocking)**:

- **Menu+Start doesn't exit the game** (the usual PortMaster hotkey combo);
  user has to power off the console. Not yet root-caused with certainty, but
  the leading theory: that combo is commonly implemented by `gptokeyb`/
  `gptokeyb2` watching for it and killing the game process -- and this port
  deliberately doesn't run gptokeyb2 at all (d2d reads SDL3 gamepad input
  natively, see Milestone 2), so it may have lost that hotkey "for free" by
  skipping gptokeyb2. Needs real investigation (check `oga_events`/evdev
  grab behaviour), not guessed at further yet.
- **FIXED (2026-11-14, built, not yet confirmed on device): UI text shows in
  English despite Spanish (es-ES) game data; audio is correctly Spanish.**
  `d2d.cfg` now takes `lang = ESP` (default `ENG`), threaded through every
  `data\local\{LNG,UI}\<lang>\` read (`overlay/patches/
  d2d-trimui-save-lang-input.patch`). Menu labels missing under `<lang>`
  fall back to `ENG`. Original root cause follows. Root-caused by reading `apps/d2d/load.cpp`: specific
  UI graphics (e.g. line 218, `data\local\UI\ENG\...dc6`) are **hardcoded**
  to the English locale subfolder, regardless of which language's MPQs are
  installed -- this is a real, confirmed, *undocumented* upstream d2d
  limitation (not a packaging bug, not fixable by swapping game files).
  Spoken audio and most string-table-driven text (quest text, etc., sourced
  by ID from `string.tbl`, not hardcoded to ENG) should still be correctly
  Spanish; only specific baked-in UI art uses the hardcoded path. Properly
  fixing this means detecting the installed locale dynamically (probe which
  `data\local\UI\<LANG>\` subfolder actually exists in the loaded MPQs) and
  threading that through every hardcoded `ENG`/`LATIN` path -- a real, non-
  trivial upstream fix, not attempted tonight.

**Third known issue, found and root-caused 2026-11-14 (crash-on-quit, not
blocking)**: exiting from in-game back to the title screen ("Save and
Exit") reliably crashes the process with glibc's `double free or
corruption (!prev)` -> `SIGABRT`, 100% reproducible across 3 separate real-
hardware runs. Root-caused with a custom crash handler (`sigaction` +
`SA_SIGINFO`, reading `ucontext_t.uc_mcontext.pc` -- see
`PORTMASTER-NOTES.md` for the general technique) plus `llvm-addr2line`
against the unstripped local build. The backtrace is entirely inside
OpenAL Soft's own teardown, not d2d's game logic:
```
d2d::client::Audio::~Audio() (apps/d2d/audio.hpp:164)
  -> ALCcontext::~ALCcontext() (OpenAL's context.cpp:157)
    -> destroying its Voice array
      -> each Voice's std::unique_ptr<DecoderBase> (OpenAL's own ambisonic/
         UHJ decoder, core/uhjfilter.h) double-freed on reset
```
Leading theory: OpenAL Soft runs its mixer on a background thread; `Audio::
~Audio()` stops sources and waits on `music_job`, but never calls
`alcSuspendContext(ctx)` before `alcDestroyContext(ctx)` -- if the mixer
thread is still touching a Voice's decoder at that exact moment, that's a
classic teardown race ending in a double free. Not yet fixed (one-line,
low-risk candidate fix: `alcSuspendContext(ctx)` before stopping sources),
because **it has zero observable effect on the player**: the character
save already happens before this point in every run (`save Kain: written`
in the log precedes the crash every single time), and `Diablo II Decomp.sh`
has no `set -e`/exit-code check around the `./d2d ...` call -- `pm_finish`
runs unconditionally right after, so control returns to the frontend menu
exactly like a clean exit either way. Left as a known, documented,
non-blocking bug per the user's call; revisit if real audio glitches show
up (none observed/expected during actual play, since this only triggers
at the very end of the process's life).
- **No FPS counter exists in d2d** (only `--fps-cap`, a *limiter*, not a
  *display*) -- confirmed by grep, nothing to enable. Can't currently
  quantify a reported "rain effect feels laggy" -- noted, not measured.

## TrimUI-only additions in `d2d-trimui-save-lang-input.patch` (2026-11-14)

- **"Save" row in the pause menu** (`gamemenu.cpp`, `town/update.cpp`):
  saves and closes the menu without leaving the game. Its label art is a
  custom `data\local\UI\ENG\Save.dc6` in `trimui_save_patch.mpq` (the real
  `patch_d2.mpq` plus that file, set via `d2d.cfg`'s `patch =`). Only ENG
  exists, so it reads "SAVE" even with `lang = ESP`; a Spanish label is
  not made yet.
- **`sync()` after the save's `rename()`** (`character_store.hpp`): a save
  that logged success was lost on a hard power-cycle because Linux hadn't
  flushed the FAT32 SD card.
- **Default bindings**: right trigger moved from Primary to Skill Picker.
- **Crash handler** (`main.cpp`): dumps the faulting PC and backtrace to
  stderr (`launcher.log`). Debug aid, TrimUI bring-up.
- **Entering/leaving dungeons with the pad**: level exits (cave mouths, stairs)
  are now pickable by A like NPCs/objects (`pad_pick`, ids <= -4000); A walks
  through them with the same click the mouse sends. Before, only the mouse
  could take a warp.
- **R1 shows/hides ground item names with the automap** (`d2d.cfg`
  `automap_items = 1`, `Town::items_sticky`).
- **Box art**: `overlay/assets/*-boxart.png` (640x480) go to
  `/Imgs/PORTS/<script name>.png` on the SD.

- **Menu + Start exit chord (2026-11-15):** confirmed by reading Fallout's and
  DevilutionX's launchers on the device: they start `$GPTOKEYB "<process>" &`
  (with no config for DevilutionX), and that tool kills the game on the
  chord. The launcher now does the same for `d2d` (guarded by
  `[ -n "$GPTOKEYB" ]`); d2d still reads the pad natively. The in-game
  Menu/Select + Start hold in `main.cpp` stays as a fallback.

## What hasn't been attempted at all yet

- **Anything on real TrimUI hardware**: display, audio, controls,
  performance, save/load. Nobody has run this on a device. This is the one
  remaining unknown that actually matters — everything else in this file is
  "it compiles," not "it works."
- Copying `Diablo II Decomp.zip` (or the manual folder, both already have
  real game data staged -- see below) onto a TrimUI's SD card and installing
  it via PortMaster's `autoinstall/` or a plain `Roms/PORTS/` copy.
- Submitting the FFmpeg/sysctl fix upstream to `psi29a/d2decomped` as a PR
  (and the `--update-lock` gotcha to `code-beans/handkit`, see Milestone 3).
  Not done without asking first: filing issues/PRs on someone else's repo
  under the user's identity is more consequential than a local commit.
- A real Linux (not macOS) save/reload check via
  `tools/validate-linux.Dockerfile` (needs `docker` on this machine first) --
  see Milestone 4's "Tried and stopped short".

## Reference material available locally (found this session)

- `~/Documents/devilutionx-reference` — a shallow clone of
  [diasurgical/devilutionx](https://github.com/diasurgical/devilutionx) (the
  open-source Diablo I port), at the user's suggestion. Not inspected in
  depth; no TrimUI-specific code found in a first pass (`grep -i trimui`
  came up empty) — useful by analogy (packaging conventions for other
  CFWs, e.g. `Packaging/miyoo_mini/skeleton_OnionOS/`), not copy-paste.
- `~/Downloads/CrossMix-OS_v1.3.0.zip` / `CrossMix-OS_v1.3.0/` — a real
  CrossMix OS build the user has locally. **This is what actually made the
  PortMaster packaging work verifiable** (see the Milestone 2 section
  above) — its `Apps/PortMaster/PortMaster/pylibs/harbourmaster/` is
  PortMaster's real install-time validation code, runnable standalone on a
  dev machine with a few `pip install`s. Worth remembering for any future
  CrossMix/TrimUI-specific question: check this local copy before
  searching the web, it's authoritative and offline.

## Game files: verified genuine, extracted, and staged (2026-11-14)

`~/Downloads/Diablo II Complete (2000-01) [es-ES digital release] V1.12-1.14d/`
turned out to need no installer run at all: despite being named like
installers, `*.mpq` in that folder **are themselves real MPQ archives**
(confirmed with `file` -> "MoPaQ (MPQ) archive", not an InstallShield/Inno
format as first assumed) that directly contain the final game MPQs, readable
with the pure-Python `mpyq` library (`pip install mpyq`) with no D2
installation needed:

| Tome | Contains |
|---|---|
| `D2 .../Installer Tome.mpq` | `d2data.mpq`, `d2sfx.mpq`, `d2speech.mpq` |
| `D2 .../Installer Tome 2.mpq` | `d2video.mpq` |
| `D2 .../Installer Tome 3.mpq` | `d2char.mpq`, `d2music.mpq`, `patch_d2.mpq` (base) |
| `D2ES .../Installer Tome.mpq` | `D2xMusic.mpq`, `D2xVideo.mpq`, `d2exp.mpq`, `d2xtalk.mpq`, `patch_d2.mpq` (LoD) |

All 12 extracted cleanly (`file` confirms every one is a valid MoPaQ archive,
right sizes — e.g. `d2video.mpq` at ~595 MB, `d2data.mpq` at ~257 MB, both in
line with known real D2 file sizes). **These are the real thing, not
placeholders or corrupted downloads.**

Two `patch_d2.mpq` exist (base install's, 8 MB; LoD's, 2 MB) because that's
how the real Blizzard installer works too — LoD installs over the base game
and its own `patch_d2.mpq` is the one that's actually left in place
afterward, so **the LoD one is what got staged** (matches this archive's own
"V1.12-1.14d" naming: base 1.12 + LoD's bundled patch = 1.14d final).

**Found and fixed a real bug while verifying this**: `overlay/tools/trimui.sh`'s
generated `README-trimui.txt` was missing `d2char.mpq` from the required-files
list, even though `gamedata_load.cpp` calls `required("d2char.mpq")` (character
animations — not optional, a miss there isn't a silent skip). Fixed; also
added a note that filenames must be lowercase (confirmed in code: a Linux-only,
case-sensitive filesystem won't find `D2xVideo.mpq`/`D2xMusic.mpq` as shipped
by the installer archive — `install-detect.md` even lists "case-insensitive MPQ
names" as a still-open loader TODO, so this isn't handled automatically yet).

**Staged for hardware testing**: all 10 required MPQs + `d2char.mpq`, correctly
renamed to lowercase, are sitting in
`upstream/build/trimui-pak/Diablo II Decomp/data/` (~2.0 GB, gitignored —
never committed, per LEGAL.md, and **excluded from `Diablo II Decomp.zip`** --
`trimui_package()` strips `*.mpq`/`*.MPQ` when zipping, see Milestone 2).
**Re-running `tools/trimui.sh package` wipes and recreates this folder**
(`rm -rf "$pak"`), so if that's run again, re-copy the MPQs back in from
`/tmp/d2-extract-test/` (if that machine/session still has it) or re-extract
them fresh with the `mpyq` snippet above before copying anything to hardware.
The whole `trimui-pak/` folder (manual copy *or* `Diablo II Decomp.zip`) is
ready to go the moment there's actual hardware to test on.

## Resume commands (same machine)

```sh
cd ~/Documents/diablo2-trimui
./scripts/apply-overlay.sh         # re-copy tools/trimui.sh + apply overlay/patches/
cd upstream
export HANDKIT_SDK=~/Documents/handkit
./tools/trimui.sh all 2>&1 | tee ~/Documents/trimui-build-resume.log
```

Incremental (Ninja + cached Conan packages): a clean rerun should finish in
well under a minute once OpenAL/zlib/bzip2/FFmpeg's install markers exist.

## Resuming on a fresh machine (if this one/its /tmp is gone)

**Verified end to end this session** (2026-11-14): cloned fresh to `/tmp`,
ran the steps below exactly, got a clean `d2d` build and `trimui-pak/`
(incl. `Diablo II Decomp.zip`) with zero actual errors -- see Milestone 3
below for the one gotcha this surfaced and fixed in step 4.

```sh
git clone --recurse-submodules https://github.com/metalpapa/diablo2-trimui.git
cd diablo2-trimui
brew install cmake ninja conan
conan profile detect --force
./scripts/apply-overlay.sh
cd vendor/handkit && ./tools/handkit configure --update-lock && cd ../..
export HANDKIT_SDK=$PWD/vendor/handkit
cd upstream && ./tools/trimui.sh all
```

(Handkit's Conan packages aren't vendored as binaries — only their
*sources* are, in `vendor/sources/` — so a fresh machine's first build still
compiles Zig/SDL3 from those vendored sources, not downloads them again.)

## Milestone 3: fresh-machine dry run, actually done (2026-11-14)

STATUS.md has claimed a "Resuming on a fresh machine" recipe since early in
this project, but it had never actually been run -- it was reasoned out, not
tested. This session finally did it: `git clone --recurse-submodules` into
a brand new `/tmp` directory (no shared build cache, no pre-existing Conan
packages beyond what's in `~/.conan2`'s global cache from other projects),
followed the documented steps, and got a clean `./tools/trimui.sh all` with
a working `d2d` binary and `trimui-pak/` -- confirming VERSIONS.md/STATUS.md
aren't just "should work" but actually do.

**One real bug found and fixed by doing this**: the documented fresh-machine
recipe said `./tools/handkit configure` (no flags), which **fails** on a
truly fresh machine with `ERROR: Package 'handkit/0.4.0' not resolved` --
Handkit's own committed `vendor/handkit/conan.lock` pins exact Conan package
revisions, but a freshly re-exported local recipe gets a new revision hash
that doesn't match the lockfile's expectation (Handkit's own `tools/handkit`
script only passes `--lockfile=` to bypass this when `conan.lock` doesn't
exist yet or `--update-lock` is passed -- since the lockfile *does* already
exist in the repo, neither condition was true). Fixed by adding
`--update-lock` to the documented command above. This is a Handkit-side
quirk, not something to patch in this repo, but worth flagging upstream to
code-beans/handkit too (their own `configure` subcommand's default behavior
arguably shouldn't require a flag most first-time users wouldn't know to add).

Also logged for completeness, not a bug: two harmless `CMake Error... Test
X - Failed` lines appeared during the build (`HAVE_WNO_INTERFERENCE_SIZE`,
`HAVE_MSSE2_SWITCH`) -- normal CMake compiler-flag feature probes that don't
apply to this toolchain/target, not actual failures. No `FAILED`/real
`error:` lines anywhere else in the full build log.

## Milestone 4: real game data verified by actually running the engine (2026-11-14)

Everything earlier about the extracted MPQs ("verified genuine... valid MoPaQ
archives") was true but weaker evidence than it sounds -- it only checked file
*format*, never that D2Decomp's engine actually accepts and plays them. This
session closed that gap using a tool already in the repo that hadn't been
tried yet: `tools/d2d_smoke.py` (launches d2d with `--headless --devctl`,
pings it over a Unix socket, asks for a screenshot, quits -- built for CI,
never run locally against this specific data before).

d2d can't run natively on this cross-compiled-for-aarch64-Linux build, so
this meant a **separate, native macOS (arm64) build** of plain upstream
d2d (`cmake -S . -B build-native-smoke -DD2D_GAME_ONLY=ON
-DD2D_BUNDLED_STORMLIB=ON -DD2D_BUNDLED_FFMPEG=ON`, Homebrew SDL3 +
openal-soft) -- nothing TrimUI/Handkit-specific, just the same engine the
cross-build uses, running where it's easy to test. `build-native-smoke/` is
gitignored (`build-*/`), never committed, and is unrelated to the actual
TrimUI artifact.

**Result: it just works.** Pointed straight at the real extracted MPQs
(`/tmp/d2-extract-test`, un-renamed, mixed-case -- macOS's case-insensitive
filesystem doesn't even need the lowercase rename the TrimUI target does):

```sh
python3 tools/d2d_smoke.py --d2d build-native-smoke/apps/d2d/d2d \
    --data /tmp/d2-extract-test --screen title --wait 10 --out /tmp/smoke-title.png
python3 tools/d2d_smoke.py --d2d build-native-smoke/apps/d2d/d2d \
    --data /tmp/d2-extract-test --screen ingame --wait 8 --out /tmp/smoke-ingame.png
```

Both exited 0. The screenshots are the real thing: a correctly rendered
Diablo II: Lord of Destruction title screen (fire, snow, the real menu) and
an in-game Rogue Encampment scene (HUD, health/mana orbs, belt, a walking
character) -- generated by the actual engine reading the actual files the
user downloaded, not a mockup. This is about as strong a confirmation as
possible without a TrimUI in hand: the asset pipeline, data loading, world
generation and rendering of the specific archive
(`Diablo II Complete (2000-01) [es-ES digital release] V1.12-1.14d`) all work.

**One honest finding, not previously known**: d2d logged
`[WARNING] patch layer doesn't look like 1.14d: data\global\excel\CubeMain.txt
has 150 rows, 1.14d's has 151 (a mod, or another version)` on load. Read
`check_patch_layer()` in `components/game/gamedata/gamedata_load.cpp`: it's a
deliberately tolerant structural heuristic ("Warns, doesn't refuse") that
compares three tables' row counts against known-1.14d values; only
`CubeMain.txt` (Horadric Cube recipes) was off, by one row --
`ItemStatCost.txt` and `UniqueItems.txt` matched exactly.

**Identified exactly which recipe is missing (2026-11-14, follow-up)**: the
user found and downloaded a community CubeMain.txt mod file (a Phrozen-Keep-
style "upgrade Set items" mod, which starts from an unmodified 1.14d
CubeMain.txt and adds 4 new rows on top). Diffing its 155 rows against this
archive's 150 by `description` column: 4 of the mod's extra rows are its
own "Upping Normal/Exceptional Set Armor/Weapon" additions (not vanilla), but
the 5th is **vanilla**: `Token of Absolution` -- the recipe that lets a
character fully respec (reset stat and skill points), added in patch 1.13.
Its exact row: 4 inputs `tes`+`ceh`+`bet`+`fed` (the four Act-boss Hell-
difficulty Essence drops: Twisted Essence of Suffering, Charged Essence of
Hatred, Burning Essence of Terror, Festering Essence of Destruction) ->
output `toa` (Token of Absolution).

Checked deeper: this archive's `misc.txt` has **no** Essence items and **no**
Token of Absolution item at all (not merely a dropped recipe row) --
confirmed identical in both of the archive's `patch_d2.mpq` candidates (base
install's 8 MB one and the LoD one actually used in `data/`, byte-identical
MD5 on `CubeMain.txt`, so this isn't an artifact of picking the wrong one).
So despite its "V1.12-1.14d" label, this specific archive's data doesn't
include patch 1.13's Essence/respec content. **Not a blocker**: the base game
is fully playable; the only effect is that one respec mechanic is
unavailable, same as pre-1.13 retail. Not something to patch in this repo --
that would mean shipping modified/third-party game data, which LEGAL.md and
this whole project's stance rule out. If full 1.14d parity ever matters, the
fix is the user's own: get an official 1.14d patch and drop it in as
`data/patch_d2.mpq` (the launcher's `D2_PATCH_INSTALLER` env var, already
documented in `tools/mpq-cat/README.md`, exists for exactly this).

**Also fixed from reading `apps/d2d/docs/design/rendering.md` while here**:
the TrimUI launcher now passes `--widescreen` to d2d. Without it the game's
view is a fixed 800x600 (4:3), pillarboxed on a wider screen. Correction
(2026-11-14): the Smart Pro and Brick don't share one resolution --
CrossMix's own hardware table (`harbourmaster/hardware.py`) has Smart Pro at
1280x720 (16:9) but **Brick at 1024x768 (a flat 4:3)**, so "the Smart
Pro/Brick's 16:9 panel" above was wrong for the Brick. Kept `--widescreen`
on unconditionally anyway, per the user: it's harmless either way --
`rendering.md` says the view's width tracks "the window's aspect
(800-1400)", so on an actual 4:3 window it computes right back to 800 wide
(a no-op), and on the Smart Pro's 16:9 it fills the screen -- no per-device
logic needed, no downside on either model. Re-validated with
`harbourmaster.captain.check_port()` after the change: still parses clean.
**Tried and stopped short**: wanted to also confirm the launcher's
`export HOME="$GAMEDIR"` (so `d2d.cfg`/saves land beside the binary, not a
real user's home) actually produces a save file, end to end. On macOS,
d2d ignores `$HOME`/`XDG_CONFIG_HOME` entirely and always uses
`~/Library/Preferences/d2d` (confirmed: `--start-screen charcreate` +
`quit` over devctl logged `ok` but wrote nothing under a test
`XDG_CONFIG_HOME`) -- that's correct, expected macOS-native behavior, not a
bug, but it means this specific check needs real Linux to mean anything.
`tools/validate-linux.Dockerfile` in this repo is exactly the right
environment for it (same `HOME`/`~/.config` logic TrimUI's Linux userspace
uses), but this machine has no `docker` installed, so this wasn't finished.
Low priority: Linux's `HOME`-based config path is standard, long-tested by
upstream's own Linux CI job, and not something this port changes --
unlike the engine+data question above, there was little reason to expect
it to behave differently here. If `docker` ever gets installed on this
machine, re-run roughly: `docker build -t d2d-test -f tools/validate-linux.Dockerfile tools/`,
then inside a container with that image, build d2d and run the
charcreate+quit cycle above with a real `$HOME` override and check for a
`.d2s` file under `$HOME/.config/d2d/save/`.

## Everything described here is already committed/pushed

`overlay/tools/trimui.sh` has all build-script fixes; `overlay/patches/`
has the FFmpeg CMakeLists.txt patch; `scripts/apply-overlay.sh` applies
both idempotently; `VERSIONS.md` reflects every dependency's actual,
now-successful build status. Nothing described here as "done" exists only
on one machine's disk.
