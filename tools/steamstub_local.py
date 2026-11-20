#!/usr/bin/env python3
"""Prepare a local, reversible entry-point repair for an unencrypted SteamStub 3.1 x64 file.

Format details were checked against atom0s/Steamless:
https://github.com/atom0s/Steamless (CC BY-NC-ND 4.0; local use only).
"""

import argparse
import hashlib
import mmap
import os
from pathlib import Path
import shutil
import stat
import struct


def inspect(data, expected_app):
    def read(offset, size):
        if offset < 0 or size < 0 or offset + size > len(data):
            raise ValueError("Truncated or invalid executable")
        return data[offset:offset + size]

    def u16(offset): return struct.unpack("<H", read(offset, 2))[0]
    def u32(offset): return struct.unpack("<I", read(offset, 4))[0]
    def u64(offset): return struct.unpack("<Q", read(offset, 8))[0]

    if read(0, 2) != b"MZ":
        raise ValueError("Not a Windows executable")
    pe = u32(0x3c)
    if read(pe, 4) != b"PE\0\0" or u16(pe + 4) != 0x8664:
        raise ValueError("Only x64 PE files are supported")
    count, optional_size = u16(pe + 6), u16(pe + 20)
    optional = pe + 24
    if not 0 < count <= 96 or optional_size < 192 or u16(optional) != 0x20b:
        raise ValueError("Unsupported PE headers")
    read(optional, optional_size + 40 * count)
    if u32(optional + 108) <= 9 or u64(optional + 112 + 9 * 8) != 0:
        raise ValueError("Executables with TLS callbacks are not supported")
    entry = u32(optional + 16)
    image_base = u64(optional + 24)
    sections = []
    for index in range(count):
        section = optional + optional_size + 40 * index
        name = read(section, 8).split(b"\0", 1)[0]
        virtual_size, address, raw_size, raw_offset = struct.unpack("<IIII", read(section + 8, 16))
        flags = u32(section + 36)
        if raw_size and (raw_offset > len(data) or raw_size > len(data) - raw_offset):
            raise ValueError("Section extends beyond the executable")
        sections.append((name, address, virtual_size, raw_offset, raw_size, flags))

    def location(rva):
        owners = [s for s in sections if s[1] <= rva < s[1] + s[4]]
        if len(owners) != 1:
            raise ValueError("Entry point is not in one file-backed section")
        section = owners[0]
        return section, section[3] + rva - section[1]

    bind, wrapped = location(entry)
    if bind[0] != b".bind" or wrapped - bind[3] < 0xf0:
        raise ValueError("Expected a SteamStub entry point in .bind")
    if read(wrapped, 14) != bytes.fromhex("e800000000505351525657554150"):
        raise ValueError("Unrecognized SteamStub entry code")
    header = bytearray(read(wrapped - 0xf0, 0xf0))
    previous = struct.unpack_from("<I", header)[0]
    for offset in range(4, len(header), 4):
        value = struct.unpack_from("<I", header, offset)[0]
        struct.pack_into("<I", header, offset, value ^ previous)
        previous = value
    sig = struct.unpack_from("<I", header, 4)[0]
    stored_base, stored_entry = struct.unpack_from("<QQ", header, 8)
    original_entry = struct.unpack_from("<Q", header, 32)[0]
    app, flags = struct.unpack_from("<II", header, 56)
    if (sig != 0xc0dec0df or stored_base != image_base or stored_entry != entry
            or app != expected_app or not flags & 4 or original_entry > 0xffffffff):
        raise ValueError("Unsupported wrapper, app ID, or encrypted game code")
    code, code_offset = location(original_entry)
    if code[0] == b".bind" or not code[5] & 0x20000000 or read(code_offset, 16) == bytes(16):
        raise ValueError("Original entry point is not executable game code")
    return optional + 16, optional + 64, original_entry


def digest(path):
    with path.open("rb") as f:
        return hashlib.file_digest(f, "sha256").hexdigest()


def prepare(source, destination, appid):
    source, destination = Path(source), Path(destination)
    if source.is_symlink() or not source.is_file():
        raise ValueError("Source must be an existing regular file")
    with source.open("rb") as f:
        with mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ) as data:
            entry_offset, checksum_offset, entry = inspect(data, appid)
    source_hash = digest(source)
    created = False
    try:
        with source.open("rb") as src, destination.open("xb") as dst:
            created = True
            shutil.copyfileobj(src, dst, length=1024 * 1024)
            dst.flush()
            os.fsync(dst.fileno())
        if digest(destination) != source_hash or digest(source) != source_hash:
            raise ValueError("Source changed while copying; no repair was prepared")
        os.chmod(destination, stat.S_IMODE(source.stat().st_mode))
        with destination.open("r+b") as f:
            f.seek(entry_offset)
            f.write(struct.pack("<I", entry))
            f.seek(checksum_offset)
            f.write(bytes(4))
            f.flush()
            os.fsync(f.fileno())
        return {"original_sha256": source_hash, "prepared_sha256": digest(destination)}
    except Exception:
        if created:
            destination.unlink(missing_ok=True)
        raise


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--appid", type=int, required=True)
    args = parser.parse_args()
    if args.appid <= 0:
        parser.error("--appid must be positive")
    print(prepare(args.source, args.destination, args.appid))
