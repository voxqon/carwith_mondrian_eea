#!/system/bin/sh
CW_MODDIR=$(CDPATH= cd -- "${0%/*}" && pwd) || exit 1
# Magisk's Action button can launch the shared WebUI in a compatible host.
if pm path --user 0 com.dergoogler.mmrl.wx >/dev/null 2>&1; then
  if am start --user 0 -n com.dergoogler.mmrl.wx/.ui.webui.WebUIActivity \
    --es MODULE_ID carwith_mondrian_eea >/dev/null 2>&1; then
    echo "Opening CarWith in WebUI X: Portable."
    exit 0
  fi
fi
echo "APatch: open this module's WebUI."
echo "Magisk: install WebUI X: Portable, grant root and shell access,"
echo "then select 'CarWith for mondrian EEA' from the module list."
echo "Status:"
sh "$CW_MODDIR/control.sh" status
