# notes to self

scratch pad, not docs. don't judge.

## works
adb/fastboot, heimdall + odin4, qdl, qcdiag, antumbra, spd_dump, pacextractor,
rkdeveloptool, the whole idevice/img4/irecovery/gaster pile, oppo_decrypt.
62MB public zip, all aarch64 static, maps on 4k and 16k.

## dropped (for now)
- sfd_tool -> the C-Hidery fork bakes gtk4 straight into the core (logging.cpp
  pulls GtkWidgetHelper), still true in 3.6.x even with USE_GTK=OFF. shipping
  TomKing062/spreadtrum_flash as spd_dump_tk instead, that's the cli sfd_tool
  forked from, same command set. fb unisoc sfd points at it.
- strace -> fixed. strace ships the new uapi headers under bundled/, but clang
  treats that path as system and zig's older copy wins. copying them to
  $BLD/uapi and passing -I does it.
- palera1n + futurerestore -> palera1n-c wants its submodules, futurerestore
  wants the whole tihmstar lib zoo (libipatcher, liboffsetfinder64, libinsn,
  libfragmentzip, libimg4tool-as-a-lib). that's a weekend on its own. recipes
  are stubbed, deps are the TODO below.

## gotchas i keep forgetting
- NEVER wrap the build subshell in `|| die`, errexit dies inside it (posix).
  cost me a whole debugging session thinking builds passed when they didn't.
- tihmstar projects need deep=1 (full clone) or their version comes out as 1
  and the >= 92 pkg-config checks fail.
- everything needs -fPIC. cryptopp and lz4 both threw ABS64 reloc errors.
- qdl #defines __unused which is also a musl struct stat member. sed it out.
- cargo-zigbuild: do NOT set CC_<triple>, it fights ring's build.rs.
- a dir given as both -I and -isystem counts as -isystem. copy it somewhere
  else if it has to win over zig's headers (strace).
- musl: major()/minor() need sys/sysmacros.h, no sys/queue.h at all (f2fs-tools).
- file: magic.mgc must come from a file of the same version, build a host one.
- fb distro: /data is nosuid,nodev. bind the rootfs onto itself and remount
  that bind, /data stays untouched. apt's _apt user needs aid_inet (3003).

## TODO
- [ ] futurerestore chain (the 5 tihmstar libs)
- [ ] palera1n submodules
- [ ] bkerler/unisoc wiring for `fb unisoc bk`
- [ ] maybe trim the MTK DA blobs, 56MB is a lot
- [ ] test on an actual 16k device, only checked the ELF math so far
- [ ] sfd_tool cli patch if i'm bored (spd_dump_tk covers it meanwhile)
- [ ] fb distro on a real 16k device, only ran the flow with the amd64 image on a pc
