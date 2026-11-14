# STATUS — resume-from-here notes

Written mid-session because the agent session can die at any point and this
is the single source of truth for "what's done" vs "what's left". Read this
before re-reading chat history.

**This machine already has everything installed** to resume immediately:
Homebrew, `cmake`, `ninja`, `conan` 2.34, a cloned+configured Handkit at
`~/Documents/handkit`, and this repo at `~/Documents/diablo2-trimui` (`origin`
= `https://github.com/metalpapa/diablo2-trimui.git`). "Resuming on a fresh
machine" below has from-scratch steps if this machine/session is gone.

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

## What hasn't been attempted at all yet

- **Anything on real TrimUI hardware**: display, audio, controls,
  performance, save/load. Nobody has run this on a device. This is the one
  remaining unknown that actually matters — everything else in this file is
  "it compiles," not "it works."
- Copying the packaged build (already staged with real game data — see
  below) onto a TrimUI's SD card and launching it via PortMaster/Ports.
- A fresh-machine/fresh-clone dry run of the whole pipeline end to end.
- Submitting the FFmpeg/sysctl fix upstream to `psi29a/d2decomped` as a PR.

## Reference material found this session (not yet used, just noted)

`~/Documents/devilutionx-reference` — a shallow clone of
[diasurgical/devilutionx](https://github.com/diasurgical/devilutionx) (the
open-source Diablo I port), at the user's suggestion, as a reference for
generic-Linux/handheld SDL packaging patterns if/when needed (e.g. input
mapping, controller config). Not inspected in depth yet; no TrimUI-specific
code found in a first pass (`grep -i trimui` came up empty) — it's a
cross-platform engine port, not a TrimUI-specific one, so anything useful
from it would be by analogy, not copy-paste.

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
never committed, per LEGAL.md). The whole `trimui-pak/` folder is now ready to
copy to a TrimUI's SD card (`/mnt/SDCARD/Roms/PORTS/`) the moment there's
actual hardware to test on.

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

```sh
git clone --recurse-submodules https://github.com/metalpapa/diablo2-trimui.git
cd diablo2-trimui
brew install cmake ninja conan
conan profile detect --force
./scripts/apply-overlay.sh
export HANDKIT_SDK=$PWD/vendor/handkit
# see vendor/handkit.conan.lock and its own ./tools/handkit configure
cd upstream && ./tools/trimui.sh all
```

(Handkit's Conan packages aren't vendored as binaries — only their
*sources* are, in `vendor/sources/` — so a fresh machine's first build still
compiles Zig/SDL3 from those vendored sources, not downloads them again.)

## Everything described here is already committed/pushed

`overlay/tools/trimui.sh` has all build-script fixes; `overlay/patches/`
has the FFmpeg CMakeLists.txt patch; `scripts/apply-overlay.sh` applies
both idempotently; `VERSIONS.md` reflects every dependency's actual,
now-successful build status. Nothing described here as "done" exists only
on one machine's disk.
