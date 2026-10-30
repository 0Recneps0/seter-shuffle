"""Tests for the 2026-10-29 menu bug (mode 39), fixed as .7.

Proven from Spencer's Mac paste, 17:01 PT: ./run.sh menu, choice 1
Shuffle, playlist "My New Sandwich Recipe", size blank (all):
dump playlist succeeded (1612 songs), then run.sh died with
"line 799: shuffle_size_args[@]: unbound variable" under bash
set -u, before any compute or apply. No playlist change happened.

Root cause: macOS ships bash 3.2, where expanding an empty
array under set -u is an unbound-variable error, unlike bash 5
on Linux where it expands to nothing. The shuffle path built
shuffle_size_args=() for a blank size and then expanded it.
The menu path had the same shape (menu_args could be empty
for a blank playlist and blank size). The fix removes both
arrays: every branch spells out its full argument list.

The same paste proved a second gap: the menu printed
"mapping status: none recorded" and then dumped anyway,
because the mapping gate only fired at apply time. The menu
now pre-checks with mapping_ready_for and refuses before any
dump or apply. The non-interactive dedupe refusal in the same
paste (1612 entries / 806 unique, then GATE FAILED on the
missing mapping, no change) was correct and is unchanged.
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
RUN_TEXT = RUN_SH.read_text()


def _function_lines(text, name):
    lines = text.splitlines()
    start = next(
        i for i, line in enumerate(lines) if line.startswith(name + "() {")
    )
    end = next(i for i in range(start + 1, len(lines)) if lines[i] == "}")
    return lines[start : end + 1]


def _extract_gate_helpers():
    lines = RUN_TEXT.splitlines()
    parts = [
        next(l for l in lines if l.startswith("log() {")),
        next(l for l in lines if l.startswith("logerr() {")),
    ]
    for name in (
        "mapping_file_for",
        "mapping_status_for",
        "mapping_ready_for",
    ):
        parts.append("\n".join(_function_lines(RUN_TEXT, name)))
    return "\n".join(parts)


def _run_ready(target, contents):
    """Run mapping_ready_for against a fixture mapping file.

    contents None means no mapping file at all. Returns
    (returncode, combined stderr).
    """
    with tempfile.TemporaryDirectory() as tmp:
        state = Path(tmp) / "state"
        state.mkdir()
        header = textwrap.dedent(
            "STATE=%s\nLOG=%s/run.log\n%s\n"
            % (state, state, _extract_gate_helpers())
        )
        probe = header + (
            "mapfile=\"$(mapping_file_for '%s')\"\n"
            "printf 'MAPFILE=%%s\\n' \"$mapfile\"\n" % target
        )
        proc = subprocess.run(
            ["bash", "-c", probe], capture_output=True, text=True, timeout=30
        )
        mapfile = next(
            l.split("=", 1)[1]
            for l in proc.stdout.splitlines()
            if l.startswith("MAPFILE=")
        )
        if contents is not None:
            Path(mapfile).write_text(contents)
        harness = header + (
            "if mapping_ready_for '%s'; then echo READY; else echo REFUSED; fi\n"
            % target
        )
        proc = subprocess.run(
            ["bash", "-c", harness], capture_output=True, text=True, timeout=30
        )
        return proc.stdout, proc.stderr


def _mapping(mapping="forward", sort="Playlist Order", age_s=0):
    ts = int(time.time()) - age_s
    return (
        f"MAPPING: {mapping}\nTHROWAWAY: T\nTARGET: Test Target\n"
        f"SORT: {sort}\nTIMESTAMP: {ts}\n"
    )


class MappingReadyTests(unittest.TestCase):
    def test_missing_mapping_refuses_with_sortprobe_command(self):
        out, err = _run_ready("Test Target", None)
        self.assertIn("REFUSED", out)
        self.assertIn("sortprobe", err)
        self.assertIn("Test Target", err)

    def test_fresh_mapping_ready(self):
        out, _ = _run_ready("Test Target", _mapping())
        self.assertIn("READY", out)

    def test_stale_49h_mapping_refuses(self):
        out, err = _run_ready("Test Target", _mapping(age_s=49 * 3600))
        self.assertIn("REFUSED", out)
        self.assertIn("48 hours", err)

    def test_fresh_47h_mapping_ready(self):
        out, _ = _run_ready("Test Target", _mapping(age_s=47 * 3600))
        self.assertIn("READY", out)

    def test_missing_sort_label_refuses(self):
        out, _ = _run_ready("Test Target", _mapping(sort=""))
        self.assertIn("REFUSED", out)

    def test_other_mapping_refuses(self):
        out, _ = _run_ready("Test Target", _mapping(mapping="other"))
        self.assertIn("REFUSED", out)


class NoEmptyArrayTests(unittest.TestCase):
    def test_no_possibly_empty_array_expansions_remain(self):
        # Code forms only: the old names still appear in the
        # explanatory comments describing why they were removed.
        self.assertNotIn("shuffle_size_args=", RUN_TEXT)
        self.assertNotIn("shuffle_size_args[@]", RUN_TEXT)
        self.assertNotIn("menu_args=", RUN_TEXT)
        self.assertNotIn("menu_args[@]", RUN_TEXT)
        # The only [@] expansion left is apply_args, which is
        # always assigned exactly seven elements before use.
        expansions = [
            line for line in RUN_TEXT.splitlines() if "[@]" in line
        ]
        self.assertEqual(len(expansions), 1)
        self.assertIn("apply_args[@]", expansions[0])
        self.assertIn(
            'apply_args=("$target" "$ORDER_TXT" "$run_backup" '
            '"$build_mapping" "$allow_dupes" "$lib_songs" "$stamp_flag")',
            RUN_TEXT,
        )

    def test_shuffle_compute_branches_expand_cleanly_under_set_u(self):
        # Extract the verbatim shuffle compute block and run it
        # with a stub step() under set -u: blank size with a
        # source playlist must call the CLI with
        # --allow-duplicates and no --size, and a set size with
        # no source playlist must pass exactly one --size.
        lines = RUN_TEXT.splitlines()
        start = next(
            i
            for i, line in enumerate(lines)
            if line.strip().startswith("# Bash 3.2 (macOS")
        )
        end = next(
            i
            for i in range(start, len(lines))
            if 'apply_order "$TARGET_PLAYLIST" "shuffle"' in lines[i]
        )
        block = "\n".join(lines[start:end])
        for size, source, must, must_not in (
            ("", "Some Playlist", ["--allow-duplicates"], ["--size"]),
            ("100", "", ["--size", "100"], ["--allow-duplicates"]),
            ("all", "Some Playlist", ["--allow-duplicates"], ["--size"]),
        ):
            harness = textwrap.dedent(
                "set -u\n"
                "step() { printf 'STEP-ARGS: %%s\\n' \"$*\"; }\n"
                "PY=python3\nDUMP=/tmp/dump.json\nORDER=/tmp/order.json\n"
                "ORDER_TXT=/tmp/order.txt\n"
                "SHUFFLE_SIZE=%s\nSOURCE_PLAYLIST=%s\n%s\n"
                % (
                    f"'{size}'" if size else "''",
                    f"'{source}'" if source else "''",
                    block,
                )
            )
            proc = subprocess.run(
                ["bash", "-c", harness],
                capture_output=True,
                text=True,
                timeout=30,
            )
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertNotIn("unbound variable", proc.stderr)
            for token in must:
                self.assertIn(token, proc.stdout)
            for token in must_not:
                self.assertNotIn(token, proc.stdout)


class MenuPrecheckTests(unittest.TestCase):
    def _menu_section(self):
        return RUN_TEXT.split('if [ "$CMD" = "menu" ]')[1].split(
            "# Sort-probe command"
        )[0]

    def test_menu_prechecks_mapping_before_every_build(self):
        menu = self._menu_section()
        for target in (
            '"$menu_target"',
            '"SeTeR Rediscover"',
            '"SeTeR Flow"',
        ):
            self.assertIn(f"mapping_ready_for {target}", menu)
        # Dedupe and undo share the $pl branch.
        self.assertGreaterEqual(menu.count('mapping_ready_for "$pl"'), 2)
        # Each pre-check precedes its dispatch in the section.
        self.assertLess(
            menu.index('mapping_ready_for "$menu_target"'),
            menu.index('bash "$ROOT/run.sh" shuffle'),
        )
        self.assertLess(
            menu.index('mapping_ready_for "SeTeR Rediscover"'),
            menu.index('bash "$ROOT/run.sh" rediscover'),
        )

    def test_menu_never_dumps_directly(self):
        menu = self._menu_section()
        self.assertNotIn("dump-library", menu)
        self.assertNotIn("dump playlist", menu)


if __name__ == "__main__":
    unittest.main()
