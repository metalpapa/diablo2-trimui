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

cp -v "$overlay/tools/trimui.sh" "$target/tools/trimui.sh"
cp -v "$overlay/docs/trimui.md" "$target/docs/trimui.md"
chmod +x "$target/tools/trimui.sh"
echo "Overlay applied to $target. cd there and run tools/trimui.sh (see docs/trimui.md)."
