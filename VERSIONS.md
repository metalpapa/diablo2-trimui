# Frozen dependency versions

Every third-party piece this port depends on, pinned to an exact version and
checksum. "Frozen" means: if any upstream link below disappears or changes,
this repo still has what's needed to reproduce the same build — the sources
are mirrored under `vendor/sources/`, and the two moving-target projects
(D2Decomp itself, Handkit) are pinned git submodules, not floating branches.

| Dependency | Version | Pinned as | Verified |
|---|---|---|---|
| D2Decomp (game engine) | commit `beb487b` (2026-11-14) | git submodule `upstream/` | **builds a full aarch64 `d2d` binary** |
| Handkit (toolchain + SDL3 backend) | commit `05e661f` | git submodule `vendor/handkit/` | toolchain+SDL3 built OK |
| Zig (cross C/C++ compiler) | 0.14.1 | `vendor/sources/zig-*-0.14.1.tar.xz` | used successfully |
| SDL3 (Handkit's `handkit-sdl` recipe) | **3.2.30** (experimental branch; main is 3.2.10) | `vendor/sources/SDL3-3.2.30.tar.gz` (sha256 `4c3b0933...42e3d`, matches GitHub's release digest) | built OK with Handkit's backend, d2d links; not run on device |
| OpenAL Soft | **1.24.3**, not 1.25.x | `vendor/sources/openal-soft-1.24.3.tar.gz` | built OK |
| zlib | 1.3.1 | `vendor/sources/zlib-1.3.1.tar.gz` | built OK |
| bzip2 | 1.0.8 | `vendor/sources/bzip2-1.0.8.tar.gz` | built OK (custom CMakeLists, see trimui.sh) |
| FFmpeg (Bink-only, built by D2Decomp's own CMake) | 9.0.2 | `vendor/sources/ffmpeg-9.0.2.tar.xz` | built OK (`overlay/patches/`, see STATUS.md) |
| CLI11 (header-only, FetchContent in D2Decomp's CMake) | 2.6.2 | `vendor/sources/cli11-2.6.2.tar.gz` | built OK |
| StormLib | bundled by D2Decomp (`-DD2D_BUNDLED_STORMLIB=ON`) | inside `upstream/` submodule | built OK |

**Why OpenAL Soft 1.24.3, not 1.25.2** (the version D2Decomp's own
`tools/d2vita.sh` pins for its Switch build): 1.25.x compiles some of its own
internals as real C++20 named modules (`FILE_SET CXX_MODULES`), which needs a
`clang-scan-deps` that understands Zig's cross-compiler output. That rabbit
hole (host LLVM's scanner mismatches Zig's bundled Clang's target flags,
aborts) wasn't worth it when 1.24.3 is otherwise the same library with no
such dependency. See STATUS.md for the full blow-by-blow.

See **STATUS.md** for what's built, what's still failing, and exact commands
to resume a session.

## Checksums

```
$ shasum -a 256 vendor/sources/*
```

## Why vendor instead of just pinning version numbers

A version number or a git tag is not frozen if the server hosting it can
change what that name points to, go offline, or simply be reorganized
(ziglang.org, GitHub release assets, ffmpeg.org mirrors have all moved
things before). Keeping the actual bytes in `vendor/sources/`, checksum
already verified at the time they were added, means this repo can rebuild
the exact same dependency graph later even if every link above breaks.

## Updating a pinned version

1. Download the new version, verify its checksum against the upstream
   project's own published hash (not just "it downloaded fine").
2. Replace the file under `vendor/sources/`, update this table, STATUS.md,
   and the checksum/version references in `overlay/tools/trimui.sh`.
3. Update the submodule pin (`git -C upstream pull && git add upstream`, or
   the same for `vendor/handkit`) only deliberately, with a commit message
   saying what changed and why — not as a side effect of an unrelated commit.
4. Rebuild and note in `overlay/docs/trimui.md` whether the new versions are
   still only "reasoned" or have actually been run on hardware.
