#!/system/bin/sh
# config, adb keys and watcher state go away with the module.
# acquisitions under out/ are left behind so you don't lose evidence.
D=/data/local/tmp/flashbench
rm -f "$D"/fb.conf "$D"/watch.* "$D"/diag-prev-* 2>/dev/null
rm -rf "$D"/home 2>/dev/null
# only nuke the whole dir if nothing was acquired
rmdir "$D" 2>/dev/null
