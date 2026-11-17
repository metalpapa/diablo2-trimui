#!/usr/bin/env bash
set -euo pipefail

volume=/Volumes/CROSSMIX
user_dir="$volume/Data/ports/diablo2decomp/.config/d2d"
backup_root="$HOME/Documents/diablo2-trimui-backups"

if [[ ! -d "$user_dir/save" ]]; then
    printf 'TrimUI save directory not found at %s. Mount the CROSSMIX volume first.\n' "$user_dir" >&2
    exit 1
fi

mkdir -p "$backup_root"
backup=$(mktemp -d "$backup_root/$(date +%Y%m%d-%H%M%S)-before-session.XXXXXX")
ditto "$user_dir/save" "$backup/save"
for file in d2d.cfg d2d.log launcher.log; do
    if [[ -f "$user_dir/$file" ]]; then ditto "$user_dir/$file" "$backup/$file"; fi
done

{
    printf 'Created: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf 'Device volume: CROSSMIX\n'
    printf 'Repository branch: %s\n' "$(git -C "$(dirname -- "$0")/.." branch --show-current)"
    printf 'Engine branch: %s\n' "$(git -C "$(dirname -- "$0")/../upstream" branch --show-current)"
} > "$backup/manifest.txt"

find "$backup" -type f ! -name SHA256SUMS.txt -print0 | xargs -0 shasum -a 256 > "$backup/SHA256SUMS.txt"
printf 'Backup complete: %s\n' "$backup"
printf 'Contents: save/, d2d.cfg, d2d.log, launcher.log, manifest, SHA256SUMS.txt (when present)\n'