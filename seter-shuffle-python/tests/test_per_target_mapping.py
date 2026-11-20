"""Tests for the .5 per-target mapping guard and the undo/restore
-1728 fallback (failure modes 35 and 36).

Background, 2026-10-29 15:38 PT: Spencer ran ./run.sh flow
"SeTeR Flow" twice from the .4 folder. Both runs computed and
validated a Flow order, then apply failed verification ("final song
order does not match the desired order under mapping reversed"),
apply restored from the per-run snapshot, and run.sh's restore via
undo failed with the same AppleScript -1728 bulk-read error on
user playlist id 78940. State files proved both SeTeR Flow
per-run snapshots were 0 bytes (empty playlist at apply start),
no main SeTeR Flow backup was ever installed, and the recorded
mapping was "reversed" measured on throwaway "My New Sandwich
Recipe" at 13:13 PT.

Failure 1, mapping transfer: the .4 runs used the reversed mapping
measured on the main playlist (Playlist Order descending) for a NEW
target playlist, SeTeR Flow, whose sort is the default/manual
sort. A reversed build on a forward-sorted playlist lands
backwards, so verify correctly refused. The .4 create-then-read
fix worked for the snapshot (empty fallback); this failure is the
mapping being applied to a target with a different sort. The .5
fix makes mappings per-target: sortprobe records a mapping for
ONE target (with the user-declared sort label), and a build for
target X reads ONLY the mapping file for X, never a shared file.
The pre-.5 shared sort-mapping.txt is ignored, and apply/undo/
restore print the recorded throwaway and sort label in their GATE
lines so a mismatch is visible before building.

Failure 2, undo -1728: the .4 empty fallback went into
apply-order and the retired probe script, but NOT into
undo.applescript (and restore-original was the same). Undo's first
step is a bulk playlistIDs read on the target, which fails with
-1728 on the empty SeTeR Flow playlist, so undo died before
changing anything, and run.sh reported it as "may be partial"
when nothing had changed. The .5 fix applies the exact same empty
fallback to undo, restore-original, sort-probe, and the read-only
diagnose script, marks pre-change failures PLAYLIST_UNTOUCHED in
undo/restore, and makes run.sh's post-apply restore path tell
those apart from genuinely partial failures.

Behavioral tests execute the real mapping_for_build() (and
mapping_file_for / mapping_info_for) extracted from run.sh under
bash, as test_mapping_stderr.py does. Bridge tests are structural
because this machine has no Music app or osascript: they assert
the exact fallback and marker properties hold in the AppleScript
text.
"""

from __future__ import annotations

import subprocess
import tempfile
import textwrap
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUN_SH = ROOT / "run.sh"
BRIDGE = ROOT / "bridge"
RUN_TEXT = RUN_SH.read_text()


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


def _run_mapping(target, files):
    """Run mapping_for_build with a fake STATE dir.

    files maps a key to contents: "__TARGET__" is written to the
    computed per-target path; "sort-mapping.txt" writes the legacy
    shared file.
    """
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
        if "__TARGET__" in files:
            Path(mapfile).write_text(files["__TARGET__"])
        if "sort-mapping.txt" in files:
            (state / "sort-mapping.txt").write_text(files["sort-mapping.txt"])
        harness = textwrap.dedent(
            "STATE=%s\nLOG=%s/run.log\n%s\n"
            "out=\"$(mapping_for_build '%s')\"\n"
            "rc=$?\n"
            "printf 'RC=%%s\\n' \"$rc\"\n"
            "printf 'OUT=[%%s]\\n' \"$out\"\n"
            "exit \"$rc\"\n"
            % (state, state, _extract_helpers(), target)
        )
        proc2 = subprocess.run(
            ["bash", "-c", harness], capture_output=True, text=True, timeout=30
        )
        rc = int(
            next(
                l.split("=", 1)[1]
                for l in proc2.stdout.splitlines()
                if l.startswith("RC=")
            )
        )
        out = next(
            l[len("OUT=[") : -1]
            for l in proc2.stdout.splitlines()
            if l.startswith("OUT=[")
        )
        return rc, out, proc2.stderr


def _valid_mapping(target="SeTeR Flow", mapping="reversed", ts=None):
    if ts is None:
        ts = int(time.time())
    return (
        "MAPPING: %s\n" % mapping
        + "THROWAWAY: Flow Throwaway\n"
        + "TARGET: %s\n" % target
        + "SORT: Manual (default)\n"
        + "TIMESTAMP: %d\n" % ts
    )


class TestPerTargetMappingBehavior(unittest.TestCase):
    def test_valid_per_target_mapping_captures_exactly(self):
        rc, out, err = _run_mapping(
            "SeTeR Flow", {"__TARGET__": _valid_mapping()}
        )
        self.assertEqual(rc, 0)
        self.assertEqual(out, "reversed")
        self.assertEqual(err, "")

    def test_missing_per_target_file_refuses(self):
        rc, out, err = _run_mapping("SeTeR Flow", {})
        self.assertNotEqual(rc, 0)
        self.assertEqual(out, "")
        self.assertIn("GATE FAILED", err)

    def test_legacy_shared_file_is_ignored_not_used(self):
        # A valid legacy shared mapping must NOT authorize a build:
        # it is exactly the file that caused the mode-35 transfer.
        rc, out, err = _run_mapping(
            "SeTeR Flow", {"sort-mapping.txt": _valid_mapping("SeTeR Flow")}
        )
        self.assertNotEqual(rc, 0)
        self.assertEqual(out, "")
        self.assertIn("ignored", err)

    def test_target_field_mismatch_refuses(self):
        rc, out, err = _run_mapping(
            "SeTeR Flow",
            {"__TARGET__": _valid_mapping("My New Sandwich Recipe")},
        )
        self.assertNotEqual(rc, 0)
        self.assertEqual(out, "")
        self.assertIn("do not transfer", err)

    def test_missing_sort_label_refuses(self):
        contents = _valid_mapping().replace("SORT: Manual (default)\n", "")
        rc, out, err = _run_mapping("SeTeR Flow", {"__TARGET__": contents})
        self.assertNotEqual(rc, 0)
        self.assertEqual(out, "")
        self.assertIn("sort label", err)

    def test_stale_per_target_mapping_refuses(self):
        old = int(time.time()) - 180000
        rc, out, err = _run_mapping(
            "SeTeR Flow", {"__TARGET__": _valid_mapping(ts=old)}
        )
        self.assertNotEqual(rc, 0)
        self.assertEqual(out, "")
        self.assertIn("older than 48 hours", err)

    def test_different_targets_get_different_files(self):
        harness = textwrap.dedent(
            "STATE=/tmp\nLOG=/tmp/run.log\n%s\n"
            "printf '%%s\\n' \"$(mapping_file_for 'SeTeR Flow')\"\n"
            "printf '%%s\\n' \"$(mapping_file_for 'My New Sandwich Recipe')\"\n"
            % _extract_helpers()
        )
        proc = subprocess.run(
            ["bash", "-c", harness], capture_output=True, text=True, timeout=30
        )
        lines = [l for l in proc.stdout.splitlines() if l.startswith("/tmp/")]
        self.assertEqual(len(lines), 2)
        self.assertNotEqual(lines[0], lines[1])

    def test_mapping_info_prints_provenance(self):
        with tempfile.TemporaryDirectory() as tmp:
            state = Path(tmp) / "state"
            state.mkdir()
            body = _valid_mapping()
            harness = (
                "STATE=%s\nLOG=%s/run.log\n"
                "log() { printf 'LOG: %%s\\n' \"$*\" >> \"$LOG\"; printf 'LOG: %%s\\n' \"$*\"; }\n"
                "%s\n"
                "mapfile=\"$(mapping_file_for 'SeTeR Flow')\"\n"
                "cat > \"$mapfile\" <<'MAPEOF'\n%sMAPEOF\n"
                "mapping_info_for 'SeTeR Flow'\n"
                % (state, state, _extract_helpers(), body)
            )
            proc = subprocess.run(
                ["bash", "-c", harness],
                capture_output=True,
                text=True,
                timeout=30,
            )
            self.assertIn("SeTeR Flow", proc.stdout)
            self.assertIn("Flow Throwaway", proc.stdout)
            self.assertIn("Manual (default)", proc.stdout)
            self.assertIn("reversed", proc.stdout)


class TestPerTargetMappingStructure(unittest.TestCase):
    def test_sortprobe_requires_target_and_sort_label(self):
        self.assertIn("PROBE_TARGET", RUN_TEXT)
        self.assertIn("PROBE_SORT", RUN_TEXT)
        self.assertIn("sortprobe <throwaway> <target> <sort-label>", RUN_TEXT)

    def test_sortprobe_records_target_and_sort(self):
        self.assertIn("TARGET: ", RUN_TEXT)
        self.assertIn("SORT: ", RUN_TEXT)
        block = RUN_TEXT.split('if [ "$CMD" = "sortprobe" ] || [ "$CMD" = "selfprobe" ]; then')[1]
        block = block.split("# Undo needs no dump", 1)[0]
        self.assertIn("PROBE_TARGET", block)
        self.assertIn("PROBE_SORT", block)
        # v3.0.2: the self-probe label is recorded for self-probes.
        self.assertIn("SELF_PROBE_LABEL", block)

    def test_sortprobe_failure_deletes_per_target_file_only(self):
        block = RUN_TEXT.split('if [ "$CMD" = "sortprobe" ] || [ "$CMD" = "selfprobe" ]; then')[1]
        block = block.split("# Undo needs no dump", 1)[0]
        self.assertIn('rm -f "$MAP_FILE"', block)

    def test_build_callers_pass_target_and_print_provenance(self):
        self.assertIn('mapping_for_build "$PLAYLIST"', RUN_TEXT)
        self.assertIn('mapping_for_build "$target"', RUN_TEXT)
        self.assertIn('mapping_info_for "$PLAYLIST"', RUN_TEXT)
        self.assertIn('mapping_info_for "$target"', RUN_TEXT)

    def test_mapping_for_build_never_reads_legacy_mapping(self):
        # The legacy file may only appear in an existence check
        # for the tailored error message, never as a mapping source:
        # no line may both mention the legacy file and read a
        # MAPPING value from it.
        body = "\n".join(_function_lines(RUN_TEXT, "mapping_for_build"))
        for line in body.splitlines():
            if "sort-mapping.txt" in line:
                self.assertNotIn("grep", line)

    def test_restore_path_distinguishes_untouched_from_partial(self):
        self.assertIn("PLAYLIST_UNTOUCHED", RUN_TEXT)
        self.assertIn("untouched, NOT partial", RUN_TEXT)
        self.assertIn("playlist may be partial", RUN_TEXT)


def _bridge(name):
    return (BRIDGE / name).read_text()


class TestUndoRestoreFallback(unittest.TestCase):
    def test_undo_playlist_ids_fallback(self):
        text = _bridge("undo.applescript")
        self.assertIn("on playlistTrackCount", text)
        self.assertIn("playlistTrackCount(pl) is 0", text)

    def test_restore_playlist_ids_fallback(self):
        text = _bridge("restore-original.applescript")
        self.assertIn("on playlistTrackCount", text)
        self.assertIn("playlistTrackCount(pl) is 0", text)

    def test_sort_probe_playlist_ids_fallback(self):
        text = _bridge("sort-probe.applescript")
        self.assertIn("on playlistTrackCount", text)
        self.assertIn("playlistTrackCount(pl) is 0", text)

    def test_delete_fallback_in_undo_restore_sortprobe(self):
        for name in (
            "undo.applescript",
            "restore-original.applescript",
            "sort-probe.applescript",
        ):
            text = _bridge(name)
            self.assertIn("set remaining to my playlistTrackCount(pl)", text)

    def test_undo_and_restore_mark_prechange_failures(self):
        self.assertIn("PLAYLIST_UNTOUCHED", _bridge("undo.applescript"))
        self.assertIn("PLAYLIST_UNTOUCHED", _bridge("restore-original.applescript"))

    def test_every_playlist_ids_handler_has_empty_fallback(self):
        # Audit: every script defining playlistIDs must handle the
        # empty-playlist -1728 case, either via playlistTrackCount
        # or (retired probe-order) an inline count-of-0 check.
        for name in (
            "apply-order.applescript",
            "undo.applescript",
            "restore-original.applescript",
            "sort-probe.applescript",
            "probe-order.applescript",
        ):
            text = _bridge(name)
            self.assertIn("on playlistIDs", text)
            self.assertTrue(
                "playlistTrackCount(pl) is 0" in text
                or "(count of tracks of pl) is 0" in text,
                "%s playlistIDs lacks an empty fallback" % name,
            )


if __name__ == "__main__":
    unittest.main()
