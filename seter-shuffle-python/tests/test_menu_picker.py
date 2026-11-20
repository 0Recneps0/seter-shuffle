"""Tests for the v3.0.10 menu playlist picker.

Before v3.0.10, menu choices 1 (shuffle), 3 (dedupe), and 4
(undo) all required typing a playlist name exactly. Now they
offer a numbered list from bridge/list-playlists.applescript,
via menu_pick_playlist in run.sh:

  * the list is numbered and a number picks that name, with
    spaces preserved;
  * shuffle also offers L for the whole library, which maps
    to the old blank-playlist path (shuffle into
    "SeTeR Shuffle"), not to a playlist named "L";
  * 0, an invalid pick, or an out-of-range number falls
    back to typing a name;
  * a failed or empty listing falls back to typing a name,
    so a picker failure can never block the menu.

No Mac is involved: SETER_MENU_LIST_FILE (a test hook in
run.sh, never set by a real run) supplies the list file, so
osascript is never called here. The picker changes nothing
in Music and authorizes nothing; the menu's own gates
(ensure_mapping_for for shuffle/undo, dedupe's no-precheck
path) are unchanged and are covered by test_menu_bug.py.
"""

from __future__ import annotations

import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUN_SH = ROOT / "run.sh"
RUN_TEXT = RUN_SH.read_text()
BRIDGE_TEXT = (ROOT / "bridge" / "list-playlists.applescript").read_text()


def _function_lines(text, name):
    lines = text.splitlines()
    start = next(
        i for i, line in enumerate(lines) if line.startswith(name + "() {")
    )
    end = next(i for i in range(start + 1, len(lines)) if lines[i] == "}")
    return lines[start : end + 1]


PICKER = "\n".join(_function_lines(RUN_TEXT, "menu_pick_playlist"))


def _run_picker(mode, stdin, list_names=None, list_file_contents=None):
    """Run menu_pick_playlist with a stub list; return (stdout, stderr, rc)."""
    with tempfile.TemporaryDirectory() as tmp:
        env = {"PATH": "/usr/bin:/bin"}
        header = (
            "set -u\n"
            "BRIDGE=/nonexistent-bridge-dir\n"
            "MENU_PICKED=\n"
            "MENU_PICKED_LIBRARY=0\n"
        )
        if list_names is not None or list_file_contents is not None:
            list_file = Path(tmp) / "list.txt"
            if list_file_contents is not None:
                list_file.write_text(list_file_contents, encoding="utf-8")
            else:
                list_file.write_text(
                    "\n".join(list_names) + "\n", encoding="utf-8"
                )
            env["SETER_MENU_LIST_FILE"] = str(list_file)
        script = header + PICKER + (
            "\nmenu_pick_playlist %s\n" % mode
            + "printf 'PICKED=[%s] LIBRARY=%s\\n' \"$MENU_PICKED\" \"$MENU_PICKED_LIBRARY\"\n"
        )
        proc = subprocess.run(
            ["bash", "-c", script],
            input=stdin,
            capture_output=True,
            text=True,
            timeout=30,
            env=env,
        )
        return proc.stdout, proc.stderr, proc.returncode


class PickerSelectionTests(unittest.TestCase):
    def test_numbered_list_picks_name_with_spaces(self):
        out, err, rc = _run_picker(
            "dedupe", "2\n", list_names=["Alpha", "My Playlist", "Gamma"]
        )
        self.assertEqual(rc, 0, err)
        self.assertIn("  1) Alpha", out)
        self.assertIn("  2) My Playlist", out)
        self.assertIn("  3) Gamma", out)
        self.assertIn("PICKED=[My Playlist] LIBRARY=0", out)

    def test_shuffle_library_choice_maps_to_blank_path(self):
        out, err, rc = _run_picker(
            "shuffle", "L\n", list_names=["Alpha", "My Playlist"]
        )
        self.assertEqual(rc, 0, err)
        self.assertIn("  L) Whole library (into SeTeR Shuffle)", out)
        self.assertIn("PICKED=[] LIBRARY=1", out)

    def test_shuffle_lowercase_library_choice(self):
        out, err, rc = _run_picker(
            "shuffle", "l\n", list_names=["Alpha"]
        )
        self.assertEqual(rc, 0, err)
        self.assertIn("LIBRARY=1", out)

    def test_dedupe_has_no_library_choice(self):
        out, _, rc = _run_picker(
            "dedupe", "0\nTyped Name\n", list_names=["Alpha"]
        )
        self.assertEqual(rc, 0)
        self.assertNotIn("Whole library", out)

    def test_zero_falls_back_to_typing(self):
        out, err, rc = _run_picker(
            "undo", "0\nTyped Name\n", list_names=["Alpha", "Beta"]
        )
        self.assertEqual(rc, 0, err)
        self.assertIn("PICKED=[Typed Name] LIBRARY=0", out)

    def test_invalid_pick_falls_back_to_typing(self):
        out, err, rc = _run_picker(
            "dedupe", "x\nFallback Name\n", list_names=["Alpha"]
        )
        self.assertEqual(rc, 0, err)
        self.assertIn("not a playlist number", out)
        self.assertIn("PICKED=[Fallback Name] LIBRARY=0", out)

    def test_out_of_range_falls_back_to_typing(self):
        out, err, rc = _run_picker(
            "undo", "9\nFallback Name\n", list_names=["Alpha"]
        )
        self.assertEqual(rc, 0, err)
        self.assertIn("out of range", out)
        self.assertIn("PICKED=[Fallback Name] LIBRARY=0", out)

    def test_listing_failure_falls_back_to_typing(self):
        # No SETER_MENU_LIST_FILE and no osascript on this
        # machine: the picker must fall back to typing, not die.
        out, err, rc = _run_picker("dedupe", "Typed Name\n")
        self.assertEqual(rc, 0, err)
        self.assertNotIn("Pick a playlist", out)
        self.assertIn("PICKED=[Typed Name] LIBRARY=0", out)

    def test_empty_listing_falls_back_to_typing(self):
        out, err, rc = _run_picker(
            "dedupe", "Typed Name\n", list_file_contents=""
        )
        self.assertEqual(rc, 0, err)
        self.assertNotIn("Pick a playlist", out)
        self.assertIn("PICKED=[Typed Name] LIBRARY=0", out)


class PickerWiringTests(unittest.TestCase):
    def _menu_section(self):
        return RUN_TEXT.split('if [ "$CMD" = "menu" ]')[1].split(
            "# Sort-probe command"
        )[0]

    def test_menu_uses_picker_for_shuffle_dedupe_undo(self):
        menu = self._menu_section()
        self.assertEqual(menu.count("menu_pick_playlist"), 3)
        self.assertIn("menu_pick_playlist shuffle", menu)
        self.assertIn("menu_pick_playlist dedupe", menu)
        self.assertIn("menu_pick_playlist undo", menu)
        # The old typed-name prompts are gone from those choices;
        # typing now happens only inside the picker (and its
        # fallback), which lives outside the menu section.
        self.assertNotIn("printf 'Playlist (blank for SeTeR Shuffle): '", menu)
        self.assertNotIn("printf 'Playlist: '", menu)

    def test_shuffle_library_choice_uses_old_blank_path(self):
        menu = self._menu_section()
        choice1 = menu.split("      2)")[0]
        self.assertIn('MENU_PICKED_LIBRARY" = "1"', choice1)
        self.assertIn('menu_target="SeTeR Shuffle"', choice1)
        # Blank-playlist dispatch branches (old behaviour):
        # bare shuffle, and shuffle with a size only.
        self.assertIn('bash "$ROOT/run.sh" shuffle || notify', choice1)
        self.assertIn('bash "$ROOT/run.sh" shuffle "$sz" || notify', choice1)

    def test_menu_gates_unchanged(self):
        # Shuffle still pre-checks its (possibly picked) target,
        # undo still pre-checks the picked name, dedupe still
        # has no pre-check (see test_menu_bug.py).
        menu = self._menu_section()
        self.assertIn('ensure_mapping_for "$menu_target"', menu)
        self.assertEqual(menu.count('ensure_mapping_for "$pl"'), 1)
        dedupe_choice = menu.split("      3)")[1].split("      4)")[0]
        self.assertNotIn("ensure_mapping_for", dedupe_choice)

    def test_other_menu_choices_unchanged(self):
        menu = self._menu_section()
        for dispatch in (
            'bash "$ROOT/run.sh" rediscover',
            'bash "$ROOT/run.sh" flow ||',
            'bash "$ROOT/run.sh" flowPreview',
            'bash "$ROOT/run.sh" audit',
        ):
            self.assertIn(dispatch, menu)

    def test_no_new_empty_array_expansions(self):
        # The picker uses a temp file, never a bash array.
        expansions = [
            line for line in RUN_TEXT.splitlines() if "[@]" in line
        ]
        self.assertEqual(len(expansions), 1)
        self.assertIn("apply_args[@]", expansions[0])

    def test_list_script_is_read_only(self):
        self.assertIn('name of every user playlist', BRIDGE_TEXT)
        self.assertIn("READ-ONLY", BRIDGE_TEXT)
        for forbidden in ("delete playlist", "duplicate playlist", "make new"):
            self.assertNotIn(forbidden, BRIDGE_TEXT)


if __name__ == "__main__":
    unittest.main()
