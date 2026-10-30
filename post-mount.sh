#!/system/bin/sh
CW_MODDIR=${0%/*}
. "$CW_MODDIR/lib.sh"
cw_overlay_mount > "$CW_MODDIR/state/mount.log" 2>&1
