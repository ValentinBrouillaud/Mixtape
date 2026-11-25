"""Regression checks for codesign output and unsafe prepared entitlements."""
from __future__ import annotations

import plistlib
import unittest

from validate_widget_signing import APP_GROUP_KEY, HOST_BUNDLE_ID, WIDGET_BUNDLE_ID, entitlement_problems, metadata_problems, parse_codesign_entitlements, signature_details


class WidgetSigningTests(unittest.TestCase):
    def test_xml_stdout_with_diagnostics_on_stderr(self):
        expected = {APP_GROUP_KEY: ["group.com.example.mixtape"]}
        self.assertEqual(parse_codesign_entitlements(plistlib.dumps(expected), b"Executable=/tmp/Mixtape.app/Mixtape\n"), expected)

    def test_legacy_stderr_plist_is_not_hidden_by_warnings(self):
        expected = {APP_GROUP_KEY: ["group.com.example.mixtape"]}
        stderr = b"Executable=/tmp/Mixtape\nwarning: deprecated filename\n" + plistlib.dumps(expected) + b"\nother diagnostic\n"
        self.assertEqual(parse_codesign_entitlements(b"", stderr), expected)

    def test_no_entitlements_cannot_pass_group_validation(self):
        missing = parse_codesign_entitlements(b"", b"Executable=/tmp/Mixtape\n")
        self.assertTrue(entitlement_problems(missing, "group.com.example.mixtape"))

    def test_corrupt_or_conflicting_output_is_rejected(self):
        with self.assertRaises(ValueError):
            parse_codesign_entitlements(b"<plist><dict>", b"")
        with self.assertRaises(ValueError):
            parse_codesign_entitlements(plistlib.dumps({APP_GROUP_KEY: ["group.one"]}), plistlib.dumps({APP_GROUP_KEY: ["group.two"]}))
        with self.assertRaises(ValueError):
            parse_codesign_entitlements(b"<plist><dict><key>x</key></bad></plist>", b"")

    def test_wrong_group_or_unrelated_privileges_are_rejected(self):
        group = "group.com.example.mixtape"
        self.assertEqual(entitlement_problems({APP_GROUP_KEY: [group]}, group), [])
        self.assertTrue(entitlement_problems({APP_GROUP_KEY: ["group.another"]}, group))
        self.assertTrue(entitlement_problems({APP_GROUP_KEY: [group], "com.apple.security.cs.jit": True}, group))

    def test_ad_hoc_is_distinct_from_an_apple_identity(self):
        self.assertEqual(signature_details(b"", b"CodeDirectory v=20400 size=100 flags=0x2(adhoc)\nSignature=adhoc\n"), {"adHoc": True, "codeDirectoryVersion": 20400})
        self.assertFalse(signature_details(b"", b"CodeDirectory v=20500 size=100\nAuthority=Apple Development\n")["adHoc"])

    def test_bundle_version_mismatch_prevents_preparation(self):
        host = {"CFBundleIdentifier": HOST_BUNDLE_ID, "CFBundleVersion": "41", "CFBundleShortVersionString": "1.0.40", "MinimumOSVersion": "18.0"}
        widget = dict(host, CFBundleIdentifier=WIDGET_BUNDLE_ID, NSExtension={"NSExtensionPointIdentifier": "com.apple.widgetkit-extension"})
        self.assertEqual(metadata_problems(host, widget, "41"), [])
        widget["CFBundleVersion"] = "40"
        self.assertIn("Host/widget mismatch for CFBundleVersion", metadata_problems(host, widget, "41"))

    def test_binary_plist_output_can_be_read(self):
        expected = {APP_GROUP_KEY: ["group.com.example.mixtape"]}
        self.assertEqual(parse_codesign_entitlements(plistlib.dumps(expected, fmt=plistlib.FMT_BINARY), b""), expected)


if __name__ == "__main__":
    unittest.main()
