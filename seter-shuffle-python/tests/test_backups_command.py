"""Tests for exp-2026-11-26.2: `run.sh backups [playlist]` lists restore points.

No Mac is involved: the tests run the real run.sh against fake
install trees with a fake $STATE, so no Music playlist, launchd job,
or real install directory is ever touched. Backup files are one
persistent ID per line, exactly as run.sh writes them.
"""

from __future__ import annotations

import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "tests"))


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


def _backup_filename(playlist: str) -> str:
    """The filename backup_path_for in run.sh computes for a playlist."""
    safe = playlist.replace("\n", "_").replace("\r", "_").replace(" ", "_").replace("/", "_")
    digest = hashlib.sha256(playlist.encode("utf-8")).hexdigest()[:12]
    return f"backup-{safe}-{digest}.txt"


class BackupsCommandTests(unittest.TestCase):
    """run.sh backups lists a playlist's restore points, read-only."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.home = self.base / "home"
        self.home.mkdir()
        self.install = self.base / "install"
        self.install.mkdir()
        self.state = self.base / "state"
        self.state.mkdir()
        shutil.copy(ROOT / "run.sh", self.install / "run.sh")
        shutil.copy(ROOT / "check-python.sh", self.install / "check-python.sh")
        self.env = {
            "HOME": str(self.home),
            "SETER_STATE_DIR": str(self.state),
        }

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def write_backup(
        self, playlist: str, suffix: str, ids: list[str], mtime: int
    ) -> Path:
        path = self.state / (_backup_filename(playlist) + suffix)
        path.write_text("".join(f"{pid}\n" for pid in ids), encoding="utf-8")
        os.utime(path, (mtime, mtime))
        return path

    def run_backups(self, *args: str) -> subprocess.CompletedProcess:
        return _run(self.install / "run.sh", ["backups", *args], self.env)

    def test_per_playlist_lists_every_kind_newest_run_snapshot_first(self) -> None:
        main = self.write_backup("SeTeR Flow", "", ["a", "b", "c"], 1795000000)
        prev = self.write_backup("SeTeR Flow", ".prev", ["a", "b"], 1794000000)
        pre_undo = self.write_backup("SeTeR Flow", ".pre-undo", ["a"], 1794500000)
        old_snap = self.write_backup(
            "SeTeR Flow", ".run-20261126-080000-111.txt", ["a", "b", "c", "d"], 1794800000
        )
        new_snap = self.write_backup(
            "SeTeR Flow", ".run-20261126-090000-111.txt", ["a"], 1794900000
        )
        result = self.run_backups("SeTeR Flow")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("backups for SeTeR Flow:", result.stdout)
        self.assertIn(f"  main: 3 songs, ", result.stdout)
        self.assertIn(str(main), result.stdout)
        self.assertIn(f"  previous: 2 songs, ", result.stdout)
        self.assertIn(str(prev), result.stdout)
        self.assertIn("  pre-undo snapshot: 1 song, ", result.stdout)
        self.assertIn(str(pre_undo), result.stdout)
        self.assertIn("  pre-restore snapshot: none", result.stdout)
        # Newest run snapshot first, even though its filename sorts later.
        self.assertLess(
            result.stdout.index(str(new_snap)), result.stdout.index(str(old_snap))
        )
        self.assertIn("  run snapshot: 1 song, ", result.stdout)
        self.assertIn("  run snapshot: 4 songs, ", result.stdout)

    def test_per_playlist_with_no_backups_reports_none(self) -> None:
        result = self.run_backups("No Such Playlist")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("backups for No Such Playlist:", result.stdout)
        self.assertIn("  main: none", result.stdout)
        self.assertIn("  previous: none", result.stdout)
        self.assertIn("  pre-undo snapshot: none", result.stdout)
        self.assertIn("  pre-restore snapshot: none", result.stdout)
        self.assertIn("  run snapshots: none", result.stdout)

    def test_run_snapshots_capped_at_ten_with_older_count(self) -> None:
        self.write_backup("SeTeR Flow", "", ["a"], 1795000000)
        for hour in range(12):
            self.write_backup(
                "SeTeR Flow",
                f".run-20261126-{hour:02d}0000-111.txt",
                ["a"],
                1794000000 + hour * 3600,
            )
        result = self.run_backups("SeTeR Flow")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout.count("  run snapshot: 1 song, "), 10)
        self.assertIn("  ... and 2 older run snapshots", result.stdout)

    def test_no_arg_lists_every_backup_newest_first(self) -> None:
        first = self.write_backup("SeTeR Flow", "", ["a", "b"], 1794000000)
        second = self.write_backup("My Playlist", "", ["a"], 1795000000)
        result = self.run_backups()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f"backups in {self.state}:", result.stdout)
        self.assertIn("  backup-SeTeR_Flow-", result.stdout)
        self.assertIn("  backup-My_Playlist-", result.stdout)
        # Newest (My Playlist) first.
        self.assertLess(
            result.stdout.index(str(second)), result.stdout.index(str(first))
        )

    def test_no_arg_empty_state_reports_none(self) -> None:
        result = self.run_backups()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("  none", result.stdout)

    def test_no_arg_capped_at_twenty_with_more_count(self) -> None:
        for n in range(21):
            self.write_backup(f"Playlist {n}", "", ["a"], 1794000000 + n)
        result = self.run_backups()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        # "1 song, " and "N songs, " both contain " song".
        self.assertEqual(result.stdout.count(" song"), 20)
        self.assertIn("  ... and 1 more", result.stdout)

    def test_playlist_name_with_space_and_slash_maps_to_same_file(self) -> None:
        main = self.write_backup("My List/One", "", ["a", "b"], 1795000000)
        result = self.run_backups("My List/One")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("  main: 2 songs, ", result.stdout)
        self.assertIn(str(main), result.stdout)
        # The sanitized filename, not the raw playlist name, is the file.
        self.assertIn("backup-My_List_One-", str(main))

    def test_backups_is_read_only(self) -> None:
        main = self.write_backup("SeTeR Flow", "", ["a", "b", "c"], 1795000000)
        # Every run.sh invocation writes its own run.log; the property
        # under test is that no backup file and no lock is touched.
        before_files = sorted(
            p.name for p in self.state.iterdir() if p.name.startswith("backup-")
        )
        before_mtime = main.stat().st_mtime_ns
        result = self.run_backups("SeTeR Flow")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(
            sorted(p.name for p in self.state.iterdir() if p.name.startswith("backup-")),
            before_files,
        )
        self.assertEqual(main.stat().st_mtime_ns, before_mtime)
        self.assertFalse((self.state / "run.lock.d").exists())

    def test_backups_appears_in_usage(self) -> None:
        result = _run(self.install / "run.sh", ["no-such-command"], self.env)
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn("backups [playlist]", result.stderr)


if __name__ == "__main__":
    unittest.main()
