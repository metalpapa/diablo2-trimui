#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# d2d alone, for TrimUI Smart Pro / Brick (Allwinner A133P, PowerVR GE8300),
# into build/trimui/:
#   tools/trimui.sh build     cross-compiles d2d for aarch64 Linux / glibc 2.33
#   tools/trimui.sh package   wraps it as a PortMaster-style port folder
#   tools/trimui.sh all       both
#
# Experimental, unverified on real hardware (docs/trimui.md). Modeled on
# tools/d2vita.sh's "switch)" case: d2d is a generic C++23/CMake/SDL3
# program, and aarch64-linux-gnu is a boring, already-supported
# CMAKE_SYSTEM_NAME=Linux target (apps/d2d/CMakeLists.txt's FFmpeg
# cross-compile branch), unlike the Switch/Vita's exotic SDKs. The one
# device-specific problem — making SDL3 draw on the TrimUI's closed
# PowerVR driver — is solved by a separate, actively maintained project:
# Handkit (https://github.com/code-beans/handkit). This script rides on
# its pinned Zig/Clang 19 toolchain (targets glibc 2.33, matching the
# firmware) and its SDL3 build, and builds OpenAL Soft, StormLib and a
# Bink-only FFmpeg the same way d2vita.sh does for other cross targets.
#
# Requirements, once, outside this script:
#   1. git clone https://github.com/code-beans/handkit && cd handkit
#      ./tools/handkit configure   # builds the Conan packages into your cache
#   2. python3 -m pip install 'conan>=2.33' (or: brew install conan)
#   3. export HANDKIT_SDK=/path/to/handkit   (the checkout from step 1)
set -euo pipefail
cmd=${1:-all}
build=build/trimui
out=build/trimui-pak
: "${HANDKIT_SDK:?clone and run \`./tools/handkit configure\` in https://github.com/code-beans/handkit, then export HANDKIT_SDK=<that checkout>}"

trimui_configure() {
    # A throwaway Conan project that depends on handkit-sdl (SDL3 + the
    # PowerVR/Mali display backend) and handkit-toolchain (the pinned Zig
    # cross compiler). Both come from HANDKIT_SDK's local Conan cache
    # ("./tools/handkit configure" put them there) — nothing is downloaded
    # twice.
    deps=$PWD/$build/handkit-deps
    mkdir -p "$deps"
    cat > "$deps/conanfile.txt" <<'EOF'
[requires]
handkit-sdl/0.4.0
handkit-toolchain/0.14.1
[generators]
CMakeDeps
CMakeToolchain
EOF
    conan install "$deps/conanfile.txt" \
        --output-folder "$deps" \
        --profile:host "$HANDKIT_SDK/profiles/aarch64" \
        --profile:build default \
        --build missing
}

trimui_build() {
    trimui_configure
    deps=$PWD/$build/handkit-deps
    toolchain="$deps/conan_toolchain.cmake"
    sdl3_dir=$(find "$deps" -name SDL3Config.cmake -exec dirname {} \;)
    [[ -n $sdl3_dir ]] || { echo "trimui.sh: SDL3Config.cmake not found under $deps" >&2; exit 1; }

    # OpenAL Soft on SDL3's audio, exactly as tools/d2vita.sh's switch case:
    # devkitPro/handkit both leave OpenAL out, so it's built once from source
    # into $alsoft against the same toolchain and SDL3.
    alsoft=$PWD/$build/openal-deps
    if [[ ! -f $alsoft/lib/libopenal.a ]]; then
        fetch_dir=$build/openal-src
        if [[ ! -d $fetch_dir ]]; then
            mkdir -p "$build"
            curl -fsSLo "$build/openal-soft.tar.gz" \
                https://github.com/kcat/openal-soft/archive/refs/tags/1.25.2.tar.gz
            echo "fb27e5839aa11f0e5b9d33756965291fad5d6909ab928ea1f796f4a1a6877894  $build/openal-soft.tar.gz" | sha256sum -c --quiet
            mkdir -p "$fetch_dir.part" && tar -xzf "$build/openal-soft.tar.gz" -C "$fetch_dir.part" --strip-components=1
            mv "$fetch_dir.part" "$fetch_dir"
        fi
        cmake -S "$fetch_dir" -B "$build/openal-build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_TOOLCHAIN_FILE="$toolchain" -DCMAKE_INSTALL_PREFIX="$alsoft" \
            -DSDL3_DIR="$sdl3_dir" -DLIBTYPE=STATIC \
            -DALSOFT_BACKEND_SDL3=ON -DALSOFT_REQUIRE_SDL3=ON \
            -DALSOFT_UTILS=OFF -DALSOFT_EXAMPLES=OFF
        cmake --build "$build/openal-build" --target install
    fi

    cmake -S . -B "$build/d2d" -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DD2D_GAME_ONLY=ON -DD2D_BUNDLED_STORMLIB=ON -DD2D_BUNDLED_FFMPEG=ON \
        -DCMAKE_TOOLCHAIN_FILE="$toolchain" \
        -DSDL3_DIR="$sdl3_dir" \
        -DOPENAL_INCLUDE_DIR="$alsoft/include" \
        -DOPENAL_LIBRARY="$alsoft/lib/libopenal.a"
    cmake --build "$build/d2d" --target d2d
}

trimui_package() {
    [[ -f $build/d2d/apps/d2d/d2d ]] || { echo "trimui.sh: build first (tools/trimui.sh build)" >&2; exit 1; }
    # A PortMaster-shaped port folder: CrossMix OS, NextUI, muOS and knulli
    # all scan Roms/PORTS/*.sh (docs/trimui.md). No PortMaster packaging
    # metadata (port.json, gptokeyb mapping) yet — this is a manual sideload,
    # not a PortMaster store submission.
    pak="$out/Diablo II Decomp"
    rm -rf "$pak" && mkdir -p "$pak"
    cp "$build/d2d/apps/d2d/d2d" "$pak/"
    cat > "$out/Diablo II Decomp.sh" <<'EOF'
#!/bin/sh
# PortMaster launcher: see ../README-trimui.txt for first-run setup.
DIR="$(dirname "$0")/Diablo II Decomp"
cd "$DIR" || exit 1
export HOME="$DIR"
./d2d --data "$DIR/data" "$@"
EOF
    chmod +x "$out/Diablo II Decomp.sh" "$pak/d2d"
    cat > "$out/README-trimui.txt" <<'EOF'
Diablo II Decomp (d2d) for TrimUI Smart Pro / Brick — unverified build
=======================================================================
1. Copy this whole folder to /mnt/SDCARD/Roms/PORTS/ on the SD card.
2. Create "Diablo II Decomp/data/" next to d2d and copy YOUR OWN, legally
   owned Diablo II + Lord of Destruction MPQ files into it (the same
   files d2d's README calls --data: d2data.mpq, d2exp.mpq, d2sfx.mpq,
   d2music.mpq, d2video.mpq, d2xvideo.mpq, d2xmusic.mpq, d2speech.mpq,
   d2xtalk.mpq, patch_d2.mpq), from a 1.14d install. No game files are
   bundled or distributed with d2d itself (LEGAL.md).
3. From CrossMix OS's PortMaster app (or the Ports menu), launch
   "Diablo II Decomp".
4. d2d.cfg, d2d.log and save/ are written beside d2d (HOME is set there).

This is a first attempt, not a tested release: see docs/trimui.md for
what is and isn't confirmed on real hardware, and report back (screen,
audio, controls, performance) so it can be fixed.
EOF
    echo "Packaged: $out"
}

case $cmd in
    build)   trimui_build ;;
    package) trimui_package ;;
    all)     trimui_build; trimui_package ;;
    *) echo "tools/trimui.sh: build, package or all" >&2; exit 2 ;;
esac
