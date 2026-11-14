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
`ItemStatCost.txt` and `UniqueItems.txt` matched exactly. So this archive's
`patch_d2.mpq` (the LoD one, used per the earlier "two patch_d2.mpq exist"
note) is *very close* to 1.14d but not byte-identical -- likely missing or
having a differently-ordered one cube recipe, not a sign of corruption or a
wrong game entirely (everything else loaded and rendered correctly). Correcting
the earlier "matches this archive's own 'V1.12-1.14d' naming" claim: that's
still probably true for the base game version, but the patch layer itself
isn't a confirmed byte-exact 1.14d. Not a blocker -- worth knowing about if a
Horadric Cube recipe ever looks wrong on real hardware.

**Also fixed from reading `apps/d2d/docs/design/rendering.md` while here**:
the TrimUI launcher now passes `--widescreen` to d2d. Without it the game's
view is a fixed 800x600 (4:3), pillarboxed on the Smart Pro/Brick's 16:9
1280x720 panel; `--widescreen` is a real, already-released, opt-in d2d flag
("the world draws on the wide buffer around its centre; the HUD and panels
run unchanged") made exactly for this. Re-validated with
`harbourmaster.captain.check_port()` after the change: still parses clean.

## Everything described here is already committed/pushed

`overlay/tools/trimui.sh` has all build-script fixes; `overlay/patches/`
has the FFmpeg CMakeLists.txt patch; `scripts/apply-overlay.sh` applies
both idempotently; `VERSIONS.md` reflects every dependency's actual,
now-successful build status. Nothing described here as "done" exists only
on one machine's disk.
