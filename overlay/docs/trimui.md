# d2d for the TrimUI Smart Pro / Brick

Status: **experimental, unverified on real hardware.** Written as a starting
point for a port, not a support claim (docs/design/platform-support.md's
rules apply here too: a successful cross-compile is not "supported").

d2d built for the TrimUI's AArch64 (Allwinner A133P, PowerVR GE8300) through
[Handkit](https://github.com/code-beans/handkit)'s pinned Zig/Clang 19
toolchain (glibc 2.33) and its SDL3 build, which already solves the one
TrimUI-specific problem: drawing through the device's closed PowerVR driver.
Everything else — OpenAL Soft, StormLib, the Bink-only FFmpeg — follows the
same recipe `tools/d2vita.sh` already uses for the Vita and Switch builds,
because `aarch64-linux-gnu` is a plain `CMAKE_SYSTEM_NAME=Linux` target that
apps/d2d/CMakeLists.txt's cross-compile branch already handles.

| Build | Files | Made by |
|---|---|---|
| TrimUI | `d2d` + a `Roms/PORTS/Diablo II Decomp[.sh]` folder | `tools/trimui.sh` (Handkit) |

Not in CI yet: no runner has TrimUI hardware or firmware to test against, so
this doesn't build automatically and isn't released. Run it locally.

## Why Handkit and not a plain cross-compiler

A generic `aarch64-linux-gnu-gcc` from your distro links against whatever
glibc *it* ships, almost always newer than the TrimUI firmware's. The result
would fail at launch with an unresolved `GLIBC_2.NN` symbol — a classic
embedded-Linux mismatch, not a d2d bug. Handkit's toolchain is pinned to
glibc 2.33, checked against the firmware it targets, and its SDL3 already has
a working display backend for the TrimUI's GPU, which a vanilla SDL3 Linux
build (X11/Wayland/KMS-DRM) does not. Its [platform table](
https://github.com/code-beans/handkit/blob/main/docs/platforms.md) lists the
TrimUI Smart Pro and Brick (NextUI, stock, CrossMix, spruce) as "expected":
same system and drivers as the Brick Pro, which Handkit has run its demo on,
but not yet tested as this specific game.

## Build

Once, outside this repo:

```sh
git clone https://github.com/code-beans/handkit
cd handkit && ./tools/handkit configure   # needs Conan 2.33+, CMake, Ninja
```

Then, in this repo:

```sh
export HANDKIT_SDK=/path/to/handkit
tools/trimui.sh all      # build + package, into build/trimui-pak/
```

## Where its files go

`tools/trimui.sh package` writes `build/trimui-pak/` with two install paths,
pick one:

- **Through PortMaster** (recommended — matches how every other port
  installs, including on this device): drop `Diablo II Decomp.zip` into
  `PortMaster/autoinstall/` on the SD card and open the PortMaster app; it
  auto-installs on launch (verified against this section's citations below).
- **Manual copy** (no PortMaster involved): copy `Diablo II Decomp.sh` and
  `Diablo II Decomp/` straight into `/mnt/SDCARD/Roms/PORTS/`. CrossMix OS,
  NextUI, muOS and knulli all scan `Roms/PORTS/*.sh` directly.

Put your own, legally owned Diablo II + Lord of Destruction MPQs (a 1.14d
install, lowercase filenames) into `Diablo II Decomp/data/` either way. d2d
reads them from there (`--data`, in the launcher script); none are bundled
(LEGAL.md). `d2d.cfg`, `d2d.log` and `save/` are written beside the binary
(`HOME` points there).

## PortMaster packaging: how this was actually verified (2026-11-14)

There's no public, authoritative spec doc for PortMaster's on-disk zip/
`port.json` format beyond its own source, so this was reverse-engineered
from a **real CrossMix OS install** (`CrossMix-OS_v1.3.0.zip`,
`Apps/PortMaster/PortMaster/`), specifically the bundled `harbourmaster`
Python package (`pylibs/harbourmaster/{captain,info,platform,hardware}.py`)
that PortMaster's own GUI (`pugwash`/`pugscene.py`) calls into. This isn't
guesswork dressed up as research — the actual zip this repo produces was
**run through that real code** (`harbourmaster.captain.check_port()` and
`harbourmaster.util.match_requirements()`, both imported directly from the
CrossMix install's `pylibs/`) and it parses cleanly and would be shown to a
TrimUI Smart Pro user. See `tools/trimui.sh`'s `trimui_package()` for the
inline citations (file/line references) behind each design choice below.

Key findings:

- A port zip is one or more top-level directories (here: `Diablo II Decomp/`)
  plus one or more top-level `*.sh` launchers (here: `Diablo II Decomp.sh`).
  `.sh` files *inside* the directory aren't allowed.
- A `<name>.port.json` at the top of the directory is the manifest (schema:
  `harbourmaster/info.py`'s `PORT_INFO_*_ATTRS`, version 3). `name` and
  `items` are always recomputed from the zip's own contents at install time,
  so the file doesn't need to enumerate itself.
- `min_glibc` is checked against the device's real glibc. `harbourmaster`'s
  own static table has `"trimui-*": "2.33"` — independent confirmation that
  Handkit's glibc 2.33 pin (VERSIONS.md) is exactly right for this device.
- No `gptokeyb`/`gptokeyb2` needed: that translates gamepad input into
  keyboard/mouse events for ports of PC games that only understand a
  keyboard. d2d already reads SDL3 gamepad input natively
  (`apps/d2d/gamepad_map.hpp`), the same as its Vita/Switch builds, so
  there's nothing for a translation layer to do.
- Dropping a zip into `PortMaster/autoinstall/` (e.g.
  `/mnt/SDCARD/Apps/PortMaster/PortMaster/autoinstall/` on CrossMix OS) and
  opening PortMaster installs it automatically on launch
  (`PortMaster.sh`'s own "Autoinstallation Code") — this is the "I didn't
  have to do anything else, it just showed up in the ports catalog"
  experience other ports (DevilutionX, etc.) already give on this device.
- `attr.title`/`attr.desc`/`attr.inst` from `port.json`, plus a plain
  placeholder icon (`assets/diablo2decomp-icon.png` — a generic "D2"
  monogram, no Blizzard art per LEGAL.md) and a `gameinfo.xml`, give the
  Ports menu a real title/icon instead of a bare filename.

## Not there yet (first things to find out on real hardware)

- It hasn't run on a TrimUI. Expect at least one round of fixes: shared-
  library paths, the exact PowerVR/Mali EGL alias Handkit's SDL3 picks,
  default resolution/scale on the device's panel, stick/button mapping
  through `apps/d2d/gamepad_map.hpp`.
- Performance is untested. d2d's CPU-rendered framebuffer should be light
  for a Cortex-A53 quad-core (the reference game is from 2000), but only a
  run on the device confirms it.
- Network (LAN/TCP·IP join) is expected to work — this is real Linux, not
  a sandboxed console SDK like the Vita/Switch builds — but is untested here.
- No real icon/art (a plain placeholder is included — see above — but
  nothing using actual D2 assets, which LEGAL.md rules out anyway).
- Audio backend is SDL3's through Handkit's build; OpenAL Soft's SDL3
  backend on it is untested beyond compiling.

Report results (what ran, what didn't, `d2d.log`) the same way as any other
bug: https://github.com/psi29a/d2decomped/issues, noting the TrimUI model,
firmware and this doc.
