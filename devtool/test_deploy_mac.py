"""Signing gates: no installer is reported ready without notarization and a valid ticket."""
import argparse
import importlib.util
from pathlib import Path
from types import SimpleNamespace
import unittest
import tempfile
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("deploy_mac_tests", Path(__file__).with_name("deploy.py"))
deploy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deploy)


class MacSigningTests(unittest.TestCase):
    def test_bundles_all_three_notices_with_exact_content(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            build = root / "build"
            dependency = build / "SourcePackages/checkouts/SwiftWhisper"
            (dependency / "whisper.cpp").mkdir(parents=True)
            source_texts = {
                root / "LICENSE": "MIT License\nProject copyright\n",
                dependency / "LICENSE": "MIT License\nSwiftWhisper copyright\n",
                dependency / "whisper.cpp/LICENSE": "MIT License\nwhisper.cpp copyright\n",
            }
            for source, content in source_texts.items(): source.write_text(content)
            app = root / "MarsinDictation.app"
            with patch.object(deploy, "ROOT", root):
                self.assertTrue(deploy.bundle_mac_license_notices(app, build))
            notices = app / "Contents/Resources/Licenses"
            self.assertEqual(set(p.name for p in notices.iterdir()),
                {"MarsinDictation-MIT.txt", "SwiftWhisper-MIT.txt", "whisper.cpp-MIT.txt"})
            self.assertEqual(set(p.read_text() for p in notices.iterdir()), set(source_texts.values()))

    def test_missing_dependency_notice_fails_without_staging_partial_notices(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "LICENSE").write_text("MIT License\nProject copyright\n")
            app = root / "MarsinDictation.app"
            with patch.object(deploy, "ROOT", root):
                self.assertFalse(deploy.bundle_mac_license_notices(app, root / "build"))
            self.assertFalse(app.exists(), "Missing notices must stop packaging before app mutation/signing")

    def test_missing_release_credentials_fails_before_build(self):
        args = argparse.Namespace(install=False, package=True, local_sign=False, clean=False,
                                  verbose=False, dry_run=False)
        with patch.dict(deploy.os.environ, {}, clear=True), patch.object(deploy, "run_step") as step:
            self.assertEqual(1, deploy.deploy_mac(args))
            step.assert_not_called()

    def test_rejected_or_failed_submission_never_staples(self):
        for result in [SimpleNamespace(returncode=0, stdout='{"status":"Invalid","id":"test"}'),
                       SimpleNamespace(returncode=1, stdout='{"status":"Accepted"}'),
                       SimpleNamespace(returncode=0, stdout='not json')]:
            with patch.object(deploy.subprocess, "run", return_value=result), patch.object(deploy, "run_step") as step:
                self.assertFalse(deploy.notarize_mac_artifact("test.dmg", "test@example.com", "fake", "TEAM"))
                step.assert_not_called()

    def test_accepted_submission_requires_staple_and_validation(self):
        result = SimpleNamespace(returncode=0, stdout='{"status":"Accepted","id":"test"}')
        for outcomes, expected, calls in [([True, True], True, 2), ([False], False, 1), ([True, False], False, 2)]:
            with patch.object(deploy.subprocess, "run", return_value=result), patch.object(deploy, "run_step", side_effect=outcomes) as step:
                self.assertEqual(expected, deploy.notarize_mac_artifact("test.dmg", "test@example.com", "fake", "TEAM"))
                self.assertEqual(calls, step.call_count)


if __name__ == "__main__":
    unittest.main()
