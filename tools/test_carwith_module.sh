#!/usr/bin/env bash
# Host-side fixtures only: no Android device, /data/adb, or system mount is modified.
set -euo pipefail
module=$1
fixture=$2
[ ! -e "$fixture" ] || { echo "Use a new fixture directory" >&2; exit 1; }
. "$module/lib.sh"
CW_ADB="$fixture/adb"
CW_SYSTEM="$fixture/os"
CW_MODDIR="$CW_ADB/modules/$CW_ID"
mkdir -p "$CW_MODDIR" "$CW_ADB/post-fs-data.d"
cp -R "$module/system" "$CW_MODDIR/"
cp "$module"/*.sh "$module/module.prop" "$module/carlife-native.sha256" \
  "$module/skip_mount" "$module/carwith-layer.img" "$CW_MODDIR/"
cp "$module/boot-guard.sh" "$CW_ADB/post-fs-data.d/${CW_ID}_guard.sh"
chmod 755 "$CW_ADB/post-fs-data.d/${CW_ID}_guard.sh"

# Only platform property/Binder/package services are mocked; payload hashes use
# sha256sum and real original APK/JAR/native bytes. Core files are separate fixtures.
id() { printf '%s\n' "${FAKE_UID:-0}"; }
getprop() {
  case "$1" in
    ro.product.vendor.device) echo "${FAKE_DEVICE:-mondrian}" ;;
    ro.product.mod_device) echo "${FAKE_REGION:-mondrian_eea_global}" ;;
    ro.build.version.sdk) echo "${FAKE_SDK:-35}" ;;
    ro.product.cpu.abi) echo "${FAKE_ABI:-arm64-v8a}" ;;
    ro.build.version.incremental) echo "${FAKE_ROM:-OS3.0.2.0.VMNEUXM}" ;;
    sys.boot_completed) echo 1 ;;
  esac
}
cw_boot_id() { echo "${FAKE_BOOT:-boot-1}"; }
service() { echo "Service MiuiCarService: ${FAKE_BINDER:-not found}"; }
pm() {
  case "${@: -1}" in
    com.miui.carlink)
      [ "${FAKE_PACKAGE:-missing}" != installed ] || echo "package:$CW_SYSTEM/product/app/CarWith/CarWith.apk" ;;
    com.baidu.carlife.xiaomi)
      [ "${FAKE_CARLIFE_PACKAGE:-missing}" != installed ] || echo "package:$CW_SYSTEM/product/app/CarLife/CarLife.apk" ;;
  esac
  return 0
}
dumpsys() {
  if [ "$2" = com.baidu.carlife.xiaomi ]; then
    printf '    pkgFlags=[ %s HAS_CODE ALLOW_CLEAR_USER_DATA ]\n' "${FAKE_CARLIFE_FLAG:-SYSTEM}"
    printf '    versionCode=%s minSdk=23 targetSdk=30\n    versionName=8.8.4\n' "${FAKE_CARLIFE_CODE:-273}"
  else
    printf '    pkgFlags=[ SYSTEM HAS_CODE ALLOW_CLEAR_USER_DATA ]\n'
  fi
}
getenforce() { echo Enforcing; }

mkdir -p "$CW_SYSTEM/system/framework" "$CW_SYSTEM/system_ext/framework"
for path in \
  system/framework/framework.jar system/framework/services.jar \
  system_ext/framework/miui-framework.jar system_ext/framework/miui-services.jar; do
  printf 'core-fixture:%s\n' "$path" > "$CW_SYSTEM/$path"
done
# The production checker is exercised against real extracted target hashes
# by overriding file resolution at this boundary, never the validation function.
sha256sum() {
  local original=
  case "$1" in
    "$CW_SYSTEM/system/framework/"*) original="$REAL_CORE/system/system_a/${1#"$CW_SYSTEM/"}" ;;
    "$CW_SYSTEM/system_ext/framework/"*)
      case "${1##*/}" in miui-framework.jar|miui-services.jar)
        original="$REAL_CORE/system_ext/system_ext_a/framework/${1##*/}" ;;
      esac ;;
  esac
  if [ -n "$original" ] && [ "${CORRUPT_CORE:-}" != "${1##*/}" ]; then
    command sha256sum "$original"
  else
    command sha256sum "$@"
  fi
}

passed=0
ok() { passed=$((passed + 1)); echo "PASS $1"; }
expect_error() {
  local expected=$1
  shift
  if "$@"; then echo "Unexpected success: $expected" >&2; exit 1; fi
  [ "$CW_ERROR" = "$expected" ] || { echo "Expected $expected, got $CW_ERROR" >&2; exit 1; }
  ok "$expected"
}
assert_status() {
  cw_status > "$fixture/status.json"
  # Use a real JSON parser to validate the shell emitter.
  STATUS_FILE="$fixture/status.json" "$PYTHON_EXE" -c \
    'import json,os,sys; s=json.load(open(os.environ["STATUS_FILE"])); assert s[sys.argv[1]]==sys.argv[2],s' "$1" "$2"
}

cw_check_rom
cw_check_payload
cw_check_hook
ok "target and original payload hashes"
cw_guard
assert_status reboot_required no
assert_status desired off
ok "initial boot remains undeployed"
cw_deploy
assert_status desired on
assert_status reboot_required yes
ok "deploy schedules both APKs, CarLife native libraries and JAR together"
cw_undeploy
assert_status reboot_required no
ok "undo before reboot restores prior choice"
cw_deploy
FAKE_BOOT=boot-2
cw_guard
mkdir -p "$CW_SYSTEM/product/app/CarWith"
cp "$CW_MODDIR/system/product/app/CarWith/CarWith.apk" "$CW_SYSTEM/product/app/CarWith/"
cp -R "$CW_MODDIR/system/product/app/CarLife" "$CW_SYSTEM/product/app/"
cp "$CW_MODDIR/system/system_ext/framework/miui.car.server.jar" "$CW_SYSTEM/system_ext/framework/"
FAKE_BINDER=found FAKE_PACKAGE=installed
FAKE_CARLIFE_PACKAGE=installed
assert_status apk match
assert_status jar match
assert_status system_app yes
assert_status binder found
assert_status carlife_apk match
assert_status carlife_native match
assert_status carlife_package installed
assert_status carlife_system_app yes
assert_status carlife_version 8.8.4
assert_status carlife_version_code 273
assert_status carlife_compatible yes
FAKE_CARLIFE_CODE=219 assert_status carlife_compatible no
FAKE_CARLIFE_CODE=unknown assert_status carlife_compatible unknown
FAKE_CARLIFE_FLAG=HAS_CODE assert_status carlife_system_app no
FAKE_CARLIFE_PACKAGE=missing assert_status carlife_package missing
assert_status carlife_package installed
assert_status reboot_required no
cp "$fixture/status.json" "$fixture/running-status.json"
ok "deployed boot: both APKs, native libraries, version compatibility, system apps and service checked"
cw_undeploy
assert_status reboot_required yes
assert_status binder found
ok "undeploy preserves live service until reboot"
FAKE_BOOT=boot-3
cw_guard
rm "$CW_SYSTEM/product/app/CarWith/CarWith.apk" "$CW_SYSTEM/system_ext/framework/miui.car.server.jar"
rm "$CW_SYSTEM/product/app/CarLife/CarLife.apk" "$CW_SYSTEM/product/app/CarLife/lib/arm64/"*.so
rmdir "$CW_SYSTEM/product/app/CarLife/lib/arm64" "$CW_SYSTEM/product/app/CarLife/lib" "$CW_SYSTEM/product/app/CarLife"
FAKE_BINDER="not found" FAKE_PACKAGE=missing
FAKE_CARLIFE_PACKAGE=missing
assert_status reboot_required no
assert_status apk missing
assert_status binder missing
assert_status carlife_apk missing
assert_status carlife_native missing
assert_status carlife_package missing
ok "undeployed next boot"

FAKE_DEVICE=other expect_error DEVICE_MISMATCH cw_deploy
FAKE_REGION=mondrian_global expect_error REGION_MISMATCH cw_deploy
FAKE_SDK=36 expect_error SDK_MISMATCH cw_deploy
FAKE_ABI=x86_64 expect_error ABI_MISMATCH cw_deploy
FAKE_ROM=OS3.0.3.0.VMNEUXM expect_error ROM_MISMATCH cw_deploy
CORRUPT_CORE=framework.jar expect_error FRAMEWORK_MISMATCH cw_deploy
CORRUPT_CORE=services.jar expect_error SERVICES_MISMATCH cw_deploy
CORRUPT_CORE=miui-framework.jar expect_error MIUI_FRAMEWORK_MISMATCH cw_deploy
CORRUPT_CORE=miui-services.jar expect_error MIUI_SERVICES_MISMATCH cw_deploy
FAKE_UID=2000 expect_error ROOT_REQUIRED cw_deploy
touch "$CW_MODDIR/disable"
expect_error MODULE_DISABLED cw_deploy
rm "$CW_MODDIR/disable"
touch "$CW_MODDIR/remove"
expect_error MODULE_REMOVING cw_deploy
rm "$CW_MODDIR/remove"
mkdir -p "$CW_ADB/modules_update/$CW_ID"
expect_error UPDATE_PENDING cw_deploy
cw_undeploy
[ -f "$CW_ADB/modules_update/$CW_ID/skip_mount" ]
ok "undeploy also cancels staged update"
rm "$CW_ADB/modules_update/$CW_ID/skip_mount"
rmdir "$CW_ADB/modules_update/$CW_ID"
mv "$CW_ADB/post-fs-data.d/${CW_ID}_guard.sh" "$fixture/guard"
expect_error GUARD_MISSING cw_deploy
mv "$fixture/guard" "$CW_ADB/post-fs-data.d/${CW_ID}_guard.sh"

cp "$CW_MODDIR/system/product/app/CarWith/CarWith.apk" "$fixture/apk.backup"
printf 'corrupt' >> "$CW_MODDIR/system/product/app/CarWith/CarWith.apk"
expect_error APK_CORRUPT cw_deploy
cp "$fixture/apk.backup" "$CW_MODDIR/system/product/app/CarWith/CarWith.apk"
cp "$CW_MODDIR/system/system_ext/framework/miui.car.server.jar" "$fixture/jar.backup"
printf 'corrupt' >> "$CW_MODDIR/system/system_ext/framework/miui.car.server.jar"
expect_error JAR_CORRUPT cw_deploy
cp "$fixture/jar.backup" "$CW_MODDIR/system/system_ext/framework/miui.car.server.jar"
mv "$CW_MODDIR/system/product/app/CarLife/CarLife.apk" "$fixture/carlife.backup"
expect_error CARLIFE_CORRUPT cw_deploy
cp "$fixture/carlife.backup" "$CW_MODDIR/system/product/app/CarLife/CarLife.apk"
printf 'corrupt' >> "$CW_MODDIR/system/product/app/CarLife/CarLife.apk"
expect_error CARLIFE_CORRUPT cw_deploy
cp "$fixture/carlife.backup" "$CW_MODDIR/system/product/app/CarLife/CarLife.apk"
cp "$CW_MODDIR/system/product/app/CarLife/lib/arm64/libc++_shared.so" "$fixture/native.backup"
printf 'corrupt' >> "$CW_MODDIR/system/product/app/CarLife/lib/arm64/libc++_shared.so"
expect_error CARLIFE_LIBS_CORRUPT cw_deploy
cp "$fixture/native.backup" "$CW_MODDIR/system/product/app/CarLife/lib/arm64/libc++_shared.so"
mv "$CW_MODDIR/system/product/app/CarLife/lib/arm64/libc++_shared.so" "$fixture/native.missing"
expect_error CARLIFE_LIBS_CORRUPT cw_deploy
mv "$fixture/native.missing" "$CW_MODDIR/system/product/app/CarLife/lib/arm64/libc++_shared.so"
cp "$CW_MODDIR/carlife-native.sha256" "$fixture/native-manifest.backup"
printf 'corrupt' >> "$CW_MODDIR/carlife-native.sha256"
expect_error CARLIFE_LIBS_CORRUPT cw_deploy
cp "$fixture/native-manifest.backup" "$CW_MODDIR/carlife-native.sha256"

# Simulate APatch installer's separate partition moves and relative links.
mv "$CW_MODDIR/system/product" "$CW_MODDIR/product"
mv "$CW_MODDIR/system/system_ext" "$CW_MODDIR/system_ext"
ln -s ../product "$CW_MODDIR/system/product"
ln -s ../system_ext "$CW_MODDIR/system/system_ext"
cw_check_payload
cw_deploy
ok "APatch separate-partition layout"
FAKE_BOOT=boot-4 FAKE_ROM=OS3.0.3.0.VMNEUXM cw_guard
[ -f "$CW_MODDIR/skip_mount" ]
[ "$(cat "$CW_MODDIR/state/guard_reason")" = ROM_MISMATCH ]
ok "early OTA guard turns deployment off"
cw_deploy
FAKE_BOOT=boot-5 CORRUPT_CORE=services.jar cw_guard
[ -f "$CW_MODDIR/skip_mount" ]
[ "$(cat "$CW_MODDIR/state/guard_reason")" = SERVICES_MISMATCH ]
ok "early framework guard turns deployment off"
FAKE_ROM='bad"rom\with
newline' cw_status > "$fixture/escaped-status.json"
STATUS_FILE="$fixture/escaped-status.json" "$PYTHON_EXE" -c \
  'import json,os; s=json.load(open(os.environ["STATUS_FILE"])); assert "\"" in s["rom"] and "\\" in s["rom"]'
ok "JSON quotes, backslashes, and control characters"
mkdir -p "$CW_MODDIR/state"
printf 'APatch\n' > "$CW_MODDIR/state/manager"
[ "$(cw_backend)" = unconfirmed ]
mkdir -p "$CW_ADB/modules/fake_mount"
printf 'id=fake_mount\nmetamodule=1\n' > "$CW_ADB/modules/fake_mount/module.prop"
touch "$CW_ADB/modules/fake_mount/mount.sh"
[ "$(cw_backend)" = unconfirmed ]
expect_error MOUNT_BACKEND_MISSING cw_deploy
cw_write_state mount_mode invalid
expect_error MOUNT_BACKEND_MISSING cw_deploy
rm -f "$CW_MODDIR/skip_mount"
cw_guard
[ -f "$CW_MODDIR/skip_mount" ]
[ "$(cat "$CW_MODDIR/state/guard_reason")" = MOUNT_BACKEND_MISSING ]
ok "APatch requires native configuration even with a third-party backend present"

echo "RESULT $passed host fixture groups passed; no device validation."
