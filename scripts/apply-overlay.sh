#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copies this repo's overlay/ files onto a d2decomped checkout, so they
# build as if they'd been added there directly. Defaults to upstream/
# (this repo's submodule); pass another checkout path to use a different one.
set -euo pipefail
target=${1:-$(dirname "$0")/../upstream}
overlay=$(dirname "$0")/../overlay

[[ -e $target/.git && -d $target/tools ]] || {
    echo "apply-overlay.sh: $target doesn't look like a git checkout of d2decomped." >&2
    echo "Run 'git submodule update --init' first, or pass a checkout path." >&2
    exit 1
}

# Absolute now: "git -C $target" below resolves relative args (like $patch)
# against $target, not this script's original CWD.
target=$(cd "$target" && pwd)
overlay=$(cd "$overlay" && pwd)

cp -v "$overlay/tools/trimui.sh" "$target/tools/trimui.sh"
cp -v "$overlay/docs/trimui.md" "$target/docs/trimui.md"
chmod +x "$target/tools/trimui.sh"

# Small, additive patches against d2decomped's own CMakeLists.txt (never
# against vendored FFmpeg/etc. source — see STATUS.md). Applied with
# --reverse --check first so re-running this script after it already
# succeeded is a silent no-op instead of a "patch does not apply" error.
for patch in "$overlay"/patches/*.patch; do
    [[ -e $patch ]] || continue
    if git -C "$target" apply --reverse --check "$patch" 2>/dev/null; then
        echo "Already applied: $(basename "$patch")"
    else
        git -C "$target" apply "$patch"
        echo "Patched: $(basename "$patch")"
    fi
done

# Same idea for the Handkit checkout: the SDL bump (3.2.10 -> 3.2.30) lives
# in overlay/handkit-patches/ because vendor/handkit is code-beans' repo.
handkit=$(dirname "$0")/../vendor/handkit
if [[ -e $handkit/.git ]]; then
    handkit=$(cd "$handkit" && pwd)
    for patch in "$overlay"/handkit-patches/*.patch; do
        [[ -e $patch ]] || continue
        if git -C "$handkit" apply --reverse --check "$patch" 2>/dev/null; then
            echo "Already applied: $(basename "$patch")"
        else
            git -C "$handkit" apply "$patch"
            echo "Patched handkit: $(basename "$patch")"
        fi
    done
fi

echo "Overlay applied to $target. cd there and run tools/trimui.sh (see docs/trimui.md)."
