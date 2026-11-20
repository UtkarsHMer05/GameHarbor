#!/usr/bin/env python3
"""Prepare a local Sekiro repair using the Steamless 3.1 format; do not distribute.

Format reference: https://github.com/atom0s/Steamless (CC BY-NC-ND 4.0).
"""
import hashlib
import os
from pathlib import Path
import struct
import subprocess
import sys


def prepare(src, dst):
    data = bytearray(src.read_bytes())
    u16 = lambda p: struct.unpack_from('<H', data, p)[0]
    u32 = lambda p: struct.unpack_from('<I', data, p)[0]
    u64 = lambda p: struct.unpack_from('<Q', data, p)[0]
    if data[:2] != b'MZ': raise ValueError('Not a PE file')
    pe = u32(60)
    if data[pe:pe+4] != b'PE\0\0' or u16(pe+4) != 0x8664: raise ValueError('Not x64 PE')
    count, size, opt = u16(pe+6), u16(pe+20), pe+24
    if count < 1 or count > 96 or size < 192 or u16(opt) != 0x20b: raise ValueError('Invalid headers')
    entry, base = u32(opt+16), u64(opt+24)
    sections = []
    for i in range(count):
        p = opt+size+i*40
        name = bytes(data[p:p+8]).split(b'\0')[0]
        vs, va, rs, raw = struct.unpack_from('<IIII', data, p+8)
        if raw+rs > len(data): raise ValueError('Truncated section')
        sections.append((name, va, rs, raw, u32(p+36)))
    def locate(rva):
        found = [s for s in sections if s[1] <= rva < s[1]+s[2]]
        if len(found) != 1: raise ValueError('Invalid RVA')
        s=found[0]
        return s, s[3]+rva-s[1]
    bind, at = locate(entry)
    if bind[0] != b'.bind' or at-bind[3] < 240 or data[at:at+14] != bytes.fromhex('e800000000505351525657554150'):
        raise ValueError('Unsupported wrapper')
    tls, tls_size = struct.unpack_from('<II', data, opt+184)
    if tls:
        _, tls_at = locate(tls)
        if tls_size < 40: raise ValueError('Invalid TLS')
        callbacks = u64(tls_at+24)
        if callbacks:
            _, cb_at = locate(callbacks-base)
            if u64(cb_at) != 0: raise ValueError('TLS callbacks require further analysis')
    h = bytearray(data[at-240:at]); prev=struct.unpack_from('<I',h)[0]
    for i in range(4,240,4):
        val=struct.unpack_from('<I',h,i)[0]; struct.pack_into('<I',h,i,val^prev); prev=val
    if (struct.unpack_from('<I',h,4)[0] != 0xc0dec0df or
        struct.unpack_from('<Q',h,8)[0] != base or struct.unpack_from('<Q',h,16)[0] != entry or
        struct.unpack_from('<I',h,56)[0] != 814380 or struct.unpack_from('<I',h,60)[0] & 4):
        raise ValueError('Unexpected SteamStub header')
    original = struct.unpack_from('<Q',h,32)[0]
    code_rva, code_len = struct.unpack_from('<QQ',h,72)
    code, code_at = locate(code_rva)
    if code_rva != code[1] or code_len != code[2] or code_len % 16 or not code[4] & 0x20000000:
        raise ValueError('Unexpected encrypted section')
    owner, _ = locate(original)
    if owner != code: raise ValueError('Unexpected original entry')
    key, iv, stolen = bytes(h[88:120]), bytes(h[120:136]), bytes(h[136:152])
    def crypt(args, payload):
        return subprocess.run(['/usr/bin/openssl','enc',*args,'-K',key.hex(),'-nopad'],input=payload,stdout=subprocess.PIPE,stderr=subprocess.PIPE,check=True).stdout
    rebuilt_iv=crypt(['-aes-256-ecb','-d'],iv)
    decrypted=crypt(['-aes-256-cbc','-d','-iv',rebuilt_iv.hex()],stolen+bytes(data[code_at:code_at+code_len]))
    if len(decrypted) != code_len+16: raise ValueError('Unexpected decrypted length')
    data[code_at:code_at+code_len]=decrypted[:code_len]
    struct.pack_into('<I',data,opt+16,original); struct.pack_into('<I',data,opt+64,0)
    with dst.open('xb') as f:
        f.write(data); f.flush(); os.fsync(f.fileno())
    os.chmod(dst,src.stat().st_mode & 0o777)
    print('Prepared SHA256:',hashlib.sha256(data).hexdigest())


if __name__ == '__main__':
    prepare(Path(sys.argv[1]),Path(sys.argv[2]))
