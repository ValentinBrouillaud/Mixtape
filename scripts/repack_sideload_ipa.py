#!/usr/bin/env python3
"""Store bundle Info.plist entries without compression; preserve every signed byte."""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import zipfile


def stored_plist(name: str) -> bool:
    # Resource bundles are included too: signing tools may enumerate every plist.
    return name.endswith("/Info.plist")


def repack(source: Path, destination: Path) -> dict:
    if source.resolve() == destination.resolve():
        raise ValueError("Input and output IPA must differ")
    digests = {}
    plists = []
    with zipfile.ZipFile(source) as original, zipfile.ZipFile(destination, "w") as result:
        for entry in original.infolist():
            if entry.filename in digests:
                raise ValueError("Duplicate ZIP entry")
            updated = copy.copy(entry)
            if stored_plist(entry.filename):
                updated.compress_type = zipfile.ZIP_STORED
                plists.append(entry.filename)
            digest = hashlib.sha256()
            with original.open(entry) as input_stream, result.open(updated, "w") as output:
                while chunk := input_stream.read(1024 * 1024):
                    output.write(chunk)
                    digest.update(chunk)
            digests[entry.filename] = digest.hexdigest()
        result.comment = original.comment
    with zipfile.ZipFile(destination) as result:
        if len(result.infolist()) != len(digests):
            raise ValueError("Repacking changed the archive file count")
        for entry in result.infolist():
            with result.open(entry) as stream:
                digest = hashlib.file_digest(stream, "sha256").hexdigest()
            if digest != digests[entry.filename]:
                raise ValueError("Repacking changed signed file contents")
            if stored_plist(entry.filename) and entry.compress_type != zipfile.ZIP_STORED:
                raise ValueError("Info.plist must be stored uncompressed")
    return {"signedFileBytesPreserved": True, "fileCount": len(digests), "storedInfoPlists": plists}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    report = repack(args.source, args.destination)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("Verified unchanged signed file bytes and uncompressed Info.plist entries in the IPA.")


if __name__ == "__main__":
    main()
