"""Regression tests for the v3.0.2 one-click installer fix.

The v3.0 one-click run died on a Mac at Step 1 with
"SETUP_ARGS[@]: unbound variable": macOS ships bash 3.2, where
expanding an empty array under set -u is an error, unlike bash 5
on Linux (this machine), so the bug was invisible here. The fix
removes arrays from install-or-update.sh entirely (arguments are
rebuilt with set -- / "$@") and makes the script chmod +x its
own helpers, because the v3.0 zip shipped them mode 660 and
double-clicking gave "permission denied".
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = sorted(
    p for p in ROOT.glob("*.sh") if p.name != "install-or-update.sh"
) + [ROOT / "install-or-update.sh"]


def shell_files():
    return [p for p in ROOT.glob("*.sh")]


class OneClickFixTest(unittest.TestCase):
    def test_no_array_expansion_in_installer(self):
        lines = (ROOT / "install-or-update.sh").read_text(encoding="utf-8").splitlines()
        code = "\n".join(line for line in lines if not line.lstrip().startswith("#"))
        self.assertNotIn("[@]", code, "installer must contain no [@] expansion")
        self.assertNotIn("SETUP_ARGS", code, "SETUP_ARGS array must be gone")
        # Arguments rebuilt with set -- / "$@", which is safe empty on bash 3.2.
        self.assertIn('set -- "$@" --force', code)

    def test_only_apply_args_expansion_left_in_tree(self):
        for script in shell_files():
            text = script.read_text(encoding="utf-8")
            for match in re.finditer(r"\$\{(\w+)\[@\]\}", text):
                self.assertEqual(
                    match.group(1),
                    "apply_args",
                    f"{script.name}: unexpected [@] expansion {match.group(0)}",
                )
        run = (ROOT / "run.sh").read_text(encoding="utf-8")
        # apply_args is assigned all 7 elements in both branches before use.
        assignments = re.findall(r'apply_args=\(([^)]*)\)', run)
        self.assertEqual(len(assignments), 2)
        for assignment in assignments:
            self.assertEqual(len(re.findall(r'"[^"]*"', assignment)), 7)

    def test_default_no_argument_path_runs(self):
        """--yes only: no --playlist/--hour/--minute/--force from the
        user, the exact invocation that died at Step 1 on the Mac."""
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            install = base / "install"
            agents = base / "agents"
            state = base / "state"
            agents.mkdir()
            state.mkdir()
            (agents / "com.seter.daily.plist").write_text(
                "<plist>old</plist>", encoding="utf-8"
            )
            env = dict(os.environ)
            env["SETER_TEST_MODE"] = "1"
            env["SETER_PYTHON_INSTALL_DIR"] = str(install)
            env["SETER_LAUNCHAGENTS_DIR"] = str(agents)
            env["SETER_STATE_DIR"] = str(state)
            result = subprocess.run(
                ["bash", str(ROOT / "install-or-update.sh"), "--yes"],
                capture_output=True,
                text=True,
                env=env,
                timeout=60,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("ok install/update done", result.stdout)
            self.assertFalse((agents / "com.seter.daily.plist").exists())
            self.assertEqual(
                (install / "installed-version.txt").read_text().strip(), "3.0.4"
            )

    def test_chmod_self_restores_execute_bits(self):
        """Copy the tree with modes stripped to 644, run the copy,
        and check the helpers are executable afterwards."""
        with tempfile.TemporaryDirectory() as tmp:
            copy = Path(tmp) / "tree"
            shutil.copytree(
                ROOT,
                copy,
                ignore=shutil.ignore_patterns("__pycache__", "tests"),
            )
            helpers = [
                "setup-python.sh",
                "check-python.sh",
                "daily.sh",
                "run.sh",
                "migrate-to-python.sh",
                "install-or-update.sh",
                "SeTeR-Shuffle-Install.command",
            ]
            for name in helpers:
                path = copy / name
                if path.exists():
                    path.chmod(0o644)
            base = Path(tmp)
            install = base / "install"
            agents = base / "agents"
            state = base / "state"
            agents.mkdir()
            state.mkdir()
            env = dict(os.environ)
            env["SETER_TEST_MODE"] = "1"
            env["SETER_PYTHON_INSTALL_DIR"] = str(install)
            env["SETER_LAUNCHAGENTS_DIR"] = str(agents)
            env["SETER_STATE_DIR"] = str(state)
            result = subprocess.run(
                ["bash", str(copy / "install-or-update.sh"), "--yes"],
                capture_output=True,
                text=True,
                env=env,
                timeout=60,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            for name in helpers:
                path = copy / name
                if path.exists():
                    self.assertTrue(
                        path.stat().st_mode & 0o111,
                        f"{name} should be executable after a run",
                    )


if __name__ == "__main__":
    unittest.main()
