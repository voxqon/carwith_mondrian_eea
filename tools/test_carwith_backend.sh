#!/usr/bin/env bash
set -euo pipefail
module=$1
fixture=$2
[ ! -e "$fixture" ] || { echo "Use a new fixture directory" >&2; exit 1; }
. "$module/lib.sh"
CW_ADB="$fixture"
CW_MODDIR="$CW_ADB/modules/$CW_ID"
CW_SYSTEM="$fixture/os"
cw_manager() { echo "${FAKE_MANAGER:-APatch}"; }

# Exercise the deployment switch and boot protection with platform checks stubbed.
mkdir -p "$CW_MODDIR"
touch "$CW_MODDIR/module.prop" "$CW_MODDIR/skip_mount"
cw_root() { return 0; }
cw_check_rom() { return 0; }
cw_check_payload() { return 0; }
cw_check_hook() { return 0; }
if cw_deploy; then echo "Missing native mode accepted" >&2; exit 1; fi
[ "$CW_ERROR" = MOUNT_BACKEND_MISSING ]
[ -f "$CW_MODDIR/skip_mount" ]
rm "$CW_MODDIR/skip_mount"
cw_guard
[ -f "$CW_MODDIR/skip_mount" ]
[ "$(cat "$CW_MODDIR/state/guard_reason")" = MOUNT_BACKEND_MISSING ]
cw_undeploy
cw_write_state mount_mode invalid
[ "$(cw_backend)" = unconfirmed ]
if cw_deploy; then echo "Invalid native mode accepted" >&2; exit 1; fi
FAKE_MANAGER=unknown
[ "$(cw_backend)" = unconfirmed ]
if cw_check_backend; then echo "Unknown manager accepted" >&2; exit 1; fi
FAKE_MANAGER=Magisk
[ "$(cw_backend)" = magisk ]
cw_check_backend
cw_deploy
[ ! -f "$CW_MODDIR/skip_mount" ]
cw_undeploy
[ -f "$CW_MODDIR/skip_mount" ]
FAKE_MANAGER=APatch
cw_write_state mount_mode apatch_overlay
cw_write_state deployment off
cp "$module/post-mount.sh" "$CW_MODDIR/post-mount.sh"
chmod 0755 "$CW_MODDIR/post-mount.sh"
CW_FILESYSTEMS="$fixture/filesystems"
printf 'nodev\toverlay\nerofs\n' > "$CW_FILESYSTEMS"
[ "$(cw_backend)" = apatch_overlay ]
if cw_check_backend; then echo "Missing image accepted" >&2; exit 1; fi
[ "$CW_ERROR" = LAYER_CORRUPT ]
printf 'corrupt' > "$CW_MODDIR/carwith-layer.img"
if cw_check_backend; then echo "Corrupt image accepted" >&2; exit 1; fi
[ "$CW_ERROR" = LAYER_CORRUPT ]
cp "$module/carwith-layer.img" "$CW_MODDIR/carwith-layer.img"
mv "$CW_MODDIR/post-mount.sh" "$fixture/post-mount.backup"
if cw_check_backend; then echo "Missing overlay hook accepted" >&2; exit 1; fi
[ "$CW_ERROR" = OVERLAY_HOOK_MISSING ]
mv "$fixture/post-mount.backup" "$CW_MODDIR/post-mount.sh"
cw_check_backend
cw_deploy
[ "$(cw_desired)" = on ]
[ -f "$CW_MODDIR/skip_mount" ]
cw_guard
[ "$(cat "$CW_MODDIR/state/boot_choice")" = on ]
cw_undeploy
[ "$(cw_desired)" = off ]
[ -f "$CW_MODDIR/skip_mount" ]
mkdir -p "$CW_ADB/modules_update/$CW_ID/state"
printf 'apatch_overlay\n' > "$CW_ADB/modules_update/$CW_ID/state/mount_mode"
printf 'on\n' > "$CW_ADB/modules_update/$CW_ID/state/deployment"
cw_undeploy
[ "$(cat "$CW_ADB/modules_update/$CW_ID/state/deployment")" = off ]
[ -f "$CW_ADB/modules_update/$CW_ID/skip_mount" ]
rm "$CW_ADB/modules_update/$CW_ID/skip_mount" "$CW_ADB/modules_update/$CW_ID/state/"*
rmdir "$CW_ADB/modules_update/$CW_ID/state" "$CW_ADB/modules_update/$CW_ID"
CW_MOUNTINFO="$fixture/mountinfo"
printf '10 1 0:10 / /system_ext/framework ro,relatime - overlay overlay ro,lowerdir=%s/overlay_root/system_ext/framework:/system_ext/framework\n' "$CW_MODDIR" > "$CW_MOUNTINFO"
[ "$(cw_overlay_state)" = partial ]
printf '11 1 0:11 / /product/app ro,relatime - overlay overlay ro,lowerdir=%s/overlay_root/product/app:/product/app\n' "$CW_MODDIR" >> "$CW_MOUNTINFO"
[ "$(cw_overlay_state)" = active ]
printf '10 1 0:10 / /system_ext/framework ro,relatime - overlay overlay ro,lowerdir=system_ext/framework:/system_ext/framework\n' > "$CW_MOUNTINFO"
[ "$(cw_overlay_state)" = partial ]
printf '11 1 0:11 / /product/app ro,relatime - overlay overlay ro,lowerdir=product/app:/product/app\n' >> "$CW_MOUNTINFO"
[ "$(cw_overlay_state)" = active ]
printf '10 1 0:10 / /system_ext/framework ro,relatime - overlay overlay ro,lowerdir=unrelated/framework:/system_ext/framework\n' > "$CW_MOUNTINFO"
[ "$(cw_overlay_state)" = missing ]
printf '' > "$CW_MOUNTINFO"
[ "$(cw_overlay_state)" = missing ]
printf 'erofs\n' > "$CW_FILESYSTEMS"
[ "$(cw_backend)" = overlay_unsupported ]
if cw_deploy; then echo "Unsupported overlay accepted" >&2; exit 1; fi
[ "$CW_ERROR" = OVERLAY_UNSUPPORTED ]
printf 'nodev\toverlay\nerofs\n' > "$CW_FILESYSTEMS"

# Simulate the privileged mount calls, exercising production rollback decisions.
getprop() { echo "${FAKE_BOOT_COMPLETED:-0}"; }
mount() {
  printf 'mount %s\n' "${@: -1}" >> "$fixture/mount-calls"
  printf '%s\n' "$*" >> "$fixture/mount-options"
  [ "${@: -1}" != "${FAIL_TARGET:-}" ]
}
umount() {
  printf 'umount %s\n' "$*" >> "$fixture/mount-calls"
  [ "$1" != -l ] || [ "${FAIL_DETACH:-no}" != yes ]
}
cw_hash_matches() {
  case "$1" in
    /system_ext/framework/miui.car.server.jar|/product/app/CarWith/CarWith.apk|/product/app/CarLife/CarLife.apk)
      [ "${FAIL_FINAL_HASH:-no}" != yes ] && [ "${FAIL_FINAL_HASH_PATH:-}" != "$1" ] ;;
    *)
      [ -f "$1" ] && [ "$(command sha256sum "$1" | cut -d ' ' -f 1)" = "$2" ] ;;
  esac
}
cw_carlife_native_matches() {
  [ "$1" = /product/app/CarLife/lib/arm64 ]
  [ "${FAIL_FINAL_NATIVE:-no}" != yes ]
}
cw_write_state deployment on
for FAIL_TARGET in "$CW_MODDIR/overlay_root" /system_ext/framework /product/app; do
  printf '' > "$fixture/mount-calls"
  if cw_overlay_mount; then echo "Failed native mount accepted" >&2; exit 1; fi
  [ "$(cw_desired)" = off ]
  [ "$(cat "$CW_MODDIR/state/guard_reason")" = OVERLAY_MOUNT_FAILED ]
  case "$FAIL_TARGET" in
    /system_ext/framework) grep -qx "umount $CW_MODDIR/overlay_root" "$fixture/mount-calls" ;;
    /product/app) grep -qx 'umount /system_ext/framework' "$fixture/mount-calls"
      grep -qx "umount $CW_MODDIR/overlay_root" "$fixture/mount-calls" ;;
    *) ! grep -q '^umount' "$fixture/mount-calls" ;;
  esac
  cw_write_state deployment on
done
FAIL_TARGET=
printf '' > "$fixture/mount-calls"
if FAIL_DETACH=yes cw_overlay_mount; then echo "Failed layer detach accepted" >&2; exit 1; fi
grep -qx 'umount /product/app' "$fixture/mount-calls"
grep -qx 'umount /system_ext/framework' "$fixture/mount-calls"
grep -qx "umount $CW_MODDIR/overlay_root" "$fixture/mount-calls"
[ "$(cw_desired)" = off ]
cw_write_state deployment on
printf '' > "$fixture/mount-calls"
if FAIL_FINAL_HASH=yes cw_overlay_mount; then echo "Final hash failure accepted" >&2; exit 1; fi
grep -qx 'umount /product/app' "$fixture/mount-calls"
grep -qx 'umount /system_ext/framework' "$fixture/mount-calls"
! grep -qx "umount $CW_MODDIR/overlay_root" "$fixture/mount-calls"
cw_write_state deployment on
printf '' > "$fixture/mount-calls"
if FAIL_FINAL_HASH_PATH=/product/app/CarLife/CarLife.apk cw_overlay_mount; then
  echo "CarLife final hash failure accepted" >&2; exit 1
fi
[ "$(cw_desired)" = off ]
grep -qx 'umount /product/app' "$fixture/mount-calls"
grep -qx 'umount /system_ext/framework' "$fixture/mount-calls"
cw_write_state deployment on
printf '' > "$fixture/mount-calls"
if FAIL_FINAL_NATIVE=yes cw_overlay_mount; then echo "Native library failure accepted" >&2; exit 1; fi
[ "$(cw_desired)" = off ]
grep -qx 'umount /product/app' "$fixture/mount-calls"
grep -qx 'umount /system_ext/framework' "$fixture/mount-calls"
cw_write_state deployment on
mkdir -p "$CW_SYSTEM/product/app/CarLife"
if cw_overlay_mount; then echo "Existing CarLife target accepted" >&2; exit 1; fi
[ "$(cat "$CW_MODDIR/state/guard_reason")" = TARGET_ALREADY_PRESENT ]
rmdir "$CW_SYSTEM/product/app/CarLife"
cw_write_state deployment on
printf '' > "$fixture/mount-calls"
printf '' > "$fixture/mount-options"
cw_overlay_mount
grep -qx "umount -l $CW_MODDIR/overlay_root" "$fixture/mount-calls"
[ "$(grep -c '^umount' "$fixture/mount-calls")" = 1 ]
grep -qx -- '-t overlay overlay -o ro,lowerdir=system_ext/framework:/system_ext/framework /system_ext/framework' "$fixture/mount-options"
grep -qx -- '-t overlay overlay -o ro,lowerdir=product/app:/product/app /product/app' "$fixture/mount-options"
[ "$(cat "$CW_MODDIR/state/mount_result")" = OVERLAY_MOUNTED ]
if FAKE_BOOT_COMPLETED=1 cw_overlay_mount; then echo "Live remount accepted" >&2; exit 1; fi
[ "$CW_ERROR" = BOOT_STAGE_REQUIRED ]
echo "PASS Magisk/native APatch selection, invalid mode rejection, boot guard, image integrity, independent deployment, staged-update cancellation, persistent skip_mount and actual mount detection"
echo "PASS native mount failures, detached layer, APK/native hash failure rollback, CarLife target conflict, relative lowers and live-remount refusal"
