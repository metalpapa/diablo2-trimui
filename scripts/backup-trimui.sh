#!/usr/bin/env bash
set -euo pipefail

volume=CROSSMIX
sd_user='::/Data/ports/diablo2decomp/.config/d2d'
backup_root="$HOME/Documents/diablo2-trimui-backups"

device=$(diskutil info "$volume" 2>/dev/null | awk -F': *' '/Device Node/ {print $2}' || true)
if [[ -z "$device" ]]; then
    printf 'TrimUI SD card (CROSSMIX) not found. Connect it first.\n' >&2
    exit 1
fi
raw_device=$(printf '%s\n' "$device" | sed 's#/dev/disk#/dev/rdisk#')

mkdir -p "$backup_root"
backup=$(mktemp -d "$backup_root/$(date +%Y%m%d-%H%M%S)-before-session.XXXXXX")
mkdir -p "$backup/save"
sudo -v
sudo mdir -i "$raw_device" "$sd_user/save" >/dev/null
sudo mcopy -s -i "$raw_device" "$sd_user/save/*" "$backup/save/" </dev/null

for file in d2d.cfg d2d.log launcher.log; do
    if sudo mdir -i "$raw_device" "$sd_user/$file" >/dev/null 2>&1; then
        sudo mcopy -i "$raw_device" "$sd_user/$file" "$backup/$file" </dev/null
    fi
done

{
    printf 'Created: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf 'Device volume: CROSSMIX\n'
    printf 'Repository branch: %s\n' "$(git -C "$(dirname -- "$0")/.." branch --show-current)"
    printf 'Engine branch: %s\n' "$(git -C "$(dirname -- "$0")/../upstream" branch --show-current)"
} > "$backup/manifest.txt"

find "$backup" -type f ! -name SHA256SUMS.txt -print0 | xargs -0 shasum -a 256 > "$backup/SHA256SUMS.txt"
printf 'Backup complete: %s\n' "$backup"
printf 'Contents copied to this Mac: save/, d2d.cfg, d2d.log, launcher.log, manifest, SHA256SUMS.txt (when present)\n'