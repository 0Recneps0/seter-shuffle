"""Tests for stable-preparation: installer, daily run, migration.

Standard library unittest only. These tests run the shell scripts
in test mode (SETER_TEST_MODE=1) with override directories, so no
real install, launchd job, or Music playlist is ever touched.
AppleScript itself is still not executed here; what is tested is
the logic that can be tested without a Mac: plist generation,
path handling, version refusal, migration dry-run/confirm/
rollback file effects, daily mapping pre-checks, and the daily
library-manifest writer.
"""

from __future__ import annotations

import hashlib
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from seter_shuffle.manifest import manifest_lines, write_library_manifest
from seter_shuffle.tracks import Track, load_library

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests" / "fixtures" / "sample-library.json"


def run_script(script: str, args: list[str], env_extra: dict[str, str]) -> subprocess.CompletedProcess:
    env = dict(os.environ)
    env["SETER_TEST_MODE"] = "1"
    env.update(env_extra)
    return subprocess.run(
        ["bash", str(ROOT / script), *args],
        capture_output=True,
        text=True,
        env=env,
        timeout=60,
    )


def mapping_file(state: Path, name: str) -> Path:
    safe = name.replace("\n", "_").replace("\r", "_").replace(" ", "_").replace("/", "_")
    # daily.sh / run.sh use tr ' /' '__': a space or slash becomes
    # one underscore each, matching the expression above.
    digest = hashlib.sha256(name.encode()).hexdigest()[:12]
    return state / f"sort-mapping-{safe}-{digest}.txt"


def write_mapping(state: Path, target: str, mapping: str = "forward", sort: str = "Playlist Order", age_seconds: int = 60) -> Path:
    import time

    path = mapping_file(state, target)
    path.write_text(
        f"MAPPING: {mapping}\nTHROWAWAY: Throwaway\nTARGET: {target}\nSORT: {sort}\nTIMESTAMP: {int(time.time()) - age_seconds}\n",
        encoding="utf-8",
    )
    return path


class InstallerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.install = self.base / "install"
        self.agents = self.base / "agents"
        self.state = self.base / "state"
        self.env = {
            "SETER_PYTHON_INSTALL_DIR": str(self.install),
            "SETER_LAUNCHAGENTS_DIR": str(self.agents),
            "SETER_STATE_DIR": str(self.state),
        }

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_install_no_daily_copies_files_and_marks_version(self) -> None:
        result = run_script("setup-python.sh", ["--no-daily", "-y"], self.env)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertTrue((self.install / "run.sh").exists())
        self.assertTrue((self.install / "daily.sh").exists())
        self.assertTrue((self.install / "bridge" / "apply-order.applescript").exists())
        self.assertTrue((self.install / "seter_shuffle" / "cli.py").exists())
        self.assertEqual((self.install / "installed-version.txt").read_text().strip(), "3.0.7")
        self.assertFalse((self.agents / "com.seter.python.daily.plist").exists())

    def test_install_is_idempotent_for_same_version(self) -> None:
        first = run_script("setup-python.sh", ["--no-daily", "-y"], self.env)
        second = run_script("setup-python.sh", ["--no-daily", "-y"], self.env)
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual((self.install / "installed-version.txt").read_text().strip(), "3.0.7")

    def test_install_refuses_different_version_without_force(self) -> None:
        run_script("setup-python.sh", ["--no-daily", "-y"], self.env)
        (self.install / "installed-version.txt").write_text("2.6\n", encoding="utf-8")
        refused = run_script("setup-python.sh", ["--no-daily", "-y"], self.env)
        self.assertNotEqual(refused.returncode, 0)
        self.assertIn("already holds version", refused.stderr + refused.stdout)
        forced = run_script("setup-python.sh", ["--no-daily", "-y", "--force"], self.env)
        self.assertEqual(forced.returncode, 0, forced.stderr)
        self.assertEqual((self.install / "installed-version.txt").read_text().strip(), "3.0.7")

    def test_daily_plist_uses_single_hour_variable_and_new_label(self) -> None:
        result = run_script("setup-python.sh", ["-y"], self.env)
        self.assertEqual(result.returncode, 0, result.stderr)
        plist = (self.agents / "com.seter.python.daily.plist").read_text()
        self.assertIn("<string>com.seter.python.daily</string>", plist)
        self.assertNotIn("<string>com.seter.daily</string>", plist)
        self.assertIn("<integer>8</integer>", plist)
        self.assertIn("daily.sh", plist)
        self.assertIn("My New Sandwich Recipe", plist)
        # The hour in the script header is the single source: the
        # default plist must agree with DAILY_HOUR in setup-python.sh.
        header = (ROOT / "setup-python.sh").read_text()
        self.assertIn("DAILY_HOUR=8", header)

    def test_daily_plist_hour_override(self) -> None:
        result = run_script("setup-python.sh", ["-y", "--hour", "9", "--minute", "30"], self.env)
        self.assertEqual(result.returncode, 0, result.stderr)
        plist = (self.agents / "com.seter.python.daily.plist").read_text()
        self.assertIn("<integer>9</integer>", plist)
        self.assertIn("<integer>30</integer>", plist)

    def test_installer_never_targets_v26_job(self) -> None:
        text = (ROOT / "setup-python.sh").read_text()
        # The installer may mention v2.6 in comments, but its plist
        # label and install directory must never be the v2.6 ones.
        self.assertNotIn('PLIST_LABEL="com.seter.daily"', text)
        self.assertNotIn("Documents/SeTeRShuffle\"", text)
        self.assertIn("Documents/SeTeRShufflePython", text)


class MigrationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.agents = self.base / "agents"
        self.agents.mkdir()
        self.install = self.base / "install"
        self.install.mkdir()
        self.env = {
            "SETER_LAUNCHAGENTS_DIR": str(self.agents),
            "SETER_PYTHON_INSTALL_DIR": str(self.install),
            "SETER_V26_DIR": str(self.base / "v26"),
        }
        (self.agents / "com.seter.daily.plist").write_text("<old/>", encoding="utf-8")
        (self.agents / "com.seter.python.daily.plist").write_text("<new/>", encoding="utf-8")

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_dry_run_changes_nothing(self) -> None:
        result = run_script("migrate-to-python.sh", ["--dry-run"], self.env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.agents / "com.seter.daily.plist").exists())
        self.assertTrue((self.agents / "com.seter.python.daily.plist").exists())
        self.assertEqual(list(self.agents.glob("*.disabled-*")), [])

    def test_confirm_disables_old_and_rollback_restores_it(self) -> None:
        confirmed = run_script("migrate-to-python.sh", ["--confirm"], self.env)
        self.assertEqual(confirmed.returncode, 0, confirmed.stderr + confirmed.stdout)
        self.assertFalse((self.agents / "com.seter.daily.plist").exists())
        disabled = list(self.agents.glob("com.seter.daily.plist.disabled-*"))
        self.assertEqual(len(disabled), 1)
        self.assertTrue((self.agents / "com.seter.python.daily.plist").exists())
        rolled = run_script("migrate-to-python.sh", ["--rollback"], self.env)
        self.assertEqual(rolled.returncode, 0, rolled.stderr + rolled.stdout)
        self.assertTrue((self.agents / "com.seter.daily.plist").exists())
        self.assertEqual(list(self.agents.glob("com.seter.daily.plist.disabled-*")), [])

    def test_confirm_refuses_without_python_install(self) -> None:
        env = dict(self.env)
        env["SETER_PYTHON_INSTALL_DIR"] = str(self.base / "missing-install")
        result = run_script("migrate-to-python.sh", ["--confirm"], env)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.agents / "com.seter.daily.plist").exists())


class DailyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.state = self.base / "state"
        self.state.mkdir()
        self.env = {
            "SETER_STATE_DIR": str(self.state),
            "SETER_BACKUP_DIR": str(self.base / "backups"),
        }

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_daily_without_mappings_attempts_selfprobe_and_fails_closed(self) -> None:
        # v3.0.2: daily.sh no longer refuses for lack of a mapping
        # without trying; it auto self-probes first. On this
        # machine there is no osascript, so the probe fails, and
        # the run must fail closed naming the target and snapshot,
        # before any build step.
        result = run_script("daily.sh", ["My New Sandwich Recipe"], self.env)
        self.assertNotEqual(result.returncode, 0)
        combined = result.stdout + result.stderr
        self.assertIn("auto self-probe failed for 'My New Sandwich Recipe'", combined)
        self.assertIn("sort-probe-snapshot.txt", combined)
        self.assertNotIn("daily dedupe done", combined)
        # And it never invokes a throwaway sortprobe: only selfprobe.
        text = (ROOT / "daily.sh").read_text()
        self.assertNotIn("run.sh\" sortprobe", text)

    def test_daily_stale_mapping_is_refreshed_by_probe_or_fails_closed(self) -> None:
        # v3.0.2: a stale mapping is no longer the refusal itself;
        # the auto self-probe refreshes it. On this machine the
        # probe cannot run (no osascript), so the run fails at
        # the probe, not at a stale-mapping check, and still
        # changes nothing.
        write_mapping(self.state, "My New Sandwich Recipe", age_seconds=180000)
        write_mapping(self.state, "SeTeR Rediscover")
        result = run_script("daily.sh", ["My New Sandwich Recipe"], self.env)
        self.assertNotEqual(result.returncode, 0)
        combined = result.stdout + result.stderr
        self.assertIn("auto self-probe failed for 'My New Sandwich Recipe'", combined)
        self.assertNotIn("daily dedupe done", combined)

    def test_daily_dry_run_passes_with_fresh_mappings(self) -> None:
        write_mapping(self.state, "My New Sandwich Recipe")
        write_mapping(self.state, "SeTeR Rediscover")
        env = dict(self.env)
        env["SETER_DAILY_DRY_RUN"] = "1"
        result = run_script("daily.sh", ["My New Sandwich Recipe"], env)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("dry run", result.stdout + result.stderr)


class ManifestTests(unittest.TestCase):
    def test_manifest_columns_and_rows(self) -> None:
        tracks = load_library(str(FIXTURE))
        lines = manifest_lines(tracks)
        self.assertEqual(lines[0], "persistent_id\tartist\talbum\ttitle")
        self.assertEqual(len(lines), len(tracks) + 1)
        first = tracks[0]
        self.assertEqual(
            lines[1],
            f"{first.persistent_id}\t{first.artist}\t{first.album}\t{first.name}",
        )

    def test_manifest_write_via_cli(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "manifest.tsv"
            result = subprocess.run(
                [sys.executable, "-m", "seter_shuffle.cli", "library-manifest",
                 "--library", str(FIXTURE), "--out", str(out)],
                capture_output=True, text=True, cwd=str(ROOT), timeout=60,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(out.exists())
            self.assertTrue(out.read_text().startswith("persistent_id\tartist\talbum\ttitle"))


if __name__ == "__main__":
    unittest.main()
