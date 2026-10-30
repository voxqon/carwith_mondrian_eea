#!/usr/bin/env sh
# Run against an install ZIP with a real XZ implementation; no Android mount.
set -eu
archive=$1
fixture=$2
[ ! -e "$fixture" ] || { echo "Use a new fixture directory" >&2; exit 1; }
mkdir -p "$fixture"
printf 'nodev\toverlay\nerofs\n' > "$fixture/filesystems"
CW_TEST_FILESYSTEMS="$fixture/filesystems"
export CW_TEST_FILESYSTEMS

test_applet() {
  if [ -n "${CW_TEST_EMULATOR:-}" ]; then
    "$CW_TEST_EMULATOR" "$CW_TEST_BUSYBOX" "$@"
  elif [ -n "${CW_TEST_BUSYBOX:-}" ]; then
    "$CW_TEST_BUSYBOX" "$@"
  else
    command "$@"
  fi
}
# Emulated ash may otherwise execute applets from the host's /bin/busybox.
unzip() { test_applet unzip "$@"; }
unxz() { test_applet unxz "$@"; }
dd() { test_applet dd "$@"; }
sha256sum() { test_applet sha256sum "$@"; }

prepare_case() {
  CW_TEST_ADB="$fixture/$1/adb"
  MODPATH="$fixture/$1/module"
  export CW_TEST_ADB MODPATH
  mkdir -p "$MODPATH"
  unzip -q "$archive" -x 'META-INF/*' -d "$MODPATH"
  # Only Android properties, framework lookup and SELinux permissions are mocked.
  printf '\nCW_ADB=$CW_TEST_ADB\nCW_FILESYSTEMS=$CW_TEST_FILESYSTEMS\ncw_check_rom() { return 0; }\n' >> "$MODPATH/lib.sh"
}

install_case() (
  BOOTMODE=true
  APATCH=false
  MAGISK_VER_CODE=26400
  KSU=false
  [ "$1" != APatch ] || APATCH=true
  ui_print() { printf '%s\n' "$*"; }
  abort() { printf '%s\n' "$*" >&2; exit 1; }
  set_perm() { chmod "$4" "$1"; }
  set_perm_recursive() { return 0; }
  case "${2:-}" in
    decoder)
      unxz() { return 1; }
      ;;
    native)
      dd() {
        test_applet dd "$@" || return 1
        for arg in "$@"; do
          case "$arg" in
            of=*/libc++_shared.so) printf corrupt >> "${arg#of=}" ;;
          esac
        done
      }
      ;;
    image)
      unxz() {
        test_applet unxz "$@" || return 1
        printf corrupt
      }
      ;;
  esac
  . "$MODPATH/customize.sh"
)

for manager in Magisk APatch; do
  prepare_case "$manager"
  install_case "$manager"
  [ -f "$MODPATH/skip_mount" ]
  [ ! -e "$MODPATH/carwith-layer.img.xz" ]
  [ ! -e "$MODPATH/payload.map" ]
  [ ! -e "$MODPATH/payload.sha256" ]
  [ "$(cat "$MODPATH/state/manager")" = "$manager" ]
  [ -x "$CW_TEST_ADB/post-fs-data.d/carwith_mondrian_eea_guard.sh" ]
  (
    CW_MODDIR=$MODPATH
    . "$MODPATH/lib.sh"
    cw_check_payload
    cw_hash_matches "$MODPATH/carwith-layer.img" "$CW_LAYER_SHA"
    [ "$(cw_desired)" = off ]
    cw_check_hook
    cw_check_backend
    if [ "$manager" = APatch ]; then
      [ "$(cat "$MODPATH/state/mount_mode")" = apatch_overlay ]
      [ "$(cat "$MODPATH/state/deployment")" = off ]
    fi
  )
  echo "PASS $manager: restored original files, image, disabled deployment, guard and archive cleanup"
done

prepare_case checksum
printf corrupt >> "$MODPATH/carwith-layer.img.xz"
if install_case Magisk; then echo "Corrupt archive accepted" >&2; exit 1; fi
[ ! -d "$MODPATH/system" ]
[ ! -d "$CW_TEST_ADB/post-fs-data.d" ]
echo "PASS compressed checksum failure blocks extraction and hook registration"

for fault in decoder native image; do
  prepare_case "$fault"
  if install_case APatch "$fault"; then echo "Invalid $fault accepted" >&2; exit 1; fi
  [ ! -d "$CW_TEST_ADB/post-fs-data.d" ]
  echo "PASS $fault failure blocks installation and hook registration"
done

for fault in path numeric; do
  prepare_case "map-$fault"
  if [ "$fault" = path ]; then
    printf '0 0 0 0 ../outside\n' > "$MODPATH/payload.map"
  else
    printf 'bad 0 0 0 system/product/app/CarWith/CarWith.apk\n' > "$MODPATH/payload.map"
  fi
  (
    cd "$MODPATH"
    sha256sum carwith-layer.img.xz payload.map > payload.sha256
  )
  if install_case Magisk; then echo "Invalid map $fault accepted" >&2; exit 1; fi
  [ ! -d "$MODPATH/system" ]
  [ ! -e "$fixture/map-$fault/outside" ]
  [ ! -d "$CW_TEST_ADB/post-fs-data.d" ]
  echo "PASS invalid map $fault blocks file writes and hook registration"
done
echo "RESULT 8 installation fixture groups passed; no Android device validation."
