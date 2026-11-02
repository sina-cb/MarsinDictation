"""Exercise local build preflight without invoking Xcode, signing, or touching user config."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

class LocalMacBuildPreflightTests(unittest.TestCase):
    def check_config(self, existing):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "devtool").mkdir(); (root / "mac").mkdir(); (root / "bin").mkdir()
            script = root / "devtool/build_mac_local.sh"
            shutil.copyfile(Path(__file__).with_name("build_mac_local.sh"), script)
            config = root / "mac/Local.xcconfig"
            if existing is not None: config.write_text(existing)
            generator = root / "bin/xcodegen"
            generator.write_text('#!/bin/sh\ntest -f mac/Local.xcconfig || exit 91\n')
            generator.chmod(0o755)
            builder = root / "bin/xcodebuild"
            builder.write_text('#!/bin/sh\nexit 17\n'); builder.chmod(0o755)
            result = subprocess.run(["sh", str(script)], env={**os.environ,
                "XCODEGEN": str(generator), "PATH": str(root / "bin") + ":" + os.environ["PATH"]})
            self.assertEqual(result.returncode, 17, "Build preflight must reach stub Xcode after config resolution")
            self.assertTrue(config.exists())
            if existing is not None: self.assertEqual(config.read_text(), existing)
    def test_clean_checkout_creates_empty_local_config(self): self.check_config(None)
    def test_existing_personal_config_is_preserved(self): self.check_config("// personal config must remain unchanged\n")

if __name__ == "__main__": unittest.main()
