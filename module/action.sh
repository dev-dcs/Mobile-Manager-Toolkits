#!/system/bin/sh
# action button in the root manager - @Dev_DcS
MODDIR=${0%/*}

sh "$MODDIR/libexec/fb-usb.sh"
echo
sh "$MODDIR/libexec/fb-doctor.sh" --short
if [ -f "$MODDIR/libexec/fb-watch.sh" ]; then
	echo
	sh "$MODDIR/libexec/fb-watch.sh" --status
fi
