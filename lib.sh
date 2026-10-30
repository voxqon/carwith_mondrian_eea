#!/system/bin/sh

CW_ID=carwith_mondrian_eea
CW_ADB=/data/adb
CW_SYSTEM=
CW_ROM=OS3.0.2.0.VMNEUXM
CW_APK_SHA=081ac798b3a114f14e602b2cb1c5c691ff2cb47009c1a6ba4eebbb4e87caeb2f
CW_JAR_SHA=292e38490c907831a0cfde59db383418da34b32d0d102a52ca6ce98e190285f3
CW_CARLIFE_SHA=00df4aaacbbc5837f3a0ef17fc55dfabf038596dd27b652cfb23c9722770a994
CW_CARLIFE_NATIVE_SHA=420c6de2436243a6d09889e1d6e50fae5aea6aa3224e8cd007f6c04053f1ba78
CW_LAYER_SHA=ab9b57795fb1cd4bbc2b483673bab1154c7ee0ddf1ad6aefce2c9d1274a7c4a6
CW_FILESYSTEMS=/proc/filesystems
CW_MOUNTINFO=/proc/1/mountinfo

cw_error() {
  CW_ERROR=$1
  return 1
}

cw_root() {
  [ "$(id -u)" = 0 ] || cw_error ROOT_REQUIRED
}

cw_hash_matches() {
  [ -f "$1" ] || return 1
  local result
  result=$(sha256sum "$1" 2>/dev/null) || return 1
  [ "${result%% *}" = "$2" ]
}

cw_check_rom() {
  CW_ERROR=
  [ "$(getprop ro.product.vendor.device)" = mondrian ] || { cw_error DEVICE_MISMATCH; return 1; }
  [ "$(getprop ro.product.mod_device)" = mondrian_eea_global ] || { cw_error REGION_MISMATCH; return 1; }
  [ "$(getprop ro.build.version.sdk)" = 35 ] || { cw_error SDK_MISMATCH; return 1; }
  [ "$(getprop ro.product.cpu.abi)" = arm64-v8a ] || { cw_error ABI_MISMATCH; return 1; }
  [ "$(getprop ro.build.version.incremental)" = "$CW_ROM" ] || { cw_error ROM_MISMATCH; return 1; }
  cw_hash_matches "$CW_SYSTEM/system/framework/framework.jar" 6e961ac72a73285005fc68c87e714a18b910a5cb6bbfc13d6bc120ad350de5d7 ||
    { cw_error FRAMEWORK_MISMATCH; return 1; }
  cw_hash_matches "$CW_SYSTEM/system/framework/services.jar" 5fea9ffbfcd324a11dca6b5cdb15730d5c33dcd98e3e70ce85d7ca031d4bfd1a ||
    { cw_error SERVICES_MISMATCH; return 1; }
  cw_hash_matches "$CW_SYSTEM/system_ext/framework/miui-framework.jar" b69066e56a7f428effaba2ac36e2a0246c8fe2f48e87df705ab0e42562196422 ||
    { cw_error MIUI_FRAMEWORK_MISMATCH; return 1; }
  cw_hash_matches "$CW_SYSTEM/system_ext/framework/miui-services.jar" 101ab36c77214b7b451828b4a53d7ac0a6590c98183f05e3426bf3f490b47cf1 ||
    { cw_error MIUI_SERVICES_MISMATCH; return 1; }
}

cw_payload_paths() {
  CW_APK="$CW_MODDIR/system/product/app/CarWith/CarWith.apk"
  CW_CARLIFE="$CW_MODDIR/system/product/app/CarLife/CarLife.apk"
  CW_JAR="$CW_MODDIR/system/system_ext/framework/miui.car.server.jar"
  # APatch's installer moves separate partitions and leaves relative symlinks.
  [ -f "$CW_APK" ] || CW_APK="$CW_MODDIR/product/app/CarWith/CarWith.apk"
  [ -f "$CW_CARLIFE" ] || CW_CARLIFE="$CW_MODDIR/product/app/CarLife/CarLife.apk"
  [ -f "$CW_JAR" ] || CW_JAR="$CW_MODDIR/system_ext/framework/miui.car.server.jar"
}

cw_carlife_native_matches() {
  cw_hash_matches "$CW_MODDIR/carlife-native.sha256" "$CW_CARLIFE_NATIVE_SHA" || return 1
  (
    cd "$1" 2>/dev/null &&
      sha256sum -c "$CW_MODDIR/carlife-native.sha256" >/dev/null 2>&1
  )
}

cw_check_payload() {
  cw_payload_paths
  cw_hash_matches "$CW_APK" "$CW_APK_SHA" || { cw_error APK_CORRUPT; return 1; }
  cw_hash_matches "$CW_JAR" "$CW_JAR_SHA" || { cw_error JAR_CORRUPT; return 1; }
  cw_hash_matches "$CW_CARLIFE" "$CW_CARLIFE_SHA" || { cw_error CARLIFE_CORRUPT; return 1; }
  cw_carlife_native_matches "${CW_CARLIFE%/*}/lib/arm64" ||
    { cw_error CARLIFE_LIBS_CORRUPT; return 1; }
}

cw_desired() {
  if [ "$(cw_mode)" = apatch_overlay ]; then
    if [ "$(cat "$CW_MODDIR/state/deployment" 2>/dev/null)" = on ]; then echo on; else echo off; fi
  elif [ -f "$CW_MODDIR/skip_mount" ]; then
    echo off
  else
    echo on
  fi
}

cw_mode() {
  if [ "$(cat "$CW_MODDIR/state/mount_mode" 2>/dev/null)" = apatch_overlay ]; then
    echo apatch_overlay
  else
    echo standard
  fi
}

cw_boot_id() {
  cat /proc/sys/kernel/random/boot_id 2>/dev/null
}

cw_write_state() {
  mkdir -p "$CW_MODDIR/state" || return 1
  chmod 0700 "$CW_MODDIR/state" || return 1
  (
    umask 077
    printf '%s\n' "$2" > "$CW_MODDIR/state/$1.tmp.$$" &&
      mv -f "$CW_MODDIR/state/$1.tmp.$$" "$CW_MODDIR/state/$1"
  )
}

cw_block_mount() {
  touch "$CW_MODDIR/skip_mount" || return 1
  if [ "$(cw_mode)" = apatch_overlay ]; then
    cw_write_state deployment off || return 1
  fi
  cw_write_state guard_reason "$1"
}

cw_guard() {
  # Called by the common post-fs-data hook BEFORE the manager mounts modules.
  [ -f "$CW_MODDIR/module.prop" ] || return 0
  [ -f "$CW_MODDIR/disable" ] && return 0
  [ -f "$CW_MODDIR/remove" ] && return 0
  # APatch's native overlay must never also enter a MetaModule's mount tree.
  if [ "$(cw_mode)" = apatch_overlay ]; then
    touch "$CW_MODDIR/skip_mount" || return 1
  fi
  if [ "$(cw_desired)" = on ]; then
    if ! cw_check_rom || ! cw_check_payload || ! cw_check_backend; then
      cw_block_mount "${CW_ERROR:-VALIDATION_FAILED}" || return 1
    fi
  fi
  cw_write_state boot_id "$(cw_boot_id)" || return 1
  cw_write_state boot_choice "$(cw_desired)"
}

cw_check_hook() {
  cw_hash_matches "$CW_ADB/post-fs-data.d/${CW_ID}_guard.sh" \
    "$(sha256sum "$CW_MODDIR/boot-guard.sh" 2>/dev/null | cut -d ' ' -f 1)" ||
    { cw_error GUARD_MISSING; return 1; }
  [ -x "$CW_ADB/post-fs-data.d/${CW_ID}_guard.sh" ] ||
    { cw_error GUARD_MISSING; return 1; }
}

cw_update_pending() {
  [ -d "$CW_ADB/modules_update/$CW_ID" ] || [ -f "$CW_MODDIR/update" ]
}

cw_deploy() {
  cw_root || return 1
  [ ! -f "$CW_MODDIR/disable" ] || { cw_error MODULE_DISABLED; return 1; }
  [ ! -f "$CW_MODDIR/remove" ] || { cw_error MODULE_REMOVING; return 1; }
  if cw_update_pending; then cw_error UPDATE_PENDING; return 1; fi
  cw_check_rom && cw_check_payload && cw_check_hook && cw_check_backend || return 1
  if [ "$(cw_mode)" = apatch_overlay ]; then
    touch "$CW_MODDIR/skip_mount" &&
      cw_write_state deployment on || { cw_error WRITE_FAILED; return 1; }
  else
    rm -f "$CW_MODDIR/skip_mount" || { cw_error WRITE_FAILED; return 1; }
  fi
  rm -f "$CW_MODDIR/state/guard_reason"
}

cw_undeploy() {
  cw_root || return 1
  touch "$CW_MODDIR/skip_mount" || { cw_error WRITE_FAILED; return 1; }
  if [ "$(cw_mode)" = apatch_overlay ]; then
    cw_write_state deployment off || { cw_error WRITE_FAILED; return 1; }
  fi
  # An already staged update must not re-enable deployment on the next boot.
  if [ -d "$CW_ADB/modules_update/$CW_ID" ]; then
    touch "$CW_ADB/modules_update/$CW_ID/skip_mount" ||
      { cw_error WRITE_FAILED; return 1; }
    (
      CW_MODDIR="$CW_ADB/modules_update/$CW_ID"
      if [ "$(cw_mode)" = apatch_overlay ]; then cw_write_state deployment off; fi
    ) || { cw_error WRITE_FAILED; return 1; }
  fi
}

cw_manager() {
  if [ -f "$CW_MODDIR/state/manager" ]; then
    cat "$CW_MODDIR/state/manager"
  elif [ "${APATCH:-}" = true ]; then
    echo APatch
  else
    echo Magisk
  fi
}

cw_backend() {
  case "$(cw_manager)" in
    Magisk) echo magisk; return ;;
    APatch)
      # Missing native-mode state must never fall back to third-party mounting.
      if [ "$(cw_mode)" = apatch_overlay ]; then
        if grep -qw overlay "$CW_FILESYSTEMS" && grep -qw erofs "$CW_FILESYSTEMS"; then
          echo apatch_overlay
        else
          echo overlay_unsupported
        fi
        return
      fi
      ;;
  esac
  echo unconfirmed
}

cw_check_backend() {
  case "${1:-$(cw_backend)}" in
    magisk) return 0 ;;
    apatch_overlay)
      cw_hash_matches "$CW_MODDIR/carwith-layer.img" "$CW_LAYER_SHA" ||
        { cw_error LAYER_CORRUPT; return 1; }
      [ -x "$CW_MODDIR/post-mount.sh" ] ||
        { cw_error OVERLAY_HOOK_MISSING; return 1; }
      ;;
    overlay_unsupported) cw_error OVERLAY_UNSUPPORTED; return 1 ;;
    *) cw_error MOUNT_BACKEND_MISSING; return 1 ;;
  esac
}

cw_overlay_state() {
  [ -r "$CW_MOUNTINFO" ] || { echo unknown; return; }
  local count
  count=$(awk -v base="$CW_MODDIR/overlay_root/" '
    ($5 == "/system_ext/framework" || $5 == "/product/app") &&
    $6 ~ /^ro(,|$)/ && / - overlay / {
      relative=substr($5, 2)
      if (index($0, "lowerdir=" base relative ":" $5) ||
          index($0, "lowerdir=" relative ":" $5)) n++
    }
    END {print n+0}
  ' "$CW_MOUNTINFO")
  case "$count" in 0) echo missing ;; 2) echo active ;; *) echo partial ;; esac
}

cw_overlay_mount() {
  [ "$(cw_mode)" = apatch_overlay ] || return 0
  [ "$(cw_manager)" = APatch ] || return 0
  [ ! -f "$CW_MODDIR/disable" ] && [ ! -f "$CW_MODDIR/remove" ] || return 0
  [ "$(cw_desired)" = on ] || return 0
  # This hook belongs to the boot stage; never replace a live service's files.
  [ "$(getprop sys.boot_completed)" != 1 ] || { cw_error BOOT_STAGE_REQUIRED; return 1; }
  if ! cw_check_rom || ! cw_check_payload || ! cw_check_hook || ! cw_check_backend; then
    cw_block_mount "$CW_ERROR"
    return 1
  fi
  [ "$(cw_overlay_state)" != active ] || return 0
  if [ -e "$CW_SYSTEM/system_ext/framework/miui.car.server.jar" ] ||
     [ -e "$CW_SYSTEM/product/app/CarWith" ] ||
     [ -e "$CW_SYSTEM/product/app/CarLife" ]; then
    cw_block_mount TARGET_ALREADY_PRESENT
    return 1
  fi
  if (
    CW_LAYER="$CW_MODDIR/overlay_root"
    mkdir -p "$CW_LAYER" && chmod 0700 "$CW_LAYER" || exit 1
    cw_overlay_cleanup() {
      cd / || return 1
      [ "${CW_APP_MOUNTED:-}" != yes ] || umount /product/app
      [ "${CW_FW_MOUNTED:-}" != yes ] || umount /system_ext/framework
      [ "${CW_LAYER_MOUNTED:-}" != yes ] || umount "$CW_LAYER"
    }
    trap cw_overlay_cleanup EXIT
    mount -t erofs -o ro,loop "$CW_MODDIR/carwith-layer.img" "$CW_LAYER" || exit 1
    CW_LAYER_MOUNTED=yes
    cd "$CW_LAYER" || exit 1
    mount -t overlay overlay -o "ro,lowerdir=system_ext/framework:/system_ext/framework" /system_ext/framework || exit 1
    CW_FW_MOUNTED=yes
    mount -t overlay overlay -o "ro,lowerdir=product/app:/product/app" /product/app || exit 1
    CW_APP_MOUNTED=yes
    # OverlayFS holds the lower mount reference after the staging mount detaches.
    cd / || exit 1
    umount -l "$CW_LAYER" || exit 1
    CW_LAYER_MOUNTED=no
    cw_hash_matches /system_ext/framework/miui.car.server.jar "$CW_JAR_SHA" &&
      cw_hash_matches /product/app/CarWith/CarWith.apk "$CW_APK_SHA" &&
      cw_hash_matches /product/app/CarLife/CarLife.apk "$CW_CARLIFE_SHA" &&
      cw_carlife_native_matches /product/app/CarLife/lib/arm64 || exit 1
    trap - EXIT
  ); then
    cw_write_state mount_result OVERLAY_MOUNTED
  else
    cw_block_mount OVERLAY_MOUNT_FAILED
    cw_write_state boot_choice off
    return 1
  fi
}

cw_json_string() {
  # All fields are single-line diagnostics; flatten control characters.
  printf '"'
  printf '%s' "$1" | tr '\000-\037' ' ' | sed 's/\\/\\\\/g; s/"/\\"/g'
  printf '"'
}

cw_field() {
  [ "$CW_FIRST" = yes ] || printf ','
  CW_FIRST=no
  cw_json_string "$1"
  printf ':'
  cw_json_string "$2"
}

cw_is_system_package() {
  sed -n 's/^[[:space:]]*pkgFlags=\[\([^]]*\)\].*/\1/p; s/^[[:space:]]*flags=\[\([^]]*\)\].*/\1/p' |
    tr ' ' '\n' | grep -qx SYSTEM
}

cw_status() {
  cw_root || return 1
  local rom_error payload_error hook_error desired boot_choice boot_id pending enabled update
  local apk_state jar_state service_state pkg_state pkg_paths service_output pkg_dump system_app
  local backend_error backend conflict overlay_state
  local carlife_state carlife_native carlife_pkg carlife_paths carlife_system carlife_dump
  local carlife_version carlife_code carlife_compatible
  rom_error=OK
  cw_check_rom || rom_error=$CW_ERROR
  payload_error=OK
  cw_check_payload || payload_error=$CW_ERROR
  hook_error=OK
  cw_check_hook || hook_error=$CW_ERROR
  desired=$(cw_desired)
  boot_choice=unknown
  boot_id=$(cat "$CW_MODDIR/state/boot_id" 2>/dev/null)
  if [ -n "$boot_id" ] && [ "$boot_id" = "$(cw_boot_id)" ]; then
    boot_choice=$(cat "$CW_MODDIR/state/boot_choice" 2>/dev/null)
  fi
  enabled=yes
  [ -f "$CW_MODDIR/disable" ] && enabled=disabled
  [ -f "$CW_MODDIR/remove" ] && enabled=removing
  update=no
  cw_update_pending && update=yes
  pending=no
  [ "$desired" = "$boot_choice" ] || pending=yes
  [ "$update" = no ] || pending=yes
  if [ "$enabled" != yes ] && [ "$boot_choice" = on ]; then pending=yes; fi
  apk_state=missing
  jar_state=missing
  carlife_state=missing
  carlife_native=missing
  if [ -f "$CW_SYSTEM/product/app/CarWith/CarWith.apk" ]; then
    apk_state=different
    cw_hash_matches "$CW_SYSTEM/product/app/CarWith/CarWith.apk" "$CW_APK_SHA" && apk_state=match
  fi
  if [ -f "$CW_SYSTEM/system_ext/framework/miui.car.server.jar" ]; then
    jar_state=different
    cw_hash_matches "$CW_SYSTEM/system_ext/framework/miui.car.server.jar" "$CW_JAR_SHA" && jar_state=match
  fi
  if [ -f "$CW_SYSTEM/product/app/CarLife/CarLife.apk" ]; then
    carlife_state=different
    cw_hash_matches "$CW_SYSTEM/product/app/CarLife/CarLife.apk" "$CW_CARLIFE_SHA" && carlife_state=match
  fi
  if [ -d "$CW_SYSTEM/product/app/CarLife/lib/arm64" ]; then
    carlife_native=different
    cw_carlife_native_matches "$CW_SYSTEM/product/app/CarLife/lib/arm64" && carlife_native=match
  fi
  service_output=$(service check MiuiCarService 2>/dev/null)
  service_state=unknown
  case "$service_output" in
    *"not found"*) service_state=missing ;;
    *": found"*) service_state=found ;;
  esac
  pkg_state=unknown
  system_app=unknown
  if pkg_paths=$(pm path --user 0 com.miui.carlink 2>/dev/null); then
    pkg_state=missing
    [ -z "$pkg_paths" ] || pkg_state=installed
  fi
  if [ "$pkg_state" = installed ]; then
    pkg_dump=$(dumpsys package com.miui.carlink 2>/dev/null)
    if printf '%s\n' "$pkg_dump" | cw_is_system_package; then
      system_app=yes
    else
      system_app=no
    fi
  fi
  carlife_pkg=unknown
  carlife_system=unknown
  carlife_version=
  carlife_code=
  carlife_compatible=unknown
  if carlife_paths=$(pm path --user 0 com.baidu.carlife.xiaomi 2>/dev/null); then
    carlife_pkg=missing
    [ -z "$carlife_paths" ] || carlife_pkg=installed
  fi
  if [ "$carlife_pkg" = installed ]; then
    carlife_dump=$(dumpsys package com.baidu.carlife.xiaomi 2>/dev/null)
    if printf '%s\n' "$carlife_dump" | cw_is_system_package; then
      carlife_system=yes
    else
      carlife_system=no
    fi
    carlife_version=$(printf '%s\n' "$carlife_dump" |
      sed -n 's/^[[:space:]]*versionName=//p' | head -n 1)
    carlife_code=$(printf '%s\n' "$carlife_dump" |
      sed -n 's/^[[:space:]]*versionCode=\([0-9][0-9]*\).*/\1/p' | head -n 1)
    if [ -n "$carlife_code" ]; then
      carlife_compatible=no
      [ "$carlife_code" -ge 220 ] && carlife_compatible=yes
    fi
  fi
  backend=$(cw_backend)
  backend_error=OK
  cw_check_backend "$backend" || backend_error=$CW_ERROR
  conflict=no
  if [ "$backend_error" != OK ] &&
     { [ "$apk_state" != missing ] || [ "$jar_state" != missing ] ||
       [ "$carlife_state" != missing ] || [ "$carlife_native" != missing ]; }; then conflict=yes; fi
  overlay_state=not_used
  if [ "$(cw_mode)" = apatch_overlay ]; then overlay_state=$(cw_overlay_state); fi
  CW_FIRST=yes
  printf '{'
  cw_field schema 1
  cw_field module_version "$(sed -n 's/^version=//p' "$CW_MODDIR/module.prop" | head -n 1)"
  cw_field manager "$(cw_manager)"
  cw_field mount_backend "$backend"
  cw_field backend_check "$backend_error"
  cw_field mount_conflict "$conflict"
  cw_field overlay_state "$overlay_state"
  cw_field device "$(getprop ro.product.vendor.device)"
  cw_field rom "$(getprop ro.build.version.incremental)"
  cw_field sdk "$(getprop ro.build.version.sdk)"
  cw_field compatibility "$rom_error"
  cw_field payload "$payload_error"
  cw_field guard "$hook_error"
  cw_field guard_reason "$(cat "$CW_MODDIR/state/guard_reason" 2>/dev/null)"
  cw_field enabled "$enabled"
  cw_field update_pending "$update"
  cw_field desired "$desired"
  cw_field boot_choice "$boot_choice"
  cw_field reboot_required "$pending"
  cw_field apk "$apk_state"
  cw_field jar "$jar_state"
  cw_field package "$pkg_state"
  cw_field system_app "$system_app"
  cw_field package_paths "$pkg_paths"
  cw_field carlife_apk "$carlife_state"
  cw_field carlife_native "$carlife_native"
  cw_field carlife_package "$carlife_pkg"
  cw_field carlife_system_app "$carlife_system"
  cw_field carlife_package_paths "$carlife_paths"
  cw_field carlife_version "$carlife_version"
  cw_field carlife_version_code "$carlife_code"
  cw_field carlife_compatible "$carlife_compatible"
  cw_field binder "$service_state"
  cw_field selinux "$(getenforce 2>/dev/null)"
  printf '}\n'
}
