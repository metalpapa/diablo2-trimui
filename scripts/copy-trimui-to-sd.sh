#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "$0")/.." && pwd)
package="$repo_root/upstream/build/trimui-pak/Diablo II Decomp"
launcher="$repo_root/upstream/build/trimui-pak/Diablo II Decomp.sh"
installer="$repo_root/overlay/tools/sd-install.sh"
box_art="$repo_root/overlay/assets/diablo2decomp-boxart.png"

for path in "$package/d2d" "$launcher" "$installer" "$box_art"; do
    [[ -f "$path" ]] || { printf 'Required file not found: %s\nRun make build first.\n' "$path" >&2; exit 1; }
done

bash "$repo_root/scripts/backup-trimui.sh"
bash "$installer" --binary "$package/d2d" --launcher "$launcher" --cfg show_fps=1

device=$(diskutil info "CROSSMIX" 2>/dev/null | awk -F': *' '/Device Node/ {print $2}' || true)
[[ -n "$device" ]] || { printf 'ERROR: SD card (CROSSMIX) not found.\n' >&2; exit 1; }
rdevice=$(printf '%s\n' "$device" | sed 's#/dev/disk#/dev/rdisk#')
sudo -v

ensure_dir() {
    local path="$1"
    if ! sudo mdir -i "$rdevice" "$path" >/dev/null 2>&1; then
        sudo mmd -i "$rdevice" "$path"
    fi
}

ensure_dir "::/Imgs"
ensure_dir "::/Imgs/PORTS"
sudo mdel -i "$rdevice" "::/Imgs/PORTS/Diablo II Decomp.png" 2>&1 || true
sudo mcopy -i "$rdevice" "$box_art" "::/Imgs/PORTS/Diablo II Decomp.png" </dev/null
printf 'Binary, launcher, and box art copied. Existing MPQs and saves were left untouched.\n'