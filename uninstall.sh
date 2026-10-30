#!/system/bin/sh
CW_HOOK=/data/adb/post-fs-data.d/carwith_mondrian_eea_guard.sh
if [ -f "$CW_HOOK" ] && grep -q '^# CARWITH_MONDRIAN_EEA_GUARD_V1$' "$CW_HOOK"; then
  rm -f "$CW_HOOK"
fi
# The root manager removes this module's files; Android manages app records/data.
