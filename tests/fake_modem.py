#!/usr/bin/env python3
# fake DIAG and AT modems on a pty, for testing qcdiag/atcmd without hardware
# usage: fake_modem.py diag|at   (prints the pty path, serves until killed)
import os, pty, struct, sys, tty

def crc16(data):
    c = 0xffff
    for b in data:
        c ^= b
        for _ in range(8):
            c = (c >> 1) ^ 0x8408 if c & 1 else c >> 1
    return c ^ 0xffff

def frame(p):
    p = p + struct.pack('<H', crc16(p))
    out = bytearray()
    for b in p:
        out += bytes([0x7d, b ^ 0x20]) if b in (0x7e, 0x7d) else bytes([b])
    return bytes(out) + b'\x7e'

def unframe(raw):
    out, esc = bytearray(), False
    for b in raw:
        if esc:
            out.append(b ^ 0x20); esc = False
        elif b == 0x7d:
            esc = True
        else:
            out.append(b)
    if len(out) < 3 or crc16(out[:-2]) != struct.unpack('<H', out[-2:])[0]:
        return None
    return bytes(out[:-2])

nv = {1877: bytes([0x7e, 0x7d, 0x01]) + bytes(125), 550: bytes([8, 0x3a]) + bytes(126)}
efs = {'/nv/item_files/modem/mmode/lte_bandpref': struct.pack('<Q', (1 << 0) | (1 << 2) | (1 << 6) | (1 << 19))}
fds, dirs = {}, {}

def efs_cmd(sub, p):
    hdr = struct.pack('<BBH', 0x4b, 0x13, sub)
    if sub == 0:
        return hdr + p
    if sub == 2:
        flags, mode = struct.unpack('<ii', p[:8]); path = p[8:].split(b'\0')[0].decode()
        if path not in efs and not flags & 0o100:
            return hdr + struct.pack('<ii', -1, 2)
        if flags & 0o1000 or path not in efs:
            efs[path] = b''
        fd = len(fds) + 3; fds[fd] = path
        return hdr + struct.pack('<ii', fd, 0)
    if sub == 4:
        fd, n, off = struct.unpack('<iII', p[:12]); d = efs[fds[fd]][off:off + n]
        return hdr + struct.pack('<iIii', fd, off, len(d), 0) + d
    if sub == 5:
        fd, off = struct.unpack('<iI', p[:8]); d = p[8:]; path = fds[fd]
        efs[path] = efs[path][:off] + d
        return hdr + struct.pack('<iIii', fd, off, len(d), 0)
    if sub == 3:
        return hdr + struct.pack('<i', 0)
    if sub == 11:
        path = p.split(b'\0')[0].decode().rstrip('/')
        ents = sorted(k[len(path) + 1:] for k in efs if k.startswith(path + '/'))
        d = len(dirs) + 1; dirs[d] = ents
        return hdr + struct.pack('<Ii', d, 0)
    if sub == 12:
        d, seq = struct.unpack('<ii', p[:8]); ents = dirs[d]
        if seq > len(ents):
            return hdr + struct.pack('<iiiiiiiii', d, seq, 0, 0, 0, 0, 0, 0, 0) + b'\0'
        name = ents[seq - 1]; size = 8
        return hdr + struct.pack('<iiiiiiiii', d, seq, 0, 0, 0o100644, size, 0, 0, 0) + name.encode() + b'\0'
    if sub == 13:
        return hdr + struct.pack('<i', 0)
    if sub == 15:
        path = p.split(b'\0')[0].decode()
        if path not in efs:
            return hdr + struct.pack('<i', 2) + bytes(24)
        return hdr + struct.pack('<iiiiiii', 0, 0o100644, len(efs[path]), 1, 0, 1700000000, 0)
    return bytes([0x13]) + hdr

def diag(p):
    c = p[0]
    if c == 0x7c:
        return struct.pack('<BBHII', 0x7c, 1, 0, 0x1234, 0x5678) + b'MPSS.FAKE.1.0\0SM8650\0'
    if c == 0x41:
        return bytes([0x41, 1 if p[1:7] == b'000000' else 0])
    if c in (0x26, 0x27):
        item = struct.unpack('<H', p[1:3])[0]
        if c == 0x27:
            nv[item] = p[3:131]; st = 0
        st = 0 if item in nv else 5
        data = nv.get(item, bytes(128))
        return bytes([c]) + p[1:3] + data + struct.pack('<H', st)
    if c == 0x4b and p[1] == 0x13:
        return efs_cmd(struct.unpack('<H', p[2:4])[0], p[4:])
    return bytes([0x13]) + p

def serve_diag(fd):
    buf = b''
    while True:
        buf += os.read(fd, 4096)
        while b'\x7e' in buf:
            raw, buf = buf.split(b'\x7e', 1)
            p = unframe(raw)
            if not p:
                continue
            out = frame(b'\x10\x00\x05\x00junk') + frame(diag(p))   # a log packet first
            for i in range(0, len(out), 7):                          # dribble it out
                os.write(fd, out[i:i + 7])

def serve_at(fd):
    buf = b''
    while True:
        buf += os.read(fd, 1024)
        while b'\r' in buf:
            line, buf = buf.split(b'\r', 1)
            cmd = line.decode().strip()
            os.write(fd, line + b'\r\n')               # echo
            if cmd.upper() == 'AT+CGMR':
                os.write(fd, b'\r\n+CGMR: FAKE_MODEM_V1\r\n\r\nOK\r\n')
            elif cmd.upper().startswith('AT+BAD'):
                os.write(fd, b'\r\n+CME ERROR: 4\r\n')
            elif cmd.upper() == 'AT+SLOW':
                pass
            else:
                os.write(fd, b'\r\nOK\r\n')

m, s = pty.openpty()
tty.setraw(m)
print(os.ttyname(s), flush=True)
(serve_diag if sys.argv[1] == 'diag' else serve_at)(m)
