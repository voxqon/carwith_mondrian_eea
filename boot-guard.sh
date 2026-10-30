#!/system/bin/sh
# CARWITH_MONDRIAN_EEA_GUARD_V1
# Common hooks run before APatch's mounting backend, unlike module-local hooks.
for CW_GUARD_DIR in \
  /data/adb/modules/carwith_mondrian_eea \
  /data/adb/modules_update/carwith_mondrian_eea; do
  [ -f "$CW_GUARD_DIR/lib.sh" ] || continue
  (
    CW_MODDIR=$CW_GUARD_DIR
    . "$CW_MODDIR/lib.sh"
    cw_guard
  )
done
exit 0
