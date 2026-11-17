# Diablo II Decomp for TrimUI

An experimental TrimUI Smart Pro / Brick port layer for [D2Decomp](https://github.com/psi29a/d2decomped), an open-source reimplementation of the Diablo II: Lord of Destruction 1.14d engine.

This repository keeps TrimUI build and packaging changes separate from the D2Decomp source. It applies a small overlay to the `upstream/` submodule and uses [Handkit](https://github.com/code-beans/handkit) for the TrimUI SDL3 display backend and cross-toolchain.

## Current status

- The port has booted and been play-tested on a TrimUI Smart Pro running CrossMix OS.
- The project is experimental, not an official D2Decomp release. Long-session memory stability and some controller paths still need device testing.
- The latest code adds a brief red range indicator for Corpse Explosion. The ARM build succeeds, but this visual change has not yet been checked on the console.
- The `show_fps` overlay now reports battery percentage on Linux devices; this display change still needs testing on TrimUI.
- An opt-in Challenge submenu has independent Harder Monsters, More Monsters, Class-Usable Elite Loot, and Hide Gold/Potion Labels switches. They do not change official campaign difficulty.
- The latest device log has no out-of-memory kill, but ends with an unexplained segmentation fault after a save; see the engineering log for details.
- The shared DT1 cache reduced memory use in a short native macOS run; the same benefit still needs confirmation during a long TrimUI session.

See [PLAN-MEJORAS.md](PLAN-MEJORAS.md) for priorities, session notes, measurements, and open issues. Build, install, and device details are in [overlay/docs/trimui.md](overlay/docs/trimui.md).

## Features

- AArch64 Linux build for TrimUI Smart Pro and Brick using Handkit's SDL3 backend.
- PortMaster-compatible package, plus a manual-install option.
- Native SDL gamepad controls, Spanish language selection, and TrimUI-specific save and menu improvements.
- Runtime options for game speed, widescreen, and scaling mode.

## Build

Requirements: Git with submodules, CMake, Ninja, Python 3, Conan 2.33+, and a configured Handkit checkout. The recursive clone includes the pinned Handkit submodule and vendored build sources.

```sh
git clone --recurse-submodules https://github.com/metalpapa/diablo2-trimui.git
cd diablo2-trimui
./scripts/apply-overlay.sh

export HANDKIT_SDK="$PWD/vendor/handkit"
(cd "$HANDKIT_SDK" && ./tools/handkit configure)

cd upstream
tools/trimui.sh all
```

The packaged output is written to `upstream/build/trimui-pak/`. For installation steps and the expected SD-card layout, see [overlay/docs/trimui.md](overlay/docs/trimui.md).

## Repeatable TrimUI workflow

From the repository root:

```sh
make backup   # save/config/log backup to this Mac; requires CROSSMIX and sudo
make build    # compile and package; does not access the SD card
make copy     # backup, then copy binary, launcher and box art to CROSSMIX
make update   # build/package, then backup and copy to CROSSMIX
```

`make build` does not access the SD card. `make backup` reads saves/config/logs from the SD with mtools and stores a checksummed copy on this Mac. `make copy` and `make update` run that backup first; they leave MPQ data and save files on the card untouched. The SD must be connected and identifiable as `CROSSMIX`; raw mtools access may request your macOS sudo password.

Backups go to `~/Documents/diablo2-trimui-backups/` in timestamped folders with SHA-256 checksums.

## Game data

Bring your own legally owned Diablo II: Lord of Destruction 1.14d files. No game data, saves, installers, or keys are included or distributed. Place the required MPQ files in the package's `data/` directory as described in the installation guide. See [D2Decomp's legal notes](https://github.com/psi29a/d2decomped/blob/main/LEGAL.md).

## Repository layout

```text
overlay/       TrimUI build script, docs, patches, and artwork
scripts/       Applies the overlay to the D2Decomp checkout
upstream/      D2Decomp source submodule
vendor/        Pinned Handkit checkout and build sources
```

## Contributing

Bug reports and contributions are welcome. Include the TrimUI model, firmware, build revision, steps to reproduce, and relevant logs that you have reviewed for personal paths. Never share game files, keys, or saves. See [D2Decomp's contribution guide](upstream/CONTRIBUTING.md) and [repository instructions](upstream/AGENTS.md).

## Credits and license

- [D2Decomp](https://github.com/psi29a/d2decomped) and its contributors; GPL-3.0-or-later.
- [Handkit](https://github.com/code-beans/handkit); MIT license.
- This port layer is licensed under GPL-3.0-or-later; see [LICENSE](LICENSE).
