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

# Frozen dependency sources (diablo2-trimui/VERSIONS.md). This script is
# normally run from an overlay applied onto a d2decomped checkout that sits
# directly under the diablo2-trimui repo (scripts/apply-overlay.sh), so
# ../vendor/sources is where the pinned tarballs live. TRIMUI_VENDOR_DIR
# overrides this (e.g. when trimui.sh is run from somewhere else); if
# neither has the file, this script falls back to downloading it.
vendor_dir=${TRIMUI_VENDOR_DIR:-$PWD/../vendor/sources}

# OpenAL Soft is pinned to 1.24.3, not the newer 1.25.x d2decomped's own
# tools/d2vita.sh uses for the Switch build: 1.25.x compiles some of its own
# internals as real C++20 named modules (FILE_SET CXX_MODULES), which needs
# a clang-scan-deps that understands Zig's cross-compiler output and that
# neither Zig 0.14.1 nor a plain CMake setup provides out of the box here.
# 1.24.3 has no such dependency and is otherwise the same library/API.

sha256_check() {   # file sha256
    # Computes and compares by hand: BSD sha256sum (macOS's /sbin/sha256sum)
    # and GNU sha256sum take the "-c" check flag differently, and not every
    # system has both tools.
    local actual
    if command -v shasum >/dev/null 2>&1; then
        actual=$(shasum -a 256 "$1" | cut -d' ' -f1)
    else
        actual=$(sha256sum "$1" | cut -d' ' -f1)
    fi
    [[ $actual == "$2" ]] || { echo "trimui.sh: $1: expected sha256 $2, got $actual" >&2; exit 1; }
}

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
handkit-sdl/3.2.10
[tool_requires]
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
        fetch_dir=$build/openal-src-1.24.3
        if [[ ! -d $fetch_dir ]]; then
            mkdir -p "$build"
            if [[ -f $vendor_dir/openal-soft-1.24.3.tar.gz ]]; then
                cp "$vendor_dir/openal-soft-1.24.3.tar.gz" "$build/openal-soft.tar.gz"
            else
                curl -fsSLo "$build/openal-soft.tar.gz" \
                    https://github.com/kcat/openal-soft/archive/refs/tags/1.24.3.tar.gz
            fi
            sha256_check "$build/openal-soft.tar.gz" 7e1fecdeb45e7f78722b776c5cf30bd33934b961d7fd2a11e0494e064cc631ce
            mkdir -p "$fetch_dir.part" && tar -xzf "$build/openal-soft.tar.gz" -C "$fetch_dir.part" --strip-components=1
            mv "$fetch_dir.part" "$fetch_dir"
        fi
        cmake --fresh -S "$fetch_dir" -B "$build/openal-build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_TOOLCHAIN_FILE="$toolchain" -DCMAKE_INSTALL_PREFIX="$alsoft" \
            -DCMAKE_CXX_SCAN_FOR_MODULES=OFF \
            -DSDL3_DIR="$sdl3_dir" -DLIBTYPE=STATIC \
            -DALSOFT_BACKEND_SDL3=ON -DALSOFT_REQUIRE_SDL3=ON \
            -DALSOFT_UTILS=OFF -DALSOFT_EXAMPLES=OFF
cmake --build "$build/openal-build" --target install
    fi

    # zlib and bzip2: StormLib (bundled by D2D_BUNDLED_STORMLIB) and
    # components/screenshot both need them, and nothing above provides them
    # for the target. zlib ships its own CMakeLists.txt; bzip2's upstream
    # tarball doesn't, so a tiny one is written into its source tree here.
    zbz=$PWD/$build/zbz-deps
    if [[ ! -f $zbz/lib/libz.a ]]; then
        zlib_src=$build/zlib-1.3.1
        if [[ ! -d $zlib_src ]]; then
            if [[ -f $vendor_dir/zlib-1.3.1.tar.gz ]]; then
                cp "$vendor_dir/zlib-1.3.1.tar.gz" "$build/zlib.tar.gz"
            else
                curl -fsSLo "$build/zlib.tar.gz" https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz
            fi
            sha256_check "$build/zlib.tar.gz" 9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23
            mkdir -p "$zlib_src.part" && tar -xzf "$build/zlib.tar.gz" -C "$zlib_src.part" --strip-components=1
            mv "$zlib_src.part" "$zlib_src"
        fi
        cmake --fresh -S "$zlib_src" -B "$build/zlib-build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_TOOLCHAIN_FILE="$toolchain" -DCMAKE_INSTALL_PREFIX="$zbz" \
            -DBUILD_SHARED_LIBS=OFF -DZLIB_BUILD_EXAMPLES=OFF
        cmake --build "$build/zlib-build" --target zlibstatic
        cmake --install "$build/zlib-build" --component Development 2>/dev/null || true
        # zlib's install target also tries to install the shared lib target,
        # which this static-only configure never built; copy by hand instead.
        mkdir -p "$zbz/lib" "$zbz/include"
        cp "$build/zlib-build"/libz.a "$zbz/lib/" 2>/dev/null || cp "$build/zlib-build"/libzlibstatic.a "$zbz/lib/libz.a"
        cp "$zlib_src"/zlib.h "$build/zlib-build"/zconf.h "$zbz/include/"
    fi
    if [[ ! -f $zbz/lib/libbz2.a ]]; then
        bz2_src=$build/bzip2-1.0.8
        if [[ ! -d $bz2_src ]]; then
            if [[ -f $vendor_dir/bzip2-1.0.8.tar.gz ]]; then
                cp "$vendor_dir/bzip2-1.0.8.tar.gz" "$build/bzip2.tar.gz"
            else
                curl -fsSLo "$build/bzip2.tar.gz" https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz
            fi
            sha256_check "$build/bzip2.tar.gz" ab5a03176ee106d3f0fa90e381da478ddae405918153cca248e682cd0c4a2269
            mkdir -p "$bz2_src.part" && tar -xzf "$build/bzip2.tar.gz" -C "$bz2_src.part" --strip-components=1
            mv "$bz2_src.part" "$bz2_src"
            # Upstream bzip2 1.0.8 ships only a Makefile; this is the whole
            # library (7 files, per its own Makefile's $(OBJS)) as a CMake target.
            cat > "$bz2_src/CMakeLists.txt" <<'EOF'
cmake_minimum_required(VERSION 3.10)
project(bz2 C)
add_library(bz2 STATIC
    blocksort.c huffman.c crctable.c randtable.c
    compress.c decompress.c bzlib.c)
target_include_directories(bz2 PUBLIC $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>)
install(TARGETS bz2 ARCHIVE DESTINATION lib)
install(FILES bzlib.h DESTINATION include)
EOF
        fi
        cmake --fresh -S "$bz2_src" -B "$build/bzip2-build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_TOOLCHAIN_FILE="$toolchain" -DCMAKE_INSTALL_PREFIX="$zbz"
        cmake --build "$build/bzip2-build" --target install
    fi

    # FFmpeg's own ExternalProject (apps/d2d/CMakeLists.txt) downloads its
    # source itself; D2D_FFMPEG_SOURCE_DIR points it at the vendored,
    # checksum-pinned copy instead, when there is one (VERSIONS.md).
    ffmpeg_args=()
    if [[ -f $vendor_dir/ffmpeg-9.0.2.tar.xz ]]; then
        ffmpeg_src=$build/ffmpeg-9.0.2
        if [[ ! -d $ffmpeg_src ]]; then
            mkdir -p "$ffmpeg_src.part"
            tar -xJf "$vendor_dir/ffmpeg-9.0.2.tar.xz" -C "$ffmpeg_src.part" --strip-components=1
            mv "$ffmpeg_src.part" "$ffmpeg_src"
        fi
        ffmpeg_args=(-DD2D_FFMPEG_SOURCE_DIR="$ffmpeg_src")
    fi

    # CLI11 is normally FetchContent'd by git from GitHub (root CMakeLists.txt);
    # FETCHCONTENT_SOURCE_DIR_CLI11 points it at the vendored tarball instead.
    cli11_args=()
    if [[ -f $vendor_dir/cli11-2.6.2.tar.gz ]]; then
        cli11_src=$build/cli11-2.6.2
        if [[ ! -d $cli11_src ]]; then
            mkdir -p "$cli11_src.part"
            tar -xzf "$vendor_dir/cli11-2.6.2.tar.gz" -C "$cli11_src.part" --strip-components=1
            mv "$cli11_src.part" "$cli11_src"
        fi
        cli11_args=(-DFETCHCONTENT_SOURCE_DIR_CLI11="$cli11_src")
    fi

    # Conan's toolchain file sets CMAKE_CXX_STANDARD 17 as a plain (non-cache)
    # variable, from the Handkit profile's compiler.cppstd=17 (what SDL3 and
    # OpenAL need). A plain set() shadows -DCMAKE_CXX_STANDARD=23 and
    # d2decomped's own "if(NOT DEFINED CMAKE_CXX_STANDARD)" guard
    # (root CMakeLists.txt), so d2d itself would silently compile as C++17
    # and fail on <span>, unordered_set::contains, etc. This wrapper
    # includes Conan's toolchain, then raises the standard back to what
    # d2decomped actually requires.
    d2d_toolchain="$build/d2d-toolchain.cmake"
    cat > "$d2d_toolchain" <<EOF
include("$toolchain")
set(CMAKE_CXX_STANDARD 23)
EOF

    # D2D_WERROR=OFF: sanctioned escape hatch (CONTRIBUTING.md/CMakeLists.txt)
    # for a toolchain surfacing a warning upstream hasn't audited. Here it's
    # Conan's generated toolchain passing an explicit -stdlib=libc++ that
    # Zig's cross driver already defaults to and then reports unused;
    # harmless, but d2decomped's own code treats warnings as errors.
    cmake --fresh -S . -B "$build/d2d" -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DD2D_GAME_ONLY=ON -DD2D_BUNDLED_STORMLIB=ON -DD2D_BUNDLED_FFMPEG=ON \
        -DD2D_WERROR=OFF \
        -DCMAKE_TOOLCHAIN_FILE="$d2d_toolchain" \
        -DCMAKE_CXX_SCAN_FOR_MODULES=OFF \
        -DSDL3_DIR="$sdl3_dir" \
        -DOPENAL_INCLUDE_DIR="$alsoft/include" \
        -DOPENAL_LIBRARY="$alsoft/lib/libopenal.a" \
        -DZLIB_LIBRARY="$zbz/lib/libz.a" -DZLIB_INCLUDE_DIR="$zbz/include" \
        -DBZIP2_LIBRARIES="$zbz/lib/libbz2.a" -DBZIP2_LIBRARY="$zbz/lib/libbz2.a" \
        -DBZIP2_LIBRARY_RELEASE="$zbz/lib/libbz2.a" -DBZIP2_INCLUDE_DIR="$zbz/include" \
        "${ffmpeg_args[@]}" "${cli11_args[@]}"
    cmake --build "$build/d2d" --target d2d
}

# PortMaster's real on-disk format (reverse-engineered from a real CrossMix
# OS install's bundled harbourmaster -- Apps/PortMaster/PortMaster/pylibs/
# harbourmaster/{captain,info,platform,hardware}.py -- not just the public
# docs; see docs/trimui.md "PortMaster packaging" for the citations):
#   - A port zip is one or more top-level directories plus one or more
#     top-level *.sh launchers (captain.py's check_port: no .sh allowed
#     *inside* the directory, at least one directory, at least one script).
#   - A "<name>.port.json" (or literally "port.json") sitting at the top of
#     the directory is the manifest (info.py's PORT_INFO_*_ATTRS is the
#     full v3 schema). 'name' and 'items' are always overwritten by
#     harbourmaster itself from the zip's own contents, so this doesn't
#     need to enumerate files.
#   - min_glibc is checked against the device's actual glibc
#     (hardware.py: "trimui-*": "2.33" -- confirms Handkit's 2.33 pin here
#     is exactly what PortMaster itself expects on this device).
#   - Dropping the zip in PortMaster/autoinstall/ makes PortMaster install
#     it the next time it's opened (PortMaster.sh's "Autoinstallation
#     Code"), the "I didn't have to do anything else" experience other
#     ports (e.g. DevilutionX) already give on this device.
trimui_package() {
    [[ -f $build/d2d/apps/d2d/d2d ]] || { echo "trimui.sh: build first (tools/trimui.sh build)" >&2; exit 1; }
    pak="$out/Diablo II Decomp"
    rm -rf "$pak" && mkdir -p "$pak/data"
    cp "$build/d2d/apps/d2d/d2d" "$pak/"

    cat > "$pak/data/README-put-your-mpq-files-here.txt" <<'EOF'
Put your own, legally owned Diablo II + Lord of Destruction (1.14d) MPQ
files here: d2data.mpq, d2char.mpq, d2exp.mpq, d2sfx.mpq, d2music.mpq,
d2video.mpq, d2xvideo.mpq, d2xmusic.mpq, d2speech.mpq, d2xtalk.mpq,
patch_d2.mpq. Lowercase filenames (Linux is case-sensitive; the original
installer ships D2xVideo.mpq/D2xMusic.mpq with capitals). No game files
are bundled with d2d itself (LEGAL.md). See
https://github.com/metalpapa/diablo2-trimui
EOF

    cat > "$pak/diablo2decomp.port.json" <<'EOF'
{
    "version": 3,
    "name": "diablo2decomp.port.json",
    "items": null,
    "items_opt": null,
    "attr": {
        "title": "Diablo II Decomp",
        "desc": "D2Decomp's open-source reimplementation of Diablo II + Lord of Destruction (d2d), cross-compiled for the TrimUI Smart Pro/Brick via Handkit. Experimental: not yet verified on real hardware.",
        "inst": "Copy your own, legally owned Diablo II + Lord of Destruction MPQ files (a 1.14d install) into this port's data/ folder -- see data/README-put-your-mpq-files-here.txt for the exact list. No game files are bundled (LEGAL.md).",
        "genres": ["rpg", "action"],
        "porter": ["metalpapa"],
        "image": {},
        "rtr": false,
        "exp": true,
        "runtime": null,
        "min_glibc": "2.33",
        "reqs": [],
        "arch": []
    }
}
EOF

    # A placeholder icon (plain "D2" monogram, no Blizzard art -- LEGAL.md
    # rules that out) plus an ES-style gameinfo.xml so CrossMix's Ports menu
    # shows something other than the raw filename. Paths inside gameinfo.xml
    # are relative to the *shared* ports root (where both this .sh and this
    # whole directory live as siblings), not to gameinfo.xml's own location
    # -- confirmed by reading platform.py's gamelist_add(), which resolves
    # both <path> and <image> against self.hm.scripts_dir/ports_dir, never
    # the gameinfo.xml file's own directory.
    icon_src="$PWD/../overlay/assets/diablo2decomp-icon.png"
    if [[ -f $icon_src ]]; then
        cp "$icon_src" "$pak/diablo2decomp-icon.png"
        cat > "$pak/gameinfo.xml" <<EOF
<?xml version="1.0"?>
<gameList>
    <game>
        <path>./Diablo II Decomp.sh</path>
        <name>Diablo II Decomp</name>
        <desc>D2Decomp's open-source reimplementation of Diablo II + Lord of Destruction, cross-compiled for the TrimUI via Handkit. Experimental.</desc>
        <image>./Diablo II Decomp/diablo2decomp-icon.png</image>
    </game>
</gameList>
EOF
    fi

    # The launcher: PortMaster's own generic controlfolder-detection
    # (verbatim from its PortMaster.sh), so this works whether launched by
    # PortMaster itself, dropped straight into Roms/PORTS without it, or
    # moved to a different PortMaster-supported device entirely. No
    # gptokeyb/gptokeyb2: d2d reads SDL3 gamepad input natively
    # (apps/d2d/gamepad_map.hpp) instead of expecting keyboard/mouse, so
    # there's nothing for gptokeyb's button-to-key translation to do here.
    cat > "$out/Diablo II Decomp.sh" <<'EOF'
#!/bin/sh
# PortMaster port script for Diablo II Decomp (d2d).
# https://github.com/metalpapa/diablo2-trimui -- see README-trimui.txt for
# first-run setup (you supply your own, legally owned game files).

GAMEDIR="$(dirname "$0")/Diablo II Decomp"

controlfolder=""
if [ -d "/opt/system/Tools/PortMaster/" ]; then
    controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
    controlfolder="/opt/tools/PortMaster"
elif [ -d "/roms/ports/PortMaster/" ]; then
    controlfolder="/roms/ports/PortMaster"
fi

if [ -n "$controlfolder" ] && [ -f "$controlfolder/control.txt" ]; then
    # shellcheck disable=SC1091
    . "$controlfolder/control.txt"
    [ -f "$controlfolder/mod_${CFW_NAME}.txt" ] && . "$controlfolder/mod_${CFW_NAME}.txt"
    get_controls
    pm_platform_helper "$GAMEDIR/d2d"
fi

cd "$GAMEDIR" || exit 1
export HOME="$GAMEDIR"

if [ ! -d "data" ] || [ -z "$(ls -A data 2>/dev/null)" ]; then
    if command -v pm_show_error >/dev/null 2>&1; then
        pm_show_error "Diablo II Decomp" "Missing game data: see data/README-put-your-mpq-files-here.txt"
    else
        echo "Diablo II Decomp: missing game data in '$GAMEDIR/data'. See README-trimui.txt." >&2
    fi
    command -v pm_finish >/dev/null 2>&1 && pm_finish
    exit 1
fi

command -v pm_end_splash >/dev/null 2>&1 && pm_end_splash

./d2d --data "$GAMEDIR/data" "$@"

command -v pm_finish >/dev/null 2>&1 && pm_finish
EOF
    chmod +x "$out/Diablo II Decomp.sh" "$pak/d2d"

    cat > "$out/README-trimui.txt" <<'EOF'
Diablo II Decomp (d2d) for TrimUI Smart Pro / Brick — unverified build
=======================================================================
Two ways to install, pick one:

A) Through PortMaster (recommended, matches how other ports install):
   Copy "Diablo II Decomp.zip" into PortMaster/autoinstall/ on the SD card
   (e.g. /mnt/SDCARD/Apps/PortMaster/PortMaster/autoinstall/ on CrossMix
   OS) and open the PortMaster app: it auto-installs on launch, same as
   dropping any other port's zip there.

B) Manual copy (no PortMaster involved):
   Copy "Diablo II Decomp.sh" and the "Diablo II Decomp/" folder straight
   into /mnt/SDCARD/Roms/PORTS/ on the SD card. CrossMix OS, NextUI, muOS
   and knulli all scan Roms/PORTS/*.sh directly.

Either way, then:
1. Copy YOUR OWN, legally owned Diablo II + Lord of Destruction MPQ files
   into "Diablo II Decomp/data/" (see data/README-put-your-mpq-files-here.txt
   for the exact list), from a 1.14d install. Names must be lowercase
   (Linux is case-sensitive; the original installer's D2xVideo.mpq/
   D2xMusic.mpq need renaming). No game files are bundled or distributed
   with d2d itself (LEGAL.md).
2. Launch "Diablo II Decomp" from the Ports menu (or PortMaster's own
   games list, if installed via option A).
3. d2d.cfg, d2d.log and save/ are written beside d2d (HOME is set there).

This is a first attempt, not a tested release: see docs/trimui.md for
what is and isn't confirmed on real hardware, and report back (screen,
audio, controls, performance) so it can be fixed.
EOF

    # Defence in depth, on top of data/ never containing anything but the
    # placeholder .txt at this point in the script: strip any *.mpq that
    # somehow ended up there (e.g. a local test rig that already staged
    # real game data into build/trimui-pak/ for its own hardware-testing
    # use) before it could ever get zipped up. Never ship game data.
    zip_path="$out/Diablo II Decomp.zip"
    rm -f "$zip_path"
    (cd "$out" && zip -rq -X "Diablo II Decomp.zip" \
        "Diablo II Decomp.sh" "Diablo II Decomp" \
        -x "Diablo II Decomp/data/*.mpq" -x "Diablo II Decomp/data/*.MPQ")

    echo "Packaged: $out"
    echo "  - Manual copy: \"Diablo II Decomp.sh\" + \"Diablo II Decomp/\""
    echo "  - PortMaster autoinstall: \"Diablo II Decomp.zip\""
}

case $cmd in
    build)   trimui_build ;;
    package) trimui_package ;;
    all)     trimui_build; trimui_package ;;
    *) echo "tools/trimui.sh: build, package or all" >&2; exit 2 ;;
esac
