"""Signing gates: no installer is reported ready without notarization and a valid ticket."""
import argparse
import importlib.util
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("deploy_mac_tests", Path(__file__).with_name("deploy.py"))
deploy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deploy)


class MacSigningTests(unittest.TestCase):
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
