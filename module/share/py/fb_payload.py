#!/usr/bin/env python3
# fb_payload - build and inspect Android A/B update_engine payload.bin files.
# No protobuf runtime needed: the manifest is encoded/decoded by hand for the
# small field set a full payload uses.  @Dev_DcS
#
#   fb_payload info   <payload.bin>
#   fb_payload repack -o out.bin  boot:boot.img  system:system.img  [--xz] [--block-size N]
#   fb_payload repack -o out.bin  --from-dir extracted/            (name.img -> name)
#
# "repack" makes a FULL payload (one REPLACE op per partition). It is unsigned;
# flash it with update_engine where verification allows unsigned, or sign the
# metadata yourself. Delta payloads are out of scope.

import argparse
import hashlib
import lzma
import os
import struct
import sys

MAGIC = b"CrAU"
VERSION = 2

# field numbers from system/update_engine/update_metadata.proto
# DeltaArchiveManifest: block_size=3, minor_version=12, partitions=13
# PartitionUpdate: partition_name=1, new_partition_info=7, operations=8
# PartitionInfo: size=1, hash=2
# InstallOperation: type=1, data_offset=2, data_length=3, dst_extents=6
# Extent: start_block=1, num_blocks=2 ; InstallOperation.Type REPLACE=0 REPLACE_XZ=8
REPLACE, REPLACE_XZ = 0, 8


# ---- minimal protobuf wire encoder -------------------------------------

def _varint(n):
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        out.append(b | (0x80 if n else 0))
        if not n:
            return bytes(out)


def _tag(field, wire):
    return _varint((field << 3) | wire)


def f_varint(field, n):
    return _tag(field, 0) + _varint(n)


def f_bytes(field, b):
    return _tag(field, 2) + _varint(len(b)) + b


def extent(start, num):
    return f_varint(1, start) + f_varint(2, num)


def part_info(size, sha):
    return f_varint(1, size) + f_bytes(2, sha)


def install_op(op_type, data_offset, data_length, num_blocks):
    return (f_varint(1, op_type) + f_varint(2, data_offset) +
            f_varint(3, data_length) + f_bytes(6, extent(0, num_blocks)))


def partition_update(name, info, op):
    return (f_bytes(1, name.encode()) + f_bytes(7, info) + f_bytes(8, op))


# ---- minimal protobuf wire decoder (for info / round-trip) -------------

def _rd_varint(buf, i):
    shift = res = 0
    while True:
        b = buf[i]
        i += 1
        res |= (b & 0x7F) << shift
        if not (b & 0x80):
            return res, i
        shift += 7


def _fields(buf):
    """yield (field_number, wire_type, value) at top level"""
    i, n = 0, len(buf)
    while i < n:
        key, i = _rd_varint(buf, i)
        field, wire = key >> 3, key & 7
        if wire == 0:
            val, i = _rd_varint(buf, i)
        elif wire == 2:
            ln, i = _rd_varint(buf, i)
            val = buf[i:i + ln]
            i += ln
        elif wire == 5:
            val = buf[i:i + 4]
            i += 4
        elif wire == 1:
            val = buf[i:i + 8]
            i += 8
        else:
            raise ValueError("bad wire type %d" % wire)
        yield field, wire, val


# ---- build -------------------------------------------------------------

def repack(outpath, parts, block_size, use_xz):
    manifest = f_varint(3, block_size) + f_varint(12, 0)
    blobs = bytearray()
    data_off = 0
    rows = []

    for name, path in parts:
        raw = open(path, "rb").read()
        size = len(raw)
        nblocks = (size + block_size - 1) // block_size
        padded = raw + b"\0" * (nblocks * block_size - size)
        sha = hashlib.sha256(raw).digest()

        if use_xz:
            data = lzma.compress(padded, format=lzma.FORMAT_XZ,
                                 check=lzma.CHECK_NONE, preset=6)
            op_type = REPLACE_XZ
        else:
            data = padded
            op_type = REPLACE

        op = install_op(op_type, data_off, len(data), nblocks)
        info = part_info(size, sha)
        manifest += f_bytes(13, partition_update(name, info, op))
        blobs += data
        rows.append((name, size, nblocks, len(data)))
        data_off += len(data)

    with open(outpath, "wb") as f:
        f.write(MAGIC)
        f.write(struct.pack(">Q", VERSION))
        f.write(struct.pack(">Q", len(manifest)))
        f.write(struct.pack(">I", 0))          # metadata signature size (unsigned)
        f.write(manifest)
        f.write(blobs)

    total = os.path.getsize(outpath)
    for name, size, nb, dl in rows:
        print("  %-20s %10d B  %5d blk  %10d B %s" %
              (name, size, nb, dl, "xz" if use_xz else "raw"))
    print("payload: %s (%d partitions, %d bytes%s)" %
          (outpath, len(rows), total, ", xz" if use_xz else ""))


# ---- inspect -----------------------------------------------------------

def read_header(f):
    if f.read(4) != MAGIC:
        sys.exit("not a payload.bin (bad magic)")
    ver = struct.unpack(">Q", f.read(8))[0]
    manifest_size = struct.unpack(">Q", f.read(8))[0]
    sig_size = struct.unpack(">I", f.read(4))[0]
    manifest = f.read(manifest_size)
    return ver, manifest, sig_size


def info(path):
    with open(path, "rb") as f:
        ver, manifest, sig_size = read_header(f)
    bs, minor, parts = 4096, 0, []
    for field, wire, val in _fields(manifest):
        if field == 3:
            bs = val
        elif field == 12:
            minor = val
        elif field == 13:
            name, psize, nops, ptype = "?", 0, 0, "?"
            for ff, fw, fv in _fields(val):
                if ff == 1:
                    name = fv.decode(errors="replace")
                elif ff == 7:
                    for gf, gw, gv in _fields(fv):
                        if gf == 1:
                            psize = gv
                elif ff == 8:
                    nops += 1
                    for gf, gw, gv in _fields(fv):
                        if gf == 1:
                            ptype = {0: "REPLACE", 1: "REPLACE_BZ",
                                     8: "REPLACE_XZ"}.get(gv, str(gv))
            parts.append((name, psize, nops, ptype))
    print("version %d  block_size %d  minor_version %d  %ssigned  %d partitions"
          % (ver, bs, minor, "" if sig_size else "un", len(parts)))
    for name, psize, nops, ptype in parts:
        print("  %-24s %12d B  %d op(s) %s" % (name, psize, nops, ptype))


def main():
    ap = argparse.ArgumentParser(prog="fb_payload")
    sub = ap.add_subparsers(dest="cmd", required=True)
    pi = sub.add_parser("info")
    pi.add_argument("payload")
    pr = sub.add_parser("repack")
    pr.add_argument("-o", "--out", required=True)
    pr.add_argument("--block-size", type=int, default=4096)
    pr.add_argument("--xz", action="store_true")
    pr.add_argument("--from-dir")
    pr.add_argument("parts", nargs="*", help="name:image.img ...")
    a = ap.parse_args()

    if a.cmd == "info":
        info(a.payload)
        return

    parts = []
    if a.from_dir:
        for fn in sorted(os.listdir(a.from_dir)):
            if fn.endswith(".img"):
                parts.append((fn[:-4], os.path.join(a.from_dir, fn)))
    for p in a.parts:
        if ":" not in p:
            sys.exit("expected name:image, got %r" % p)
        name, path = p.split(":", 1)
        parts.append((name, path))
    if not parts:
        sys.exit("no partitions given")
    for _, path in parts:
        if not os.path.isfile(path):
            sys.exit("no such image: %s" % path)
    repack(a.out, parts, a.block_size, a.xz)


if __name__ == "__main__":
    main()
