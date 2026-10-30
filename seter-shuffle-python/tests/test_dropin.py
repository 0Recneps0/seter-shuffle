"""Tests for the drop-in replacement package (2026-10-29).

Closes the stable-prep audit gaps Spencer ordered closed:
mapping validity 24h -> 48h, interactive menu, last-reshuffled
stamp, macOS notifications, shuffle size wiring, and dedupe
name logging. Flow energy tuning is deliberately NOT changed
here: no discriminator already in the dump justifies a wider
spread without inventing a tempo, so the flat gospel-heavy wave
stays documented as a weakness (see the changelog entry).

Behavioral tests execute the real mapping_for_build() extracted
from run.sh, as test_per_target_mapping.py does. Bridge and
menu-routing tests are structural because this machine has no
Music app or osascript: they assert the exact properties in
the script text.
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
import textwrap
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUN_SH = ROOT / "run.sh"
RUN_TEXT = RUN_SH.read_text()
BRIDGE = ROOT / "bridge"
sys.path.insert(0, str(ROOT))

from seter_shuffle.cli import main as cli_main  # noqa: E402
from seter_shuffle.tracks import Track  # noqa: E402
from seter_shuffle.validate import validate_order_file  # noqa: E402


def _function_lines(text, name):
    lines = text.splitlines()
    start = next(
        i for i, line in enumerate(lines) if line.startswith(name + "() {")
    )
    end = next(i for i in range(start + 1, len(lines)) if lines[i] == "}")
    return lines[start : end + 1]


def _extract_helpers():
    lines = RUN_TEXT.splitlines()
    logfile = next(l for l in lines if l.startswith("logfile() {"))
    logerr = next(l for l in lines if l.startswith("logerr() {"))
    parts = [logfile, logerr]
    for name in ("mapping_file_for", "mapping_for_build", "mapping_info_for"):
        parts.append("\n".join(_function_lines(RUN_TEXT, name)))
    return "\n".join(parts)


def _valid_mapping(ts):
    return (
        "MAPPING: forward\nTHROWAWAY: T\nTARGET: Test Target\n"
        f"SORT: Playlist Order descending\nTIMESTAMP: {ts}\n"
    )


def _run_mapping(target, contents):
    with tempfile.TemporaryDirectory() as tmp:
        state = Path(tmp) / "state"
        state.mkdir()
        probe = textwrap.dedent(
            "STATE=%s\nLOG=%s/run.log\n%s\n"
            "mapfile=\"$(mapping_file_for '%s')\"\n"
            "printf 'MAPFILE=%%s\\n' \"$mapfile\"\n"
            % (state, state, _extract_helpers(), target)
        )
        proc = subprocess.run(
            ["bash", "-c", probe], capture_output=True, text=True, timeout=30
        )
        mapfile = next(
            l.split("=", 1)[1]
            for l in proc.stdout.splitlines()
            if l.startswith("MAPFILE=")
        )
        Path(mapfile).write_text(contents)
        harness = textwrap.dedent(
            "STATE=%s\nLOG=%s/run.log\n%s\n"
            "out=\"$(mapping_for_build '%s')\"\n"
            "rc=$?\n"
            "printf 'RC=%%s\\n' \"$rc\"\n"
            "printf 'OUT=[%%s]\\n' \"$out\"\n"
            "exit \"$rc\"\n"
            % (state, state, _extract_helpers(), target)
        )
        proc = subprocess.run(
            ["bash", "-c", harness], capture_output=True, text=True, timeout=30
        )
        rc = next(
            int(l.split("=", 1)[1])
            for l in proc.stdout.splitlines()
            if l.startswith("RC=")
        )
        out = next(
            l.split("[", 1)[1].rstrip("]")
            for l in proc.stdout.splitlines()
            if l.startswith("OUT=")
        )
        return rc, out, proc.stderr


class Mapping48hTests(unittest.TestCase):
    def test_mapping_fresh_at_47h(self):
        rc, out, _ = _run_mapping(
            "Test Target", _valid_mapping(int(time.time()) - 47 * 3600)
        )
        self.assertEqual(rc, 0)
        self.assertEqual(out, "forward")

    def test_mapping_stale_at_49h(self):
        rc, out, err = _run_mapping(
            "Test Target", _valid_mapping(int(time.time()) - 49 * 3600)
        )
        self.assertNotEqual(rc, 0)
        self.assertEqual(out, "")
        self.assertIn("48 hours", err)

    def test_no_24h_window_left_in_code(self):
        self.assertNotIn("86400", RUN_TEXT)
        self.assertIn("172800", RUN_TEXT)
        daily = (ROOT / "daily.sh").read_text()
        self.assertNotIn("86400", daily)
        self.assertIn("172800", daily)


class MenuTests(unittest.TestCase):
    def test_menu_command_accepted_and_dispatches(self):
        self.assertIn("menu)", RUN_TEXT)
        for dispatch in (
            'bash "$ROOT/run.sh" shuffle',
            'bash "$ROOT/run.sh" rediscover',
            'bash "$ROOT/run.sh" dedupe',
            'bash "$ROOT/run.sh" undo',
            'bash "$ROOT/run.sh" flow',
            'bash "$ROOT/run.sh" flowPreview',
            'bash "$ROOT/run.sh" audit',
        ):
            self.assertIn(dispatch, RUN_TEXT)

    def test_menu_shows_mapping_status_before_builds(self):
        self.assertIn("mapping_status_for", RUN_TEXT)
        self.assertIn("mapping status for", RUN_TEXT)
        # The menu never probes: no sortprobe dispatch inside it.
        menu = RUN_TEXT.split('if [ "$CMD" = "menu" ]')[1].split(
            "# Sort-probe command"
        )[0]
        self.assertNotIn("sortprobe", menu)


class StampTests(unittest.TestCase):
    def test_apply_stamps_only_after_verification(self):
        text = (BRIDGE / "apply-order.applescript").read_text()
        stamp_pos = text.index("Last reshuffled:")
        # Every error path that restores or aborts appears before
        # the stamp: the stamp line sits after the library-shrink
        # check and just before the APPLY OK return.
        self.assertLess(text.index("library shrank during the run"), stamp_pos)
        self.assertLess(stamp_pos, text.index('return "APPLY OK:'))

    def test_stamp_is_best_effort_and_flagged(self):
        text = (BRIDGE / "apply-order.applescript").read_text()
        self.assertIn("stampDescription", text)
        self.assertIn("description stamp skipped", text)
        self.assertIn('item 7 of argv', text)
        # Undo never stamps: no description write in undo.
        self.assertNotIn("description", (BRIDGE / "undo.applescript").read_text())
        self.assertNotIn("description", (BRIDGE / "restore-original.applescript").read_text())

    def test_run_passes_stamp_flag_only_for_shuffle_and_flow(self):
        self.assertIn('if [ "$mode" = "shuffle" ] || [ "$mode" = "flow" ]; then', RUN_TEXT)
        self.assertIn('stamp_flag="1"', RUN_TEXT)


class NotificationTests(unittest.TestCase):
    def test_notify_helper_is_best_effort(self):
        self.assertIn("notify() {", RUN_TEXT)
        notify = "\n".join(_function_lines(RUN_TEXT, "notify"))
        self.assertIn("osascript", notify)
        self.assertIn("notification unavailable", notify)

    def test_daily_notifies_on_success_and_failure(self):
        daily = (ROOT / "daily.sh").read_text()
        self.assertIn("notify() {", daily)
        self.assertIn('notify "SeTeR Shuffle daily run done', daily)
        self.assertIn('notify "SeTeR Shuffle daily run failed', daily)

    def test_apply_notifies_on_success_and_failure(self):
        self.assertIn('notify "SeTeR Shuffle: $target applied', RUN_TEXT)
        self.assertIn('notify "SeTeR Shuffle: apply failed', RUN_TEXT)


class SizeTests(unittest.TestCase):
    def test_shuffle_size_wiring_in_run(self):
        # Mode 39: the old shuffle_size_args array died under
        # bash 3.2 set -u on every blank-size shuffle, so size
        # is now spelled out branch by branch, never via an
        # array that can be empty. The flag itself is unchanged.
        # (The name still appears in the explanatory comment;
        # assert on code forms, not the comment.)
        self.assertNotIn("shuffle_size_args=", RUN_TEXT)
        self.assertNotIn("shuffle_size_args[@]", RUN_TEXT)
        self.assertIn('--size "$SHUFFLE_SIZE"', RUN_TEXT)
        self.assertIn("SETER_SHUFFLE_SIZE", RUN_TEXT)
        self.assertIn("100|250|500|1000|all", RUN_TEXT)

    def test_sized_in_place_shuffle_refuses(self):
        self.assertIn("would drop songs, so it refuses", RUN_TEXT)
        self.assertIn("an in-place playlist shuffle always reorders", RUN_TEXT)

    def test_cli_size_caps_shuffle(self):
        import io
        from contextlib import redirect_stdout

        lib = Path(__file__).resolve().parent / "fixtures" / "sample-library.json"
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "order.json"
            txt = Path(tmp) / "order.txt"
            buf = io.StringIO()
            with redirect_stdout(buf):
                rc = cli_main([
                    "shuffle", "--library", str(lib), "--out", str(out),
                    "--order-txt", str(txt), "--size", "2", "--seed", "7",
                ])
            self.assertEqual(rc, 0)
            self.assertEqual(len(txt.read_text().splitlines()), 2)

    def test_shuffle_size_validates_as_subset(self):
        lib = Path(__file__).resolve().parent / "fixtures" / "sample-library.json"
        with tempfile.TemporaryDirectory() as tmp:
            order = Path(tmp) / "order.txt"
            import json

            ids = [t["persistent_id"] for t in json.loads(lib.read_text())["tracks"]][:2]
            order.write_text("\n".join(ids) + "\n")
            # Exact shuffle mode must refuse a subset; shuffle-size must not.
            with self.assertRaises(ValueError):
                validate_order_file(lib, order, mode="shuffle")
            self.assertEqual(
                validate_order_file(lib, order, mode="shuffle-size"), ids
            )


class DedupeNameTests(unittest.TestCase):
    def test_dedupe_logs_each_duplicate_by_name(self):
        import io
        import json
        from contextlib import redirect_stdout

        lib = Path(__file__).resolve().parent / "fixtures" / "sample-library.json"
        data = json.loads(lib.read_text())
        tracks = data["tracks"]
        dup = dict(tracks[0])
        data["tracks"] = tracks + [dup]
        with tempfile.TemporaryDirectory() as tmp:
            lib2 = Path(tmp) / "lib.json"
            lib2.write_text(json.dumps(data))
            out = Path(tmp) / "order.json"
            txt = Path(tmp) / "order.txt"
            buf = io.StringIO()
            with redirect_stdout(buf):
                rc = cli_main([
                    "dedupe", "--library", str(lib2), "--out", str(out),
                    "--order-txt", str(txt),
                ])
            self.assertEqual(rc, 0)
            self.assertIn("Removed duplicate:", buf.getvalue())
            self.assertIn(tracks[0]["name"], buf.getvalue())


if __name__ == "__main__":
    unittest.main()
