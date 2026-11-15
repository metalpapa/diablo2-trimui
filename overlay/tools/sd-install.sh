#!/bin/sh
# Copies files onto the console's SD card from macOS with mtools (see the README,
# "Copying files to the console's SD card"). Everything goes to a log file.
#
#   overlay/tools/sd-install.sh [--binary FILE] [--launcher FILE] [--patch FILE]
#                               [--cfg key=value ...]
#
#   --binary   a d2d binary (strip it first: llvm-objcopy --strip-all)
#   --launcher "Diablo II Decomp.sh" (upstream/build/trimui-pak/ after `tools/trimui.sh package`)
#   --patch    trimui_save_patch.mpq (the Save label patch)
#   --cfg      set a d2d.cfg key (replaces the line); repeatable, e.g. --cfg show_fps=1
#
# Log: /tmp/sd-install.log
BINARY=""; LAUNCHER=""; PATCH=""; CFGS=""
while [ $# -gt 0 ]; do
    case "$1" in
        --binary)   BINARY="$2"; shift 2 ;;
        --launcher) LAUNCHER="$2"; shift 2 ;;
        --patch)    PATCH="$2"; shift 2 ;;
        --cfg)      CFGS="$CFGS $2"; shift 2 ;;
        *) echo "unknown option: $1"; exit 1 ;;
    esac
done
sudo -v
{
    DEVICE=$(diskutil info "CROSSMIX" 2>/dev/null | awk -F': *' '/Device Node/ {print $2}')
    if [ -z "$DEVICE" ]; then echo "ERROR: SD card (CROSSMIX) not found."; exit 1; fi
    RDEVICE=$(echo "$DEVICE" | sed 's#/dev/disk#/dev/rdisk#')
    GAME="::/Data/ports/diablo2decomp"
    put() {   # put LOCAL DEST: delete first so mcopy never asks "overwrite?"
        sudo mdel -i "$RDEVICE" "$2" 2>&1 || true
        sudo mcopy -i "$RDEVICE" "$1" "$2" </dev/null
    }
    if [ -n "$BINARY" ]; then
        sudo mdel -i "$RDEVICE" "$GAME/.config/d2d/d2d.log" 2>&1 || true
        put "$BINARY" "$GAME/d2d"
    fi
    [ -n "$LAUNCHER" ] && put "$LAUNCHER" "::/Roms/PORTS/Diablo II Decomp.sh"
    [ -n "$PATCH" ] && put "$PATCH" "$GAME/data/trimui_save_patch.mpq"
    if [ -n "$CFGS" ]; then
        CFG=/tmp/sd-install-d2d.cfg; rm -f "$CFG" "$CFG.new"
        sudo mcopy -n -i "$RDEVICE" "$GAME/.config/d2d/d2d.cfg" "$CFG" </dev/null
        cp "$CFG" "$CFG.new"
        for pair in $CFGS; do
            key=${pair%%=*}
            grep -v "^$key " "$CFG.new" | grep -v "^$key=" > "$CFG.tmp" || true
            mv "$CFG.tmp" "$CFG.new"
            echo "$key = ${pair#*=}" >> "$CFG.new"
        done
        put "$CFG.new" "$GAME/.config/d2d/d2d.cfg"
        cat "$CFG.new"
    fi
    sudo mdir -i "$RDEVICE" "$GAME/"
    echo "Done."
} > /tmp/sd-install.log 2>&1
echo "Finished. Result in /tmp/sd-install.log"
