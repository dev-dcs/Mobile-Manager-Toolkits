# notes to self

scratch pad, not docs. don't judge.

## works
adb/fastboot, heimdall + odin4, qdl, qcdiag, antumbra, spd_dump, pacextractor,
rkdeveloptool, the whole idevice/img4/irecovery/gaster pile, oppo_decrypt.
62MB public zip, all aarch64 static, maps on 4k and 16k.

## dropped (for now)
- sfd_tool -> the C-Hidery fork bakes gtk4 straight into the core (logging.cpp
  pulls GtkWidgetHelper), can't get a clean cli build without basically
  rewriting their cmake. spd_dump already does the unisoc download-mode stuff
  so meh. left the recipe as .disabled if i ever care enough.
- strace -> 7.x and even 6.19 reference brand new kernel structs
  (FD_FAILFS_ROOT, io_uring_query_zcrx) that zig's bundled headers don't have.
  would need to ship newer linux-libc-dev. not worth it for a tracer nobody's
  gonna run on the bench anyway.
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

## TODO
- [ ] futurerestore chain (the 5 tihmstar libs)
- [ ] palera1n submodules
- [ ] bkerler/unisoc wiring for `fb unisoc bk`
- [ ] maybe trim the MTK DA blobs, 56MB is a lot
- [ ] test on an actual 16k device, only checked the ELF math so far
- [ ] sfd_tool cli patch if i'm bored
