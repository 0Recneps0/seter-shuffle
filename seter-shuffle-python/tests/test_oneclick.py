"""Tests for install-or-update.sh (one-click v3.0 install or update).

Runs the script in test mode (SETER_TEST_MODE=1) with override
directories, so no real install, launchd job, or Music playlist is
ever touched. The macOS-only checks and the python check are
skipped in test mode by the script itself, exactly as setup and
migrate do; what is tested here is the orchestration logic:
fresh install, update from a 3.0-proposed install, a declined
confirmation changing nothing, a failed install leaving the
v2.6 plist untouched, and rollback after a successful run.
"""

from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run_oneclick(args, env_extra, stdin=""):
    env = dict(os.environ)
    env["SETER_TEST_MODE"] = "1"
    env.update(env_extra)
    return subprocess.run(
        ["bash", str(ROOT / "install-or-update.sh"), *args],
        input=stdin,
        capture_output=True,
        text=True,
        env=env,
        timeout=60,
    )


class OneClickTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.install = self.base / "install"
        self.agents = self.base / "agents"
        self.state = self.base / "state"
        self.agents.mkdir()
        self.state.mkdir()
        self.env = {
            "SETER_PYTHON_INSTALL_DIR": str(self.install),
            "SETER_LAUNCHAGENTS_DIR": str(self.agents),
            "SETER_STATE_DIR": str(self.state),
        }
        self.old_plist = self.agents / "com.seter.daily.plist"
        self.new_plist = self.agents / "com.seter.python.daily.plist"

    def tearDown(self):
        self.tmp.cleanup()

    def test_fresh_install_migrates_v26(self):
        self.old_plist.write_text("<plist>old</plist>", encoding="utf-8")
        result = run_oneclick(["--yes"], self.env)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.install / "installed-version.txt").read_text().strip(), "3.0.4")
        self.assertTrue(self.new_plist.exists())
        self.assertFalse(self.old_plist.exists())
        disabled = list(self.agents.glob("com.seter.daily.plist.disabled-*"))
        self.assertEqual(len(disabled), 1)
        self.assertIn("8:00 AM", result.stdout)

    def test_update_from_proposed_keeps_bak_and_skips_migration(self):
        # Pre-existing 3.0-proposed install, v2.6 already disabled.
        self.install.mkdir(parents=True)
        (self.install / "installed-version.txt").write_text("3.0-proposed\n", encoding="utf-8")
        (self.install / "run.sh").write_text("# old run.sh\n", encoding="utf-8")
        (self.agents / "com.seter.daily.plist.disabled-20261029-000000").write_text(
            "<plist>old</plist>", encoding="utf-8"
        )
        result = run_oneclick(["--yes", "--force"], self.env)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.install / "installed-version.txt").read_text().strip(), "3.0.4")
        self.assertTrue(self.new_plist.exists())
        # The differing old run.sh must have been kept as a .bak.
        self.assertTrue(any(p.name.startswith("run.sh.bak-") for p in self.install.iterdir()))
        self.assertIn("Skipping migration", result.stdout)

    def test_declined_confirmation_changes_nothing(self):
        self.old_plist.write_text("<plist>old</plist>", encoding="utf-8")
        result = run_oneclick([], self.env, stdin="no\n")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.install.exists())
        self.assertFalse(self.new_plist.exists())
        self.assertTrue(self.old_plist.exists())

    def test_failed_install_leaves_v26_untouched(self):
        # Install directory path is a file, so setup cannot mkdir it.
        self.install.write_text("not a directory", encoding="utf-8")
        self.old_plist.write_text("<plist>old</plist>", encoding="utf-8")
        result = run_oneclick(["--yes"], self.env)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.old_plist.exists())
        self.assertFalse(self.new_plist.exists())

    def test_rollback_after_oneclick(self):
        self.old_plist.write_text("<plist>old</plist>", encoding="utf-8")
        result = run_oneclick(["--yes"], self.env)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.old_plist.exists())
        env = dict(os.environ)
        env["SETER_TEST_MODE"] = "1"
        env.update(self.env)
        rollback = subprocess.run(
            ["bash", str(self.install / "migrate-to-python.sh"), "--rollback"],
            capture_output=True,
            text=True,
            env=env,
            timeout=60,
        )
        self.assertEqual(rollback.returncode, 0, rollback.stdout + rollback.stderr)
        self.assertTrue(self.old_plist.exists())
        self.assertTrue(self.install.exists())


if __name__ == "__main__":
    unittest.main()
