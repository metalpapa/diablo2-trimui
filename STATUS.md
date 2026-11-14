# STATUS — resume-from-here notes

Written mid-session because the agent session can die at any point and this
is the single source of truth for "what's done" vs "what's left". Read this
before re-reading chat history.

**This machine (the one this was built on) already has everything installed**
to resume immediately: Homebrew, `cmake`, `ninja`, `conan` 2.34, `llvm`
(for a spare `clang-scan-deps`, no longer actually needed — see below), a
cloned+configured Handkit at `/tmp/d2port/handkit`, and a cloned
`diablo2-trimui` working copy at `/tmp/d2port/diablo2-trimui` whose `origin`
is already `https://github.com/metalpapa/diablo2-trimui.git`. If this exact
machine/session is gone, "Resuming on a fresh machine" below has the from-
scratch steps.

## What's actually proven so far (real, on this Mac, cross-compiling for aarch64)

1. Handkit's toolchain (`handkit-toolchain/0.14.1`, Zig 0.14.1 wrapping
   Clang 19, target `aarch64-linux-gnu.2.33`) builds and installs via Conan.
2. Handkit's SDL3 (`handkit-sdl/3.2.10`) cross-compiles for the TrimUI's
   display backend. Not run on a device yet, but it compiles and links.
3. OpenAL Soft **1.24.3** (not 1.25.2 — see VERSIONS.md) cross-compiles
   against that SDL3, linked as `ALSOFT_BACKEND_SDL3`.
4. zlib 1.3.1 and bzip2 1.0.8 cross-compile (bzip2 needed a hand-written
   `CMakeLists.txt` since upstream only ships a Makefile; it's generated
   inline by `trimui.sh`, not a separate vendored file).
5. StormLib (D2Decomp's own bundled copy, `D2D_BUNDLED_STORMLIB=ON`)
   cross-compiles against that zlib/bzip2.
6. **Nearly all of D2Decomp's own C++23 game code compiles** for aarch64
   (components/game, components/net, components/d2s, etc. — the bulk of the
   engine). This is the strongest evidence yet that this port is feasible,
   not just "reasoned."

## The three build bugs found and fixed (all already applied in `overlay/tools/trimui.sh`)

1. **Conan context bug**: `handkit-toolchain` must be `[tool_requires]`, not
   `[requires]`, in the generated `conanfile.txt` — otherwise Conan tries to
   build a Linux/arm64 Zig (meant to run ON an aarch64 Linux machine) instead
   of the macOS-hosted one that actually cross-compiles. Fixed.
2. **CMake C++20 module scanning**: OpenAL Soft 1.25.x uses real C++20
   named modules; Zig's wrapped Clang has no matching `clang-scan-deps`.
   Rather than fight that (tried: a host LLVM's `clang-scan-deps`, hit a
   separate SDK/header mismatch that aborts — see "Dead end" below), the fix
   was to **pin OpenAL Soft to 1.24.3**, which has no modules. Fixed, and
   simpler than the alternative.
3. **C++ standard downgrade**: Conan's generated `conan_toolchain.cmake`
   sets `CMAKE_CXX_STANDARD` to **17** as a plain (non-cache) variable, from
   the Handkit profile's `compiler.cppstd=17` (what SDL3/OpenAL need). That
   shadows both `-DCMAKE_CXX_STANDARD=23` on the command line and
   D2Decomp's own `if(NOT DEFINED CMAKE_CXX_STANDARD)` guard in its root
   `CMakeLists.txt` — so d2d's own code was silently compiling as C++17 and
   failing on `<span>`, `unordered_set::contains`, etc. Fixed with a tiny
   generated wrapper toolchain file (`build/trimui/d2d-toolchain.cmake`):
   `include()`s Conan's toolchain, then sets `CMAKE_CXX_STANDARD 23`
   afterward in the same scope. This is the fix that got components/game
   etc. compiling.
4. **`-Werror` on an unrelated warning**: Conan's toolchain passes an
   explicit `-stdlib=libc++` that Zig's cross driver already defaults to,
   which Clang reports as "argument unused" — harmless, but D2Decomp
   compiles its own code with `-Werror`. Fixed with `-DD2D_WERROR=OFF`,
   which is D2Decomp's own documented escape hatch for exactly this
   situation (see its `CMakeLists.txt`/`CONTRIBUTING.md`).

### Dead end, for the record (don't redo this)

Tried making OpenAL Soft 1.25.2 work by pointing
`CMAKE_CXX_COMPILER_CLANG_SCAN_DEPS` at a Homebrew-installed LLVM 23's
`clang-scan-deps` (`brew install llvm`). It found the right compiler flags
after fixing a quoting bug (an unquoted `${var:+...}` expansion was passing
literal quote characters into CMake's cache — if this pattern is needed again
elsewhere, build it as a bash array instead), but then the host LLVM 23
scanner's own default search paths pulled in Apple's SDK headers
(`.../MacOSX27.sdk/usr/include/c++/v1/...`) while scanning code meant for
the Linux target, and one chain of standard headers hit `'stdarg.h' file not
found`. Likely fixable with more `-nostdinc`-style isolation, but switching
OpenAL versions was far less effort for the same result.

## What's still failing right now

**FFmpeg 9.0.2's own cross-compile** (built by D2Decomp's own
`apps/d2d/CMakeLists.txt` `ExternalProject`, not by `trimui.sh` directly):

```
./src/libavutil/cpu.c:46:10: fatal error: 'sys/sysctl.h' file not found
```

`sys/sysctl.h` is a macOS/BSD header, not a Linux one. This means FFmpeg's
own `./configure` (an autoconf-style script, not CMake) detected
`HAVE_SYSCTL=1` even though the target is Linux — almost certainly because
one of its feature-detection test compiles ran against the **build host's**
default include paths rather than strictly the Zig/Linux target's, despite
`--target-os=linux --arch=aarch64 --cc=<handkit-cc>` being passed (see
`apps/d2d/CMakeLists.txt`'s `CMAKE_CROSSCOMPILING` branch, which already
handles a generic `Linux` system name — this is the path being taken).

**Not yet investigated**: whether this needs an explicit
`--extra-cflags=--sysroot=...` / `-nostdinc` pushed through
`D2D_FFMPEG_...` cache variables, whether it's a `zig cc` driver quirk when
invoked the way FFmpeg's `configure` calls `$cc -c -o ...` directly (without
CMake mediating), or whether disabling the specific sysctl-gated code path
via an extra `--disable-*` flag sidesteps it entirely (check what in
`libavutil/cpu.c` guards that include — on a quick read it's almost
certainly `HAVE_SYSCTL_BY_NAME` turned on by a feature-test that shouldn't
pass when cross-compiling).

Next concrete step: read the relevant section of
`upstream/apps/d2d/CMakeLists.txt` (the `ffmpeg_options` list and the
`CMAKE_CROSSCOMPILING` branch, roughly lines 90-150) and FFmpeg 9.0.2's own
`configure` script's sysctl detection, then either add a `--disable-*` flag
or force `HAVE_SYSCTL=no` into the FFmpeg config without hand-patching
FFmpeg's source (patching vendored source would break the checksum story in
VERSIONS.md, so prefer a configure flag).

## What hasn't been attempted at all yet

- Actually running `tools/trimui.sh package` (untested, but should work
  once `build` finishes — it only copies the binary and writes a shell
  script).
- Anything on real TrimUI hardware: display, audio, controls, performance,
  save/load. Nobody has run this on a device.
- A fresh-machine/fresh-clone dry run of the whole pipeline end to end
  (everything so far was iterated in place on one machine's build directory).

## Resume commands (same machine)

```sh
cd /tmp/d2port/diablo2-trimui
./scripts/apply-overlay.sh         # re-copy the latest overlay/tools/trimui.sh into upstream/
cd upstream
export HANDKIT_SDK=/tmp/d2port/handkit
./tools/trimui.sh build 2>&1 | tee /tmp/d2port/trimui-build-resume.log
```

The build is incremental (Ninja + cached Conan packages): OpenAL, zlib,
bzip2 and the toolchain/SDL3 steps are skipped if their install markers
already exist under `build/trimui/`, so a rerun goes straight to d2d's own
compile and should hit the FFmpeg failure above within a minute or two.

## Resuming on a fresh machine (if this one/its /tmp is gone)

The repo is self-sufficient for this — that's the point of `vendor/`:

```sh
git clone --recurse-submodules https://github.com/metalpapa/diablo2-trimui.git
cd diablo2-trimui
brew install cmake ninja conan llvm   # llvm only needed if revisiting the OpenAL 1.25.x path
conan profile detect --force
./scripts/apply-overlay.sh
export HANDKIT_SDK=$PWD/vendor/handkit
conan install vendor/handkit/... # see vendor/handkit.conan.lock and its own ./tools/handkit configure
cd upstream && ./tools/trimui.sh build
```

(The Handkit Conan packages themselves aren't vendored as binaries — only
their *sources* are, in `vendor/sources/` — so the first build on a fresh
machine still compiles Zig/SDL3 from those vendored sources rather than
downloading them again, but does redo the actual compilation. That's as
frozen as this gets without vendoring compiled binaries for a specific host
OS/arch, which would stop working the moment the host changes.)

## Everything described here is already committed/pushed

As of this file's commit, `overlay/tools/trimui.sh` has all four fixes
above applied, `VERSIONS.md` reflects the OpenAL 1.24.3 switch and the new
zlib/bzip2 pins, and `vendor/sources/` has all the tarballs this needs
(including stale-but-harmless `openal-soft-1.25.2.tar.gz` removed). Nothing
described in this file as "done" exists only on a single machine's disk.
