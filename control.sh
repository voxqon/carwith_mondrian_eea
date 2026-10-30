#!/system/bin/sh
CW_MODDIR=$(CDPATH= cd -- "${0%/*}" && pwd) || exit 1
. "$CW_MODDIR/lib.sh"
cw_root || { echo ROOT_REQUIRED >&2; exit 1; }

case "${1:-status}" in
  status) cw_status ;;
  deploy)
    if cw_deploy; then echo DEPLOY_SCHEDULED; else echo "$CW_ERROR" >&2; exit 1; fi
    ;;
  undeploy)
    if cw_undeploy; then echo UNDEPLOY_SCHEDULED; else echo "$CW_ERROR" >&2; exit 1; fi
    ;;
  open)
    [ "$(getprop sys.boot_completed)" = 1 ] || { echo BOOT_INCOMPLETE >&2; exit 1; }
    am start --user 0 -n com.miui.carlink/com.carwith.launcher.settings.phone.UCarConnectInfoActivity
    ;;
  reboot)
    [ "$(getprop sys.boot_completed)" = 1 ] || { echo BOOT_INCOMPLETE >&2; exit 1; }
    /system/bin/reboot
    ;;
  *) echo UNKNOWN_COMMAND >&2; exit 2 ;;
esac
