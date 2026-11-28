"""Tests for exp-2026-11-26.1: daily.sh as a shortcut for run.sh
daily, AI always on for the daily run, organized previous
versions, and run.sh daily-status.

No Mac is involved: a stub run.sh stands in for run.sh daily's
child calls (the same harness as test_selfprobe.py), and the
organize / daily-status tests run the real run.sh against fake
install trees, so no Music playlist, launchd job, or real
install directory is ever touched.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "tests"))

import test_selfprobe as _selfprobe  # noqa: E402  (daily harness + daily_section)

_Base = _selfprobe.DailyAutoProbeTests


def _run(script: Path, args: list[str], env: dict[str, str]) -> subprocess.CompletedProcess:
    full_env = dict(os.environ)
    full_env.update(env)
    return subprocess.run(
        ["bash", str(script), *args],
        capture_output=True,
        text=True,
        env=full_env,
        timeout=60,
    )


class DailyWrapperTests(unittest.TestCase):
    """daily.sh delegates to run.sh daily, passing args and hooks through."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.install = self.base / "install"
        self.install.mkdir()
        self.state = self.base / "state"
        self.state.mkdir()
        shutil.copy(ROOT / "daily.sh", self.install / "daily.sh")
        stub = self.install / "run.sh"
        stub.write_text(
            "#!/bin/bash\n"
            "echo \"$*\" >> \"$STUB_CALLS\"\n"
            "printf 'STATE=%s DRY=%s AI_DIR=%s\\n' \"${SETER_STATE_DIR:-unset}\" \"${SETER_DAILY_DRY_RUN:-unset}\" \"${SETER_AI_DIR:-unset}\" >> \"$STUB_CALLS.env\"\n",
            encoding="utf-8",
        )
        stub.chmod(0o755)
        self.calls = self.base / "calls.log"
        self.env = {
            "SETER_STATE_DIR": str(self.state),
            "SETER_DAILY_DRY_RUN": "1",
            "SETER_AI_DIR": str(self.base / "settings"),
            "STUB_CALLS": str(self.calls),
        }

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_wrapper_passes_playlist_arg_to_run_sh_daily(self) -> None:
        result = _run(self.install / "daily.sh", ["My New Sandwich Recipe"], self.env)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(
            self.calls.read_text().splitlines(),
            ["daily My New Sandwich Recipe"],
        )

    def test_wrapper_with_no_arg_passes_bare_daily(self) -> None:
        result = _run(self.install / "daily.sh", [], self.env)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.calls.read_text().splitlines(), ["daily"])

    def test_wrapper_passes_test_hooks_through(self) -> None:
        result = _run(self.install / "daily.sh", ["My New Sandwich Recipe"], self.env)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        env_lines = (Path(str(self.calls) + ".env")).read_text().splitlines()
        self.assertEqual(
            env_lines,
            [f"STATE={self.state} DRY=1 AI_DIR={self.base / 'settings'}"],
        )


class DailyAiGuaranteeTests(_Base):
    """The daily run exports SETER_AI=1 before the flow step, even
    with no ai-enabled marker file anywhere."""

    def setUp(self) -> None:
        super().setUp()
        stub = self.install / "run.sh"
        text = stub.read_text(encoding="utf-8")
        stub.write_text(
            text.replace(
                'echo "$*" >> "$STUB_CALLS"\n',
                'echo "$*" >> "$STUB_CALLS"\n'
                'if [ "$1" = "flow" ]; then echo "FLOW_AI=${SETER_AI:-unset}" >> "$STUB_CALLS.ai"\nfi\n',
                1,
            ),
            encoding="utf-8",
        )

    def test_daily_exports_ai_for_flow_without_marker(self) -> None:
        # No ai-enabled marker exists anywhere in this harness
        # (no settings dir at all), and SETER_AI is unset: the
        # daily flow must still see AI on.
        self.assertNotIn("SETER_AI", self.env)
        result = self.run_daily()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        ai = (Path(str(self.calls) + ".ai")).read_text().splitlines()
        self.assertEqual(ai, ["FLOW_AI=1"])
        daily_log = (self.state / "daily.log").read_text(encoding="utf-8")
        self.assertIn("AI tagging is on for this run", daily_log)
        self.assertIn("SETER_AI=1", daily_log)

    def test_ai_export_exists_only_in_the_daily_section(self) -> None:
        # A manual run must not force AI: the export lives only
        # in the daily section, nowhere else in run.sh. Count
        # code lines, not comments, so commenting the export
        # out fails this test too.
        text = (ROOT / "run.sh").read_text(encoding="utf-8")
        code_lines = [
            line.strip()
            for line in text.splitlines()
            if not line.strip().startswith("#")
        ]
        self.assertEqual(code_lines.count("export SETER_AI=1"), 1)
        self.assertIn("export SETER_AI=1", _selfprobe.daily_section())


# Don't re-run the parent's tests under this subclass.
for _name in dir(_Base):
    if _name.startswith("test_") and _name not in DailyAiGuaranteeTests.__dict__:
        setattr(DailyAiGuaranteeTests, _name, None)

del _Base  # the loader would otherwise collect the parent class from this module too


class OrganizeTests(unittest.TestCase):
    """run.sh organize sweeps loose .bak files into previous-versions/ buckets."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.home = self.base / "home"
        self.home.mkdir()
        self.install = self.base / "install"
        self.install.mkdir()
        self.state = self.base / "state"
        self.state.mkdir()
        (self.install / "bridge").mkdir()
        (self.install / "seter_shuffle").mkdir()
        shutil.copy(ROOT / "run.sh", self.install / "run.sh")
        shutil.copy(ROOT / "check-python.sh", self.install / "check-python.sh")
        # Live files: must be untouched.
        (self.install / "seter_shuffle" / "cli.py").write_text("# live cli\n", encoding="utf-8")
        (self.install / "seter_shuffle" / "tracks.py").write_text("# live tracks\n", encoding="utf-8")
        # Loose .baks at top level, bridge/, seter_shuffle/.
        (self.install / "run.sh.bak-20261120-120000").write_text("# old run\n", encoding="utf-8")
        (self.install / "check-python.sh.bak-20261120-120000").write_text("# old check\n", encoding="utf-8")
        (self.install / "bridge" / "dump-library.applescript.bak-20261121-080000").write_text("-- old dump\n", encoding="utf-8")
        (self.install / "seter_shuffle" / "cli.py.bak-20261121-080000").write_text("# old cli\n", encoding="utf-8")
        # A previous-versions bucket that already exists: untouched.
        old_bucket = self.install / "previous-versions" / "20261119-090000"
        old_bucket.mkdir(parents=True)
        (old_bucket / "run.sh").write_text("# older run\n", encoding="utf-8")
        # A .bak outside the install tree: never touched.
        self.sibling = self.base / "sibling"
        self.sibling.mkdir()
        (self.sibling / "run.sh.bak-20261120-120000").write_text("# sibling\n", encoding="utf-8")
        (self.state / "run.log.bak-20261120-120000").write_text("# state log\n", encoding="utf-8")
        self.env = {
            "HOME": str(self.home),
            "SETER_STATE_DIR": str(self.state),
        }

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def run_organize(self) -> subprocess.CompletedProcess:
        return _run(self.install / "run.sh", ["organize"], self.env)

    def test_organize_moves_loose_baks_into_timestamp_buckets(self) -> None:
        result = self.run_organize()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("organize: moved 4, skipped 0", result.stdout)
        # Same stamp shares one bucket; relative paths preserved.
        bucket_a = self.install / "previous-versions" / "20261120-120000"
        self.assertEqual((bucket_a / "run.sh").read_text(), "# old run\n")
        self.assertEqual((bucket_a / "check-python.sh").read_text(), "# old check\n")
        bucket_b = self.install / "previous-versions" / "20261121-080000"
        self.assertEqual((bucket_b / "bridge" / "dump-library.applescript").read_text(), "-- old dump\n")
        self.assertEqual((bucket_b / "seter_shuffle" / "cli.py").read_text(), "# old cli\n")
        # No loose .bak files left in the tree.
        self.assertEqual(list(self.install.glob("*.bak-*")), [])
        self.assertEqual(list((self.install / "bridge").glob("*.bak-*")), [])
        self.assertEqual(list((self.install / "seter_shuffle").glob("*.bak-*")), [])
        # Live files and the pre-existing bucket are untouched.
        self.assertEqual((self.install / "seter_shuffle" / "cli.py").read_text(), "# live cli\n")
        self.assertEqual(
            (self.install / "previous-versions" / "20261119-090000" / "run.sh").read_text(),
            "# older run\n",
        )
        # Outside the install tree: untouched.
        self.assertEqual((self.sibling / "run.sh.bak-20261120-120000").read_text(), "# sibling\n")
        self.assertEqual((self.state / "run.log.bak-20261120-120000").read_text(), "# state log\n")

    def test_organize_skips_collision_without_overwriting(self) -> None:
        bucket = self.install / "previous-versions" / "20261120-120000"
        bucket.mkdir(parents=True)
        (bucket / "run.sh").write_text("# keep me\n", encoding="utf-8")
        result = self.run_organize()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("organize: moved 3, skipped 1", result.stdout)
        self.assertIn("skipped run.sh.bak-20261120-120000", result.stdout)
        self.assertEqual((bucket / "run.sh").read_text(), "# keep me\n")
        self.assertEqual((self.install / "run.sh.bak-20261120-120000").read_text(), "# old run\n")

    def test_organize_on_clean_tree_reports_zero(self) -> None:
        for p in self.install.glob("*.bak-*"):
            p.unlink()
        for p in (self.install / "bridge").glob("*.bak-*"):
            p.unlink()
        for p in (self.install / "seter_shuffle").glob("*.bak-*"):
            p.unlink()
        result = self.run_organize()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("organize: moved 0, skipped 0", result.stdout)

    def test_setup_organizes_old_baks_during_install(self) -> None:
        # A differing run.sh plus a loose .bak from an older
        # install: installing must bucket both, not leave .baks.
        (self.install / "installed-version.txt").write_text("3.5\n", encoding="utf-8")
        (self.install / "run.sh").write_text("# installed old run\n", encoding="utf-8")
        (self.install / "daily.sh.bak-20261120-120000").write_text("# old daily\n", encoding="utf-8")
        env = {
            "SETER_TEST_MODE": "1",
            "SETER_PYTHON_INSTALL_DIR": str(self.install),
            "SETER_LAUNCHAGENTS_DIR": str(self.base / "agents"),
            "SETER_STATE_DIR": str(self.state),
        }
        result = _run(ROOT / "setup-python.sh", ["--no-daily", "-y"], env)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        buckets = sorted((self.install / "previous-versions").iterdir())
        names = {b.name for b in buckets}
        self.assertIn("20261120-120000", names)
        self.assertEqual(
            (self.install / "previous-versions" / "20261120-120000" / "daily.sh").read_text(),
            "# old daily\n",
        )
        # The differing installed run.sh was bucketed under its
        # own (new) stamp by install_file, not left loose: exactly
        # one bucket holds a run.sh with the installed old content
        # (the other run.sh buckets are the setUp bucket and the
        # organized run.sh.bak bucket).
        run_buckets = [
            b for b in buckets
            if (b / "run.sh").exists()
            and (b / "run.sh").read_text() == "# installed old run\n"
        ]
        self.assertEqual(len(run_buckets), 1)
        self.assertEqual(list(self.install.glob("*.bak-*")), [])


class DailyStatusTests(unittest.TestCase):
    """run.sh daily-status reports plist, loaded job, last run, AI, manifest."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.home = self.base / "home"
        self.home.mkdir()
        self.install = self.base / "install"
        self.install.mkdir()
        self.agents = self.base / "agents"
        self.agents.mkdir()
        self.state = self.base / "state"
        self.state.mkdir()
        self.settings = self.base / "settings"
        self.settings.mkdir()
        shutil.copy(ROOT / "run.sh", self.install / "run.sh")
        shutil.copy(ROOT / "check-python.sh", self.install / "check-python.sh")
        self.env = {
            "HOME": str(self.home),
            "SETER_STATE_DIR": str(self.state),
            "SETER_LAUNCHAGENTS_DIR": str(self.agents),
            "SETER_AI_DIR": str(self.settings),
        }

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def write_plist(self, hour: int = 8, minute: int = 0, playlist: str = "My New Sandwich Recipe") -> None:
        (self.agents / "com.seter.python.daily.plist").write_text(
            '<?xml version="1.0" encoding="UTF-8"?>\n'
            '<plist version="1.0">\n<dict>\n'
            "\t<key>Label</key>\n\t<string>com.seter.python.daily</string>\n"
            "\t<key>ProgramArguments</key>\n\t<array>\n"
            "\t\t<string>/bin/bash</string>\n"
            f"\t\t<string>{self.install}/daily.sh</string>\n"
            f"\t\t<string>{playlist}</string>\n"
            "\t</array>\n"
            "\t<key>StartCalendarInterval</key>\n\t<dict>\n"
            f"\t\t<key>Hour</key>\n\t\t<integer>{hour}</integer>\n"
            f"\t\t<key>Minute</key>\n\t\t<integer>{minute}</integer>\n"
            "\t</dict>\n</dict>\n</plist>\n",
            encoding="utf-8",
        )

    def write_daily_log(self, lines: list[str]) -> None:
        (self.state / "daily.log").write_text("\n".join(lines) + "\n", encoding="utf-8")

    def run_status(self, extra_env: dict[str, str] | None = None) -> subprocess.CompletedProcess:
        env = dict(self.env)
        if extra_env:
            env.update(extra_env)
        return _run(self.install / "run.sh", ["daily-status"], env)

    def test_status_reports_plist_schedule_script_and_playlist(self) -> None:
        self.write_plist(hour=8, minute=0)
        result = self.run_status()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("daily plist: present", result.stdout)
        self.assertIn("daily schedule: 8:00", result.stdout)
        self.assertIn(f"daily script: {self.install}/daily.sh", result.stdout)
        self.assertIn("daily playlist: My New Sandwich Recipe", result.stdout)

    def test_status_says_cannot_check_launchctl_where_it_is_absent(self) -> None:
        self.write_plist()
        result = self.run_status()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        # This Linux VM has no launchctl: the report must say so
        # instead of failing or claiming the job is unloaded.
        self.assertIn("daily job loaded: cannot check on this system", result.stdout)

    def test_status_reports_last_run_and_done_outcome(self) -> None:
        self.write_plist()
        self.write_daily_log([
            "2026-11-25 08:00:01 daily run starting for playlist 'My New Sandwich Recipe'",
            "2026-11-25 08:05:12 daily run done for 'My New Sandwich Recipe'",
        ])
        result = self.run_status()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(
            "last daily run: 2026-11-25 08:00:01 daily run starting for playlist 'My New Sandwich Recipe'",
            result.stdout,
        )
        self.assertIn("last daily outcome: done", result.stdout)

    def test_status_reports_failed_outcome_with_reason(self) -> None:
        self.write_plist()
        self.write_daily_log([
            "2026-11-25 08:00:01 daily run starting for playlist 'My New Sandwich Recipe'",
            "2026-11-25 08:00:02 daily run done for 'My New Sandwich Recipe'",
            "2026-11-26 08:00:01 daily run starting for playlist 'My New Sandwich Recipe'",
            "2026-11-26 08:01:00 DAILY FAILED: shuffle 'My New Sandwich Recipe' failed (see /tmp/x/daily.log)",
        ])
        result = self.run_status()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("last daily run: 2026-11-26 08:00:01 daily run starting", result.stdout)
        self.assertIn("last daily outcome: 2026-11-26 08:01:00 DAILY FAILED: shuffle", result.stdout)

    def test_status_reports_ai_state(self) -> None:
        self.write_plist()
        (self.settings / "ai-enabled").touch()
        result = self.run_status()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("AI marker: present", result.stdout)
        self.assertIn("SETER_AI: unset", result.stdout)
        self.assertIn("AI tagging for Flow: on", result.stdout)
        (self.settings / "ai-enabled").unlink()
        result = self.run_status({"SETER_AI": "0"})
        self.assertIn("AI marker: absent", result.stdout)
        self.assertIn("SETER_AI: 0", result.stdout)
        self.assertIn("AI tagging for Flow: off", result.stdout)

    def test_status_reports_newest_manifest(self) -> None:
        self.write_plist()
        backups = self.install / "backups"
        backups.mkdir()
        (backups / "library-manifest-2026-11-24.tsv").write_text("x\n", encoding="utf-8")
        (backups / "library-manifest-2026-11-25.tsv").write_text("x\n", encoding="utf-8")
        result = self.run_status()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("newest library manifest: 2026-11-25", result.stdout)

    def test_status_with_nothing_installed(self) -> None:
        result = self.run_status()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("daily plist: missing", result.stdout)
        self.assertIn("last daily run: no daily log yet", result.stdout)
        self.assertIn("newest library manifest: none", result.stdout)


if __name__ == "__main__":
    unittest.main()
