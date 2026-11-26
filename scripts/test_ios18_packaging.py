"""Check safe architecture selection and byte-preserving ZIP normalization."""
import hashlib
from pathlib import Path
import stat
import struct
import tempfile
import unittest
import zipfile

from prepare_ios18_frameworks import ARM64, arm64_range
from repack_sideload_ipa import repack


def thin_header(cpu=ARM64, subtype=0):
    return struct.pack("<IIIIIIII", 0xFEEDFACF, cpu, subtype, 6, 0, 0, 0, 0)


class ArchitectureTests(unittest.TestCase):
    def test_selects_original_arm64_payload_from_legacy_universal_framework(self):
        header = struct.pack(">II", 0xCAFEBABE, 3)
        for record in [(12, 9, 128, 64, 0), (12, 11, 192, 64, 0), (ARM64, 0, 256, 64, 0)]:
            header += struct.pack(">IIIII", *record)
        self.assertEqual(arm64_range(header, 320), (256, 64))

    def test_thin_generic_arm64_needs_no_change(self):
        self.assertEqual(arm64_range(thin_header(), 100), (0, 100))
        with self.assertRaises(ValueError):
            arm64_range(thin_header(subtype=2), 100)

    def test_rejects_corrupt_or_ambiguous_fat_records(self):
        records = [
            [(ARM64, 0, 100, 100, 0)],
            [(ARM64, 0, 8, 32, 0)],
            [(12, 9, 100, 32, 0)],
            [(ARM64, 0, 100, 32, 0), (ARM64, 0, 132, 32, 0)],
            [(12, 9, 80, 40, 0), (ARM64, 0, 100, 32, 0)],
        ]
        for entries in records:
            header = struct.pack(">II", 0xCAFEBABE, len(entries))
            header += b"".join(struct.pack(">IIIII", *r) for r in entries)
            with self.assertRaises(ValueError):
                arm64_range(header, 180)

    def test_fat64_can_be_selected_without_truncating_offsets(self):
        header = struct.pack(">II", 0xCAFEBABF, 1)
        header += struct.pack(">IIQQII", ARM64, 0, 2**32, 100, 0, 0)
        self.assertEqual(arm64_range(header, 2**32 + 100), (2**32, 100))


class ArchiveTests(unittest.TestCase):
    def test_repack_preserves_signed_bytes_modes_and_symlink_contents(self):
        with tempfile.TemporaryDirectory() as temporary:
            source, destination = Path(temporary) / "input.ipa", Path(temporary) / "output.ipa"
            entries = {
                "Payload/Mixtape.app/Info.plist": b"main plist" * 100,
                "Payload/Mixtape.app/Frameworks/VLC.framework/Info.plist": b"framework plist" * 100,
                "Payload/Mixtape.app/PlugIns/Widget.appex/Info.plist": b"widget plist" * 100,
                "Payload/Mixtape.app/Mixtape": b"signed executable" * 1000,
                "Payload/Mixtape.app/_CodeSignature/CodeResources": b"signed resources" * 100,
                "Payload/Mixtape.app/link": b"Mixtape",
            }
            with zipfile.ZipFile(source, "w") as z:
                for name, data in entries.items():
                    info = zipfile.ZipInfo(name)
                    info.create_system = 3
                    info.compress_type = zipfile.ZIP_DEFLATED
                    info.external_attr = ((stat.S_IFLNK | 0o777) if name.endswith("/link") else (stat.S_IFREG | 0o755)) << 16
                    z.writestr(info, data)
            report = repack(source, destination)
            self.assertTrue(report["signedFileBytesPreserved"])
            self.assertEqual(len(report["storedInfoPlists"]), 3)
            with zipfile.ZipFile(source) as original, zipfile.ZipFile(destination) as result:
                for name, data in entries.items():
                    self.assertEqual(hashlib.sha256(result.read(name)).digest(), hashlib.sha256(data).digest())
                    self.assertEqual(result.getinfo(name).external_attr, original.getinfo(name).external_attr)
                    if name.endswith("/Info.plist"):
                        self.assertEqual(result.getinfo(name).compress_type, zipfile.ZIP_STORED)
                    else:
                        self.assertEqual(result.getinfo(name).compress_type, original.getinfo(name).compress_type)

    def test_in_place_repack_is_rejected_before_overwriting_input(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "app.ipa"
            source.write_bytes(b"original")
            with self.assertRaises(ValueError):
                repack(source, source)
            self.assertEqual(source.read_bytes(), b"original")


if __name__ == "__main__":
    unittest.main()
