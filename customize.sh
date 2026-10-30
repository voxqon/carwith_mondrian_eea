#!/system/bin/sh

[ "${BOOTMODE:-false}" = true ] || abort "! Install from the Android root manager, not recovery."
if [ "${APATCH:-}" = true ]; then
  CW_INSTALL_MANAGER=APatch
elif [ -n "${MAGISK_VER_CODE:-}" ] && [ "${KSU:-}" != true ]; then
  [ "$MAGISK_VER_CODE" -ge 26400 ] || abort "! Magisk 26.4+ is required."
  CW_INSTALL_MANAGER=Magisk
else
  abort "! Only Magisk and APatch are supported."
fi

CW_MODDIR=$MODPATH
. "$MODPATH/lib.sh"
ui_print "- Checking mondrian EEA / Android 15 / exact framework hashes"
cw_check_rom || abort "! Unsupported target: $CW_ERROR"
ui_print "- Expanding original components"
(
  cd "$MODPATH" &&
    sha256sum -c payload.sha256 >/dev/null 2>&1
) || abort "! Compressed payload checksum failed."
unxz -c "$MODPATH/carwith-layer.img.xz" > "$MODPATH/carwith-layer.img" ||
  abort "! Cannot expand component image. The root manager must provide XZ support."
cw_hash_matches "$MODPATH/carwith-layer.img" "$CW_LAYER_SHA" ||
  abort "! Invalid original component image."
while read -r CW_HEAD CW_BLOCKS CW_TAIL CW_BYTES CW_FILE; do
  case "$CW_HEAD:$CW_BLOCKS:$CW_TAIL:$CW_BYTES" in
    *[!0-9:]*|:*|*:|*::*) abort "! Invalid component extent." ;;
  esac
  case "$CW_FILE" in
    system/product/app/CarWith/CarWith.apk|system/product/app/CarLife/CarLife.apk|system/system_ext/framework/miui.car.server.jar) ;;
    system/product/app/CarLife/lib/arm64/*)
      CW_NAME=${CW_FILE##*/}
      case "$CW_NAME" in ''|.|..|*[!a-zA-Z0-9_.+-]*) abort "! Invalid component name." ;; esac
      [ "$CW_FILE" = "system/product/app/CarLife/lib/arm64/$CW_NAME" ] ||
        abort "! Invalid component path."
      ;;
    *) abort "! Unexpected component path." ;;
  esac
  mkdir -p "$MODPATH/${CW_FILE%/*}" || abort "! Cannot create component directory."
  dd if="$MODPATH/carwith-layer.img" of="$MODPATH/$CW_FILE" \
    bs=4096 skip="$CW_HEAD" count="$CW_BLOCKS" 2>/dev/null ||
    abort "! Cannot restore component."
  if [ "$CW_BYTES" != 0 ]; then
    dd if="$MODPATH/carwith-layer.img" bs=4096 iflag=skip_bytes,count_bytes \
      skip="$CW_TAIL" count="$CW_BYTES" \
      2>/dev/null >> "$MODPATH/$CW_FILE" || abort "! Cannot restore component tail."
  fi
done < "$MODPATH/payload.map"
cw_check_payload || abort "! Invalid original payload: $CW_ERROR"
rm -f "$MODPATH/carwith-layer.img.xz" "$MODPATH/payload.map" "$MODPATH/payload.sha256" ||
  abort "! Cannot remove installation payload."

set_perm_recursive "$MODPATH" 0 0 0755 0644
for CW_SCRIPT in lib.sh control.sh boot-guard.sh post-mount.sh action.sh uninstall.sh; do
  set_perm "$MODPATH/$CW_SCRIPT" 0 0 0755
done
mkdir -p "$MODPATH/state" || abort "! Cannot create module state"
set_perm "$MODPATH/state" 0 0 0700
printf '%s\n' "$CW_INSTALL_MANAGER" > "$MODPATH/state/manager" || abort "! Cannot record root manager"
chmod 0600 "$MODPATH/state/manager"
touch "$MODPATH/skip_mount" || abort "! Cannot initialize deployment switch"
if [ "$CW_INSTALL_MANAGER" = APatch ]; then
  cw_write_state mount_mode apatch_overlay || abort "! Cannot record mount mode"
  cw_write_state deployment off || abort "! Cannot initialize deployment"
  cw_check_backend || abort "! Native overlay unavailable: $CW_ERROR"
fi

# Register one fixed, module-owned early hook; check it before allowing deployment.
CW_HOOK_DIR="$CW_ADB/post-fs-data.d"
mkdir -p "$CW_HOOK_DIR" || abort "! Cannot create common boot hook directory"
CW_HOOK="$CW_HOOK_DIR/${CW_ID}_guard.sh"
cp -f "$MODPATH/boot-guard.sh" "$CW_HOOK" || abort "! Cannot install early validation hook"
set_perm "$CW_HOOK" 0 0 0755
cw_check_hook || abort "! Early validation hook check failed"

ui_print "- CarWith APK, Xiaomi CarLife 8.8.4, 49 ARM64 native entries and service JAR included"
ui_print "- Installation starts UNDEPLOYED, including module upgrades"
ui_print "- Reboot once, then open WebUI and select Deploy; reboot to apply"
ui_print "- APatch: native read-only EROFS / OverlayFS; no MetaModule required"
ui_print "- Magisk: open with WebUI X: Portable (root / ksu.exec permission)"
