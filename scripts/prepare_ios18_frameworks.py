#!/usr/bin/env python3
"""Keep the original generic arm64 code before preparing iOS 18 signatures."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import platform
import struct
import subprocess
import sys
import tempfile

from validate_widget_signing import checked_path, read_bundle


ARM64 = 0x0100000C


def arm64_range(header: bytes, file_size: int) -> tuple[int, int]:
    """Locate a single generic arm64 slice; never interpret CPU subtype arm64e as arm64."""
    if len(header) < 8:
        raise ValueError("Truncated Mach-O header")
    if header[:4] == bytes.fromhex("cffaedfe"):
        if len(header) < 32 or struct.unpack_from("<II", header, 4) != (ARM64, 0):
            raise ValueError("Expected generic arm64 code")
        return 0, file_size
    formats = {
        bytes.fromhex("cafebabe"): (">", False),
        bytes.fromhex("bebafeca"): ("<", False),
        bytes.fromhex("cafebabf"): (">", True),
        bytes.fromhex("bfbafeca"): ("<", True),
    }
    if header[:4] not in formats:
        raise ValueError("Unsupported Mach-O container")
    endian, fat64 = formats[header[:4]]
    count = struct.unpack_from(endian + "I", header, 4)[0]
    stride = 32 if fat64 else 20
    table_end = 8 + count * stride
    if not 1 <= count <= 32 or table_end > len(header):
        raise ValueError("Invalid universal architecture table")
    matches = []
    ranges = []
    for index in range(count):
        record = struct.unpack_from(endian + ("IIQQII" if fat64 else "IIIII"), header, 8 + index * stride)
        cpu, subtype, offset, size = record[:4]
        if offset < table_end or size < 32 or offset + size > file_size:
            raise ValueError("Architecture lies outside its binary")
        if any(offset < end and start < offset + size for start, end in ranges):
            raise ValueError("Overlapping architecture slices")
        ranges.append((offset, offset + size))
        if cpu == ARM64 and subtype == 0:
            matches.append((offset, size))
    if len(matches) != 1:
        raise ValueError("Expected exactly one generic arm64 architecture")
    return matches[0]


def slice_digest(path: Path, offset: int, size: int) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        stream.seek(offset)
        remaining = size
        while remaining:
            chunk = stream.read(min(1024 * 1024, remaining))
            if not chunk:
                raise ValueError("Incomplete arm64 payload")
            digest.update(chunk)
            remaining -= len(chunk)
    return digest.hexdigest()


def normalize(binary: Path) -> dict:
    size = binary.stat().st_size
    with binary.open("rb") as stream:
        offset, length = arm64_range(stream.read(2048), size)
    original = slice_digest(binary, offset, length)
    if offset != 0:
        with tempfile.TemporaryDirectory(prefix="mixtape-arm64-", dir=binary.parent) as temporary:
            target = Path(temporary) / binary.name
            subprocess.run(["xcrun", "lipo", str(binary), "-thin", "arm64", "-output", str(target)], check=True, capture_output=True, timeout=120)
            if target.stat().st_size != length or slice_digest(target, 0, length) != original:
                raise ValueError("Thinning changed the original arm64 payload")
            target.chmod(binary.stat().st_mode)
            target.replace(binary)
    architectures = subprocess.run(["xcrun", "lipo", "-archs", str(binary)], check=True, text=True, capture_output=True, timeout=30).stdout.split()
    if architectures != ["arm64"]:
        raise ValueError("The prepared framework must contain arm64 only")
    return {"inputBytes": size, "outputBytes": binary.stat().st_size, "removedArchitectures": offset != 0,
            "architectures": architectures, "originalArm64SHA256": original, "arm64PayloadPreserved": True}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    report = {"frameworks": [], "problems": []}
    try:
        if platform.system() != "Darwin":
            raise ValueError("Framework preparation requires macOS lipo")
        app = args.app.resolve(strict=True)
        if app.suffix != ".app" or not app.is_dir() or (app / "embedded.mobileprovision").exists():
            raise ValueError("Expected an unprovisioned CI application bundle")
        for framework in sorted(app.rglob("*.framework")):
            framework = checked_path(framework, app)
            binary = checked_path(framework / read_bundle(framework)["CFBundleExecutable"], app)
            entry = {"binary": binary.relative_to(app).as_posix(), **normalize(binary)}
            report["frameworks"].append(entry)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        report["problems"].append(str(error))
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    if report["problems"]:
        print("\n".join(report["problems"]), file=sys.stderr)
        return 1
    print("Prepared arm64-only frameworks, preserving their original arm64 code before signing.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
