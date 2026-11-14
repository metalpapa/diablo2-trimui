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
│   └── docs/trimui.md      Status, risks, build/deploy instructions
├── scripts/
│   └── apply-overlay.sh   Copies overlay/ onto upstream/ (or any d2decomped checkout)
└── upstream/              git submodule: github.com/psi29a/d2decomped
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
