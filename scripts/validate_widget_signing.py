#!/usr/bin/env python3
"""Prepare/inspect App Group signatures before the IPA is re-signed for iPhone.

The optional preparation step uses an ad-hoc identity only. The output still
requires an Apple-authorized signature and matching profiles at installation.
No provisioning profiles, accounts, certificates or team IDs are created here.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import platform
import plistlib
import re
import subprocess
import sys
import tempfile
from typing import Any
from xml.parsers.expat import ExpatError


APP_GROUP_KEY = "com.apple.security.application-groups"
HOST_BUNDLE_ID = "com.alexcding.mixtape"
WIDGET_BUNDLE_ID = HOST_BUNDLE_ID + ".widgets"


def parse_codesign_entitlements(stdout: bytes, stderr: bytes) -> dict[str, Any]:
    """Read plist output while allowing codesign diagnostics on either stream.

    Modern `--entitlements - --xml` writes the plist to stdout; older versions
    may write it to stderr with the Executable/deprecation messages around it.
    Never interpret missing/malformed output as permission to use a group.
    """
    parsed: list[dict[str, Any]] = []
    for stream in (stdout, stderr):
        candidate = stream if stream.startswith(b"bplist00") else stream.strip()
        if not candidate:
            continue
        if candidate.startswith(b"bplist00"):
            payload = candidate
        else:
            start = candidate.find(b"<?xml")
            if start < 0:
                start = candidate.find(b"<plist")
            if start < 0:
                continue
            end = candidate.find(b"</plist>", start)
            if end < 0:
                raise ValueError("codesign returned an incomplete entitlements plist")
            payload = candidate[start:end + len(b"</plist>")]
        try:
            result = plistlib.loads(payload)
        except (ValueError, ExpatError) as error:
            raise ValueError("codesign returned an unreadable entitlements plist") from error
        if not isinstance(result, dict):
            raise ValueError("codesign entitlements must be a dictionary")
        parsed.append(result)
    if not parsed:
        return {}
    if any(result != parsed[0] for result in parsed[1:]):
        raise ValueError("codesign returned conflicting entitlements on its output streams")
    return parsed[0]


def entitlement_problems(entitlements: dict[str, Any], group: str) -> list[str]:
    problems = []
    if entitlements.get(APP_GROUP_KEY) != [group]:
        problems.append("Signature must contain exactly the requested shared App Group")
    unexpected = sorted(set(entitlements) - {APP_GROUP_KEY})
    if unexpected:
        problems.append("Preparation must not claim unrelated entitlements: " + ", ".join(unexpected))
    return problems


def signature_details(stdout: bytes, stderr: bytes) -> dict[str, Any]:
    text = (stdout + b"\n" + stderr).decode("utf-8", errors="replace")
    version = re.search(r"(?m)^CodeDirectory v=(\d+)\b", text)
    identity = re.search(r"(?m)^Signature=(.+)$", text)
    return {
        "adHoc": bool(identity and identity.group(1).strip() == "adhoc"),
        "codeDirectoryVersion": int(version.group(1)) if version else None,
    }


def digest_choices(stdout: bytes, stderr: bytes) -> list[str]:
    text = (stdout + b"\n" + stderr).decode("utf-8", errors="replace")
    choices = re.search(r"(?m)^Hash choices=([^\r\n]+)", text)
    if choices:
        return [value.strip() for value in choices.group(1).split(",")]
    single = re.search(r"(?m)^Hash type=(\S+)", text)
    return [single.group(1)] if single else []


def run_codesign(arguments: list[str]) -> subprocess.CompletedProcess[bytes]:
    result = subprocess.run(
        ["/usr/bin/codesign", *arguments], capture_output=True,
        check=False, timeout=180,
    )
    if result.returncode and "--xml" in arguments:
        diagnostic = result.stderr.decode("utf-8", errors="replace").lower()
        if "unrecognized option" in diagnostic or "unknown option" in diagnostic:
            # Older codesign releases already emitted XML without this flag.
            # Retry only an unsupported flag, never a signature failure.
            return run_codesign([argument for argument in arguments if argument != "--xml"])
    if result.returncode:
        details = (result.stderr or result.stdout).decode("utf-8", errors="replace").strip()
        raise ValueError("codesign failed: " + details[-2000:])
    return result


def read_bundle(bundle: Path) -> dict[str, Any]:
    with (bundle / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    executable = info.get("CFBundleExecutable")
    if not isinstance(executable, str) or not executable or Path(executable).name != executable:
        raise ValueError(f"Invalid executable name in {bundle.name}")
    if not (bundle / executable).is_file():
        raise ValueError(f"Missing executable in {bundle.name}")
    return info


def metadata_problems(host: dict[str, Any], widget: dict[str, Any], expected_build: str | None) -> list[str]:
    problems = []
    if host.get("CFBundleIdentifier") != HOST_BUNDLE_ID:
        problems.append("Host bundle identifier changed")
    if widget.get("CFBundleIdentifier") != WIDGET_BUNDLE_ID:
        problems.append("Widget bundle identifier changed")
    for key in ("CFBundleVersion", "CFBundleShortVersionString", "MinimumOSVersion"):
        if host.get(key) != widget.get(key):
            problems.append(f"Host/widget mismatch for {key}")
    if expected_build is not None and str(host.get("CFBundleVersion")) != expected_build:
        problems.append("Unexpected app build number")
    if host.get("MinimumOSVersion") != "18.0":
        problems.append("App and widget must target iOS 18.0")
    if widget.get("NSExtension", {}).get("NSExtensionPointIdentifier") != "com.apple.widgetkit-extension":
        problems.append("Unexpected widget extension point")
    return problems


def checked_path(path: Path, root: Path) -> Path:
    resolved = path.resolve(strict=True)
    if resolved != root and root not in resolved.parents:
        raise ValueError(f"Embedded code escapes the application bundle: {path.name}")
    return resolved


def embedded_libraries(app: Path) -> list[Path]:
    """Sign dylibs and framework bundles inside-out, including debug dylibs."""
    frameworks = [checked_path(path, app) for path in app.rglob("*.framework") if path.is_dir()]
    framework_executables = {
        checked_path(framework / read_bundle(framework)["CFBundleExecutable"], app)
        for framework in frameworks
    }
    dylibs = {
        checked_path(path, app) for path in app.rglob("*.dylib") if path.is_file()
    } - framework_executables
    return sorted(set(frameworks) | dylibs, key=lambda path: (-len(path.parts), path.as_posix()))


def prepare(app: Path, widget: Path, group: str, libraries: list[Path]) -> None:
    # These are metadata-bearing preparation signatures, not distribution
    # signatures. Retain no legacy macOS/JIT/keychain entitlements in iOS.
    with tempfile.TemporaryDirectory(prefix="mixtape-widget-signing-") as temporary:
        entitlements = Path(temporary) / "shared-group.plist"
        entitlements.write_bytes(plistlib.dumps({APP_GROUP_KEY: [group]}))
        for library in libraries:
            run_codesign(["--force", "--sign", "-", "--timestamp=none", "--digest-algorithm=sha256", str(library)])
        for bundle in (widget, app):
            run_codesign([
                "--force", "--sign", "-", "--timestamp=none",
                "--digest-algorithm=sha256",
                "--generate-entitlement-der", "--entitlements", str(entitlements), str(bundle),
            ])


def inspect(app: Path, widget: Path, group: str, libraries: list[Path]) -> tuple[list[dict[str, Any]], list[str], list[dict[str, Any]]]:
    entries = []
    problems = []
    library_signatures = []
    for bundle in (app, widget):
        info = read_bundle(bundle)
        entry = {
            "bundle": "." if bundle == app else bundle.relative_to(app).as_posix(),
            "identifier": info["CFBundleIdentifier"],
            "version": info.get("CFBundleShortVersionString"),
            "build": info.get("CFBundleVersion"),
            "minimumIOS": info.get("MinimumOSVersion"),
        }
        entitlement_result = run_codesign(["--display", "--entitlements", "-", "--xml", str(bundle)])
        entitlements = parse_codesign_entitlements(entitlement_result.stdout, entitlement_result.stderr)
        entry["entitlements"] = entitlements
        problems.extend(f"{entry['bundle']}: {problem}" for problem in entitlement_problems(entitlements, group))
        signature = run_codesign(["--display", "--verbose=4", str(bundle)])
        entry.update(signature_details(signature.stdout, signature.stderr))
        entry["hashAlgorithms"] = digest_choices(signature.stdout, signature.stderr)
        if entry["hashAlgorithms"] != ["sha256"]:
            problems.append(f"{entry['bundle']}: Expected SHA-256-only preparation signatures")
        if not entry["adHoc"]:
            problems.append(f"{entry['bundle']}: Expected a temporary ad-hoc signature")
        if (entry["codeDirectoryVersion"] or 0) < 20400:
            problems.append(f"{entry['bundle']}: Expected a current code signature format")
        entries.append(entry)
    # Verification is deliberately separate from signing. --deep validates the
    # already signed children; it is never used to apply one entitlement set to
    # frameworks, dylibs and extensions indiscriminately.
    run_codesign(["--verify", "--deep", "--strict", "--verbose=2", str(app)])
    for library in libraries:
        result = run_codesign(["--display", "--entitlements", "-", "--xml", str(library)])
        if parse_codesign_entitlements(result.stdout, result.stderr):
            problems.append(f"{library.relative_to(app).as_posix()}: Libraries must not claim entitlements")
        details = run_codesign(["--display", "--verbose=4", str(library)])
        hashes = digest_choices(details.stdout, details.stderr)
        if hashes != ["sha256"]:
            problems.append(f"{library.relative_to(app).as_posix()}: Expected SHA-256-only library signatures")
        library_signatures.append({"binary": library.relative_to(app).as_posix(), "hashAlgorithms": hashes})
    return entries, problems, library_signatures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--group", required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--expected-build")
    parser.add_argument("--prepare", action="store_true", help="Apply ad-hoc preparation signatures before validation")
    args = parser.parse_args()
    report: dict[str, Any] = {
        "mode": "ad-hoc-for-resigning",
        "installableOnIPhone": False,
        "requiresAppleResigningAndProvisioning": True,
        "appGroup": args.group,
        "bundles": [],
        "embeddedLibraries": [],
        "librarySignatures": [],
        "problems": [],
    }
    try:
        if platform.system() != "Darwin":
            raise ValueError("This signature preparation/validation requires macOS codesign")
        if not re.fullmatch(r"group\.[A-Za-z0-9][A-Za-z0-9.-]+", args.group):
            raise ValueError("An explicit group. identifier is required")
        app = args.app.resolve(strict=True)
        if not app.is_dir() or app.suffix != ".app":
            raise ValueError("Expected a built iOS .app bundle")
        widget = checked_path(app / "PlugIns" / "MixtapeWidgets.appex", app)
        extensions = {checked_path(path, app) for path in app.rglob("*.appex")}
        if extensions != {widget}:
            raise ValueError("Unexpected extensions in the v40 application")
        host_info, widget_info = read_bundle(app), read_bundle(widget)
        for bundle, info in ((app, host_info), (widget, widget_info)):
            checked_path(bundle / info["CFBundleExecutable"], app)
        report["problems"].extend(metadata_problems(host_info, widget_info, args.expected_build))
        if report["problems"]:
            raise ValueError("Bundle metadata validation failed before signature preparation")
        if any((bundle / "embedded.mobileprovision").exists() for bundle in (app, widget)):
            raise ValueError("Expected an unprovisioned CI build; refusing to replace an Apple-provisioned signature")
        libraries = embedded_libraries(app)
        report["embeddedLibraries"] = [path.relative_to(app).as_posix() for path in libraries]
        if args.prepare:
            prepare(app, widget, args.group, libraries)
        entries, problems, library_signatures = inspect(app, widget, args.group, libraries)
        report["bundles"] = entries
        report["librarySignatures"] = library_signatures
        report["problems"].extend(problems)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        report["problems"].append(str(error))
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    if report["problems"]:
        print("\n".join(report["problems"]), file=sys.stderr)
        return 1
    print("Verified shared App Group in app/widget ad-hoc signatures; Apple re-signing and provisioning remain required.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
