"""Regression tests for setup-python.sh fixes (v3.0.6).

- warn() used to print an empty line instead of its message.
- Re-running setup from the installed copy used to hit `cp` on the
  same file.
- --uninstall must refuse a directory that isn't a SeTeR install.
"""

from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run_setup(script, args, install, launchagents, state):
    env = dict(os.environ)
    env.update(
        SETER_TEST_MODE="1",
        SETER_PYTHON_INSTALL_DIR=str(install),
        SETER_LAUNCHAGENTS_DIR=str(launchagents),
        SETER_STATE_DIR=str(state),
    )
    return subprocess.run(
        ["bash", str(script), *args],
        capture_output=True, text=True, env=env, timeout=60,
    )


class SetupFixesTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.install = base / "install"
        self.agents = base / "agents"
        self.state = base / "state"

    def tearDown(self):
        self.tmp.cleanup()

    def test_warn_prints_its_message(self):
        # Pull warn() out of the script and call it directly.
        script = (ROOT / "setup-python.sh").read_text()
        line = next(l for l in script.splitlines() if l.startswith("warn()"))
        out = subprocess.run(
            ["bash", "-c", f'{line}\nwarn "hello there"'],
            capture_output=True, text=True,
        )
        self.assertIn("hello there", out.stderr)

    def test_rerun_from_installed_copy_has_no_same_file_error(self):
        first = run_setup(ROOT / "setup-python.sh", ["--no-daily"],
                          self.install, self.agents, self.state)
        self.assertEqual(first.returncode, 0, first.stderr)
        again = run_setup(self.install / "setup-python.sh", ["--no-daily"],
                          self.install, self.agents, self.state)
        self.assertEqual(again.returncode, 0, again.stderr)
        self.assertNotIn("identical", again.stderr)

    def test_uninstall_refuses_non_install_directory(self):
        self.install.mkdir(parents=True)
        (self.install / "precious.txt").write_text("keep me")
        out = run_setup(ROOT / "setup-python.sh", ["--uninstall"],
                        self.install, self.agents, self.state)
        self.assertNotEqual(out.returncode, 0)
        self.assertTrue((self.install / "precious.txt").exists())

    def test_uninstall_removes_real_install(self):
        run_setup(ROOT / "setup-python.sh", ["--no-daily"],
                  self.install, self.agents, self.state)
        out = run_setup(ROOT / "setup-python.sh", ["--uninstall"],
                        self.install, self.agents, self.state)
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertFalse(self.install.exists())

    def test_installer_final_note_is_not_stale(self):
        text = (ROOT / "install-or-update.sh").read_text()
        self.assertNotIn("never\"\nsay \"auto-probes", text)
        self.assertNotIn("It never", text)


if __name__ == "__main__":
    unittest.main()
