import hashlib
import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("steamstub_local", Path(__file__).with_name("steamstub_local.py"))
steamstub_local = importlib.util.module_from_spec(spec)
spec.loader.exec_module(steamstub_local)


def fixture(flags=6):
    data = bytearray(0xe00)
    data[:2] = b"MZ"
    struct.pack_into("<I", data, 0x3c, 0x80)
    data[0x80:0x84] = b"PE\0\0"
    struct.pack_into("<HH", data, 0x84, 0x8664, 2)
    struct.pack_into("<H", data, 0x94, 0xf0)
    opt = 0x98
    struct.pack_into("<H", data, opt, 0x20b)
    struct.pack_into("<I", data, opt + 16, 0x2310)
    struct.pack_into("<Q", data, opt + 24, 0x140000000)
    struct.pack_into("<I", data, opt + 64, 0x12345678)
    struct.pack_into("<I", data, opt + 108, 16)
    section = opt + 0xf0
    data[section:section + 8] = b".text\0\0\0"
    struct.pack_into("<IIII", data, section + 8, 0x200, 0x1000, 0x200, 0x400)
    struct.pack_into("<I", data, section + 36, 0x60000020)
    section += 40
    data[section:section + 8] = b".bind\0\0\0"
    struct.pack_into("<IIII", data, section + 8, 0x800, 0x2000, 0x800, 0x600)
    struct.pack_into("<I", data, section + 36, 0x60000020)
    data[0x420:0x430] = b"\x90" * 16
    header = bytearray(0xf0)
    struct.pack_into("<I", header, 4, 0xc0dec0df)
    struct.pack_into("<QQ", header, 8, 0x140000000, 0x2310)
    struct.pack_into("<Q", header, 32, 0x1020)
    struct.pack_into("<II", header, 56, 374320, flags)
    previous = 0x12345678
    struct.pack_into("<I", header, 0, previous)
    for offset in range(4, len(header), 4):
        value = struct.unpack_from("<I", header, offset)[0] ^ previous
        struct.pack_into("<I", header, offset, value)
        previous = value
    data[0x820:0x910] = header
    data[0x910:0x91e] = bytes.fromhex("e800000000505351525657554150")
    return data


class LocalSteamStubTests(unittest.TestCase):
    def test_prepares_only_the_entry_and_checksum(self):
        with tempfile.TemporaryDirectory() as tmp:
            src, dst = Path(tmp) / "game.exe", Path(tmp) / "prepared.exe"
            original = fixture()
            src.write_bytes(original)
            report = steamstub_local.prepare(src, dst, 374320)
            result = dst.read_bytes()
            self.assertEqual(src.read_bytes(), original)
            self.assertEqual(report["original_sha256"], hashlib.sha256(original).hexdigest())
            self.assertEqual(struct.unpack_from("<I", result, 0x98 + 16)[0], 0x1020)
            self.assertEqual(struct.unpack_from("<I", result, 0x98 + 64)[0], 0)
            expected = bytearray(original)
            struct.pack_into("<I", expected, 0x98 + 16, 0x1020)
            struct.pack_into("<I", expected, 0x98 + 64, 0)
            self.assertEqual(result, expected)

    def test_rejects_bad_input_and_preserves_existing_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            src, dst = Path(tmp) / "game.exe", Path(tmp) / "prepared.exe"
            src.write_bytes(fixture())
            with self.assertRaises(ValueError):
                steamstub_local.prepare(src, dst, 1)
            self.assertFalse(dst.exists())
            src.write_bytes(fixture(flags=2))
            with self.assertRaises(ValueError):
                steamstub_local.prepare(src, dst, 374320)
            self.assertFalse(dst.exists())
            altered = fixture()
            altered[0x98 + 112 + 9 * 8] = 1
            src.write_bytes(altered)
            with self.assertRaises(ValueError):
                steamstub_local.prepare(src, dst, 374320)
            self.assertFalse(dst.exists())
            src.write_bytes(fixture())
            dst.write_bytes(b"keep")
            with self.assertRaises(FileExistsError):
                steamstub_local.prepare(src, dst, 374320)
            self.assertEqual(dst.read_bytes(), b"keep")


if __name__ == "__main__":
    unittest.main()
