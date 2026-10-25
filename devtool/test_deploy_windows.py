"""Windows package/install orchestration tests; no real process or installed files change."""
import argparse
import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("deploy", Path(__file__).with_name("deploy.py"))
deploy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deploy)


class WindowsPackageTests(unittest.TestCase):
    def test_package_runs_offline_tests_without_stopping_installed_app(self):
        args = argparse.Namespace(release=False, verbose=False, dry_run=True,
                                  run=False, build=False, test=False, install=False, package=True)
        with patch.object(deploy, "kill_existing") as stop, \
                patch.object(deploy, "run_step", return_value=True) as step, \
                patch.object(deploy, "do_build", return_value=True), \
                patch.object(deploy, "do_install", return_value=0), \
                patch.object(deploy, "print_summary", return_value=0):
            self.assertEqual(0, deploy.deploy_windows(args))
        stop.assert_not_called()
        self.assertIn(deploy.DEFAULT_TEST_FILTER, step.call_args_list[-1].args[1])

    def test_installer_uses_app_version_and_reports_launch_failure(self):
        # Isolated build tree; mocks prevent publish, compiler and UAC execution.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            project = root / "windows" / deploy.APP_PROJECT
            project.mkdir(parents=True)
            (project / f"{deploy.APP_PROJECT}.csproj").write_text(
                "<Project><PropertyGroup><Version>1.2.3</Version></PropertyGroup></Project>")
            (root / "tmp").mkdir()
            (root / "tmp" / "ggml-large-v3-turbo-q5_0.bin").touch()
            with patch.object(deploy, "ROOT", root), \
                    patch.object(deploy, "WINDOWS_DIR", root / "windows"), \
                    patch.dict(deploy.os.environ, {"ISCC_PATH": "fake-iscc.exe"}), \
                    patch.object(deploy.subprocess, "run") as run:
                run.return_value.returncode = 1
                self.assertEqual(1, deploy.do_install(package_only=False))
                iss = (root / "tmp" / "MarsinDictation.iss").read_text(encoding="utf-8")
                self.assertIn("AppVersion=1.2.3", iss)
                self.assertIn("RestartApplications=no", iss)
                self.assertNotIn("[Run]", iss)
                command = run.call_args.args[0][-1]
                self.assertIn("$ErrorActionPreference = 'Stop'", command)
                self.assertIn("catch { Write-Error $_ -ErrorAction Continue; exit 1 }", command)
                self.assertIn("exit $p.ExitCode", command)
                self.assertEqual(3, run.call_count)  # publish, compile, installer only


if __name__ == "__main__":
    unittest.main()
