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

Copy `build/trimui-pak/`'s contents to `/mnt/SDCARD/Roms/PORTS/` on the SD
card: the `Diablo II Decomp.sh` launcher and the `Diablo II Decomp/` folder
beside it. CrossMix OS, NextUI, muOS and knulli all list `Roms/PORTS/*.sh` in
their PortMaster-style ports menu. This is a manual sideload, not a
PortMaster store submission — no `port.json` or controller-mapping metadata
yet.

Put your own, legally owned Diablo II + Lord of Destruction MPQs (a 1.14d
install) into `Diablo II Decomp/data/`. d2d reads them from there
(`--data`, in the launcher script); none are bundled (LEGAL.md). `d2d.cfg`,
`d2d.log` and `save/` are written beside the binary (`HOME` points there).

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
- No PortMaster packaging metadata, no icon/art for the ports menu.
- Audio backend is SDL3's through Handkit's build; OpenAL Soft's SDL3
  backend on it is untested beyond compiling.

Report results (what ran, what didn't, `d2d.log`) the same way as any other
bug: https://github.com/psi29a/d2decomped/issues, noting the TrimUI model,
firmware and this doc.
