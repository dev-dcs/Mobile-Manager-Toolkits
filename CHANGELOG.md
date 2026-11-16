## v1.1.1

-  component   status  ->  pinned ;  lz4   update  ->  v1.11.0 ;  protobuf   held  ->  v21.12 ;  busybox   error  ->  1.36.1 ; 

## v1.1.0

Shell comforts and a logcat catcher.

- busybox: the full applet set (grep, find, vi, awk, xxd, tar, unzip and the rest),
  vendored as the static arm64 NDK build.
- nano: the editor plus its terminfo, so it draws right in any root shell.
- fb log: a rotating logcat catcher for THIS phone. start/stop, save a snapshot,
  follow live, or have it come up on boot - handy for a crash you weren't watching.
- weekly.yml rolls the pinned git sources to upstream and tags a release when
  anything moved.

## v1.0.0

Android + iOS device-management bench. arm64, Android 15-17, both 4K and 16K
page kernels. Magisk / KernelSU / APatch.

Vendors:
- AOSP: adb, fastboot, lp*/simg/mkbootimg, payload-dumper-go, magiskboot, avbtool, fb aik
- Samsung: heimdall, odin4 (Thor), samloader, exynos-usbdl
- Qualcomm: qdl (EDL), qcdiag (DIAG NV/EFS/bands)
- MediaTek: antumbra (penumbra, native); mtkclient (master build)
- Unisoc: spd_dump, pacextractor
- Rockchip: rkdeveloptool
- Oppo/Realme/OnePlus: oppo_decrypt
- Apple iOS: irecovery, img4tool, img3tool, gaster (checkm8), libimobiledevice (20 tools), idevice-tools (Rust)

Toolkit (fb <cmd>): usb, info, doctor, forensic, debug, samsung, ota, payload,
avb, aik, modem, ak3, unroot, mtk, unisoc, oppo, eng, ios, watch.

Build: static musl via zig (C/C++) and cargo-zigbuild (Rust). Every binary is
16K-aligned (maps on 4K and 16K kernels), verified at build, install and by fb doctor.

Not included: sfd_tool (GTK-entangled, spd_dump covers Unisoc), strace (kernel-header
conflicts with the cross toolchain), palera1n/futurerestore (need deeper iOS lib stack).
