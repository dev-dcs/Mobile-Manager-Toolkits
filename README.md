# FlashBench

Root module that turns an Android phone into a complete device-management and
forensics bench. Plug any device — Android, Samsung, Qualcomm, MediaTek,
Unisoc, Rockchip, or even an iPhone — over OTG and work on it from a root shell.

by @Dev_DcS

- arm64 only, Android 15–17 (API 35-37), both 4K and 16K page kernels
- Magisk, KernelSU or APatch
- every binary is static musl (zig + cargo-zigbuild), 16K-aligned, verified at build + install

## What is inside

| vendor / job | tool |
|---|---|
| **AOSP** adb, fastboot | `adb`, `fastboot` and all image tools (nmeum/android-tools 37) |
| **Samsung** download (Odin/Thor) | `heimdall`, `odin4` (Thor), `samloader` (firmware download + flash) |
| **Samsung** Exynos BootROM | `exynos-usbdl` |
| **Qualcomm** EDL 9008 | `qdl` (Sahara + Firehose) |
| **Qualcomm** DIAG | `qcdiag` (NV/EFS/SPC/bands) |
| **MediaTek** V5/V6 XFlash | `antumbra` (penumbra, Rust native) |
| **MediaTek** V3/Legacy | `mtkclient` (Python, needs Termux) |
| **Unisoc / Spreadtrum** | `spd_dump`, `sfd_tool` (CLI), `pacextractor` |
| **Rockchip** maskrom | `rkdeveloptool` |
| **Oppo / Realme / OnePlus** | `oppo_decrypt` (Python, .ofp/.ops) |
| **Apple / iOS** (OTG host) | `irecovery`, `img4tool`, `img3tool`, `gaster` (checkm8), `idevice-tools` (Rust), `libimobiledevice` tools |
| **Apple / iOS** (master only) | `palera1n`, `futurerestore` |
| boot images | `magiskboot`, `fb aik` (Android Image Kitchen style) |
| OTA payload.bin | `payload-dumper-go` |
| modem / baseband | `atcmd` (AT console), `mtools` (FAT modem image) |
| compression | `lz4 brotli xz` |
| analysis | `sqlite3`, `strace` |
| shell | `busybox` (full applet set), `nano` (with terminfo) |
| engineering | bootloader unlock lookup (wall-of-shame DB), SoC BootROM dumps |
| master only | `curl` |

`qcdiag`, `atcmd`, and `pacextractor` are native tools in `tools/`, built here. Everything else is upstream.

If the ROM already has a tool in `/system/bin`, the ROM keeps it and ours installs as `fb-<name>`.

## fb

    fb usb [-w]            plugged devices and their mode (adb, fastboot, odin, edl, brom, dfu, ...)
    fb info                summary of the connected device (adb / fastboot / odin)
    fb doctor              is this phone ready (root, usb host, binaries, page alignment)
    fb forensic ...        triage, acquire, image, apps, verify
    fb debug ...           logcat, crash, boot, selinux, app, snapshot/diff, screen, record
    fb samsung ...         unpack firmware, read PIT, flash (odin4/heimdall), download (samloader)
    fb ota ...             list / extract payload.bin
    fb aik ...             Android Image Kitchen style boot editing via magiskboot
    fb modem ...           baseband: backup/restore, AT, Qualcomm NV/EFS, LTE/NR bands, carrier, MBN
    fb ak3 ...             AnyKernel3 zip → flashable boot.img
    fb unroot ...          remove Magisk / KernelSU / APatch and restore stock boot
    fb mtk ...             MediaTek: flash, readback, unlock (antumbra / mtkclient)
    fb unisoc ...          Unisoc: spd_dump, sfd_tool, pacextractor
    fb oppo ...            Oppo/Realme/OnePlus .ofp/.ops firmware decrypt
    fb eng ...             bootloader unlock lookup, eng root check, SoC BootROMs
    fb ios ...             Apple: idevice, irecovery, img4, gaster, palera1n, futurerestore
    fb log ...             rotating logcat catcher for this phone (start/stop/save/boot)
    fb watch ...           upstream source watcher

`fb ak3`, `fb unroot`, `fb modem` always back up before writing. `fb modem` never
writes device identities (IMEI/MEID/ESN). `fb unroot` refuses a half-clean without
`--partial`.

Config, adb keys and output all live under `/data/local/tmp/flashbench/`
(output in `out/`). Nothing is written to the target except what adb itself
needs (`fb debug record` uses a temp file and removes it).

## Install-time conflict check

If any of the bundled command names already exist on the device (AOSP ships
`make_f2fs`, `sqlite3`, `mke2fs` and friends), the installer stops and asks what
to do, with a 20-second window:

- **Vol-** moves the selection, **Vol+** confirms
- **1** cancel the install
- **2** continue anyway — ours shadow the system commands (risky)
- **3** keep the system's, install ours as `fb-<name>` (default; also what
  happens if the 20s elapses or the installer can't read keys, e.g. a KSU app
  install)

## Updates

Two channels:

- **Public zip**: `module.prop` has `updateJson`, so Magisk/KernelSU/APatch show
  the usual "update available" when a new release is tagged.
- **Master build** (your own, no updateJson): `fb watch` polls the git repos of
  every bundled tool (plain smart-HTTP, no API token, no git needed) and when one
  has a newer release it posts an Android notification, optionally a ntfy push,
  and writes a status line into the module description shown by the manager.
  GitHub Actions runs the same check daily and keeps an `upstream` issue open
  while something is outdated.

A weekly job (`weekly.yml`) rolls the pinned git sources forward to their latest
upstream and, when anything moved, tags a new patch release on its own, so the
public zip tracks upstream without a hand on the wheel.

## Building

Host needs: zig 0.17 (`pip install ziglang==0.17.1`), Rust (`rustup`, with
`cargo-zigbuild` from pip), cmake, ninja, meson 1.8+ (get it from pip, not your
distro - older meson can't figure out zig's linker), autotools, pkg-config, go,
llvm-strip, git, curl, zip.

    ./build.sh --list              what the public profile pulls in
    ./build.sh                     public zip in out/
    ./build.sh -p master           master zip, needs private/ (see private.example)
    ./build.sh qdl heimdall        just these, no zip
    ./build.sh -f                  only download + verify sources

Every source is pinned: git components by commit, archives by sha256.
`config/components.list` is the single list of pins; recipes are in `recipes/`.

    scripts/upstream-check.sh            what has a newer release
    scripts/upstream-check.sh --write    bump git pins
    scripts/release.sh bump minor        new version + changelog stub, then tag vX.Y.Z

Public vs private: everything in the repo is the public part. `private/` (git
ignored) holds the master profile, secrets, extra recipes, patches and module
files. Copy `private.example/` to start.

## Notes

- Static musl binaries cannot use Android's DNS resolver: `adb connect` needs an
  IP, and `curl` gets `--doh-url` from fb.
- Root is needed for raw USB access (`/dev/bus/usb`).
- Some phones turn OTG off after a few idle minutes, check settings if `fb usb` is empty.

## Licenses

Bundled tools keep their own licenses, collected in `licenses/` inside the zip.
