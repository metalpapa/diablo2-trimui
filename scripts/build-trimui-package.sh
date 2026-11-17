#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "$0")/.." && pwd)
export HANDKIT_SDK="${HANDKIT_SDK:-$repo_root/vendor/handkit}"

if [[ ! -x "$repo_root/upstream/tools/trimui.sh" ]]; then
    printf 'D2Decomp submodule is missing or not initialized: %s\n' "$repo_root/upstream" >&2
    exit 1
fi

printf 'Building and packaging the current TrimUI binary...\n'
(
    cd "$repo_root/upstream"
    tools/trimui.sh all
)

printf '\nBuild and package are ready. Nothing was copied to the SD card.\n'
printf 'Binary:   %s\n' "$repo_root/upstream/build/trimui-pak/Diablo II Decomp/d2d"
printf 'Launcher: %s\n' "$repo_root/upstream/build/trimui-pak/Diablo II Decomp.sh"
printf 'Package:  %s\n' "$repo_root/upstream/build/trimui-pak/Diablo II Decomp.zip"