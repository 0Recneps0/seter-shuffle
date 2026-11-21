"""Tests for the v3.0.11 exp 2026-11-20.6 Options page: the submenu
now lists everything Spencer might want to change (16 entries,
grouped), and run.sh got a colored ASCII banner for the main menu.

Design, so the tests pin the right contract:

  * Options (menu choice 8), grouped display with current values,
    then numbered choices 1-16, 0 back:
      1  AI tagging for Flow (toggle, already existed)
      2  AI blend, 0.0-1.0, default 0.6 (SETER_AI_BLEND, ai-blend)
      3  AI mood cost, 0-10, default 4 (SETER_AI_MOOD_COST, ai-mood-cost)
      4  Flow size, 10-200 songs, default 50 (SETER_FLOW_SIZE, flow-size)
      5  Flow pool, 0-1000, default 400, 0 = no cap
         (SETER_FLOW_POOL_MAX, flow-pool-max)
      6  Flow source playlist (already existed)
      7  Flow target playlist (already existed)
      8  Artist spacing, 1-5, default 2 (SETER_ARTIST_SPACING,
         artist-spacing)
      9  Split collabs (toggle, already existed)
      10 "Feat." counts as same artist (toggle, default ON,
         SETER_FEATURING_SAME_ARTIST, featuring-same-artist
         holding "1" or "0", absent = 1)
      11 Rediscover size, 5-500 songs, default 30
         (SETER_REDISCOVER_SIZE, rediscover-size; maps to
         Settings.rediscover_min)
      12 Rediscover max per artist, 0-10, default 3, 0 = no limit
         (SETER_REDISCOVER_MAX_PER_ARTIST, rediscover-max-per-artist)
      13 Rediscover cooldown, 0-90 days, default 14, 0 = off
         (SETER_REDISCOVER_COOLDOWN_DAYS, rediscover-cooldown-days)
      14 Rediscover stale after, 7-365 days, default 60
         (SETER_REDISCOVER_STALE_DAYS, rediscover-stale-days)
      15 Probe max age (already existed)
      16 Dedupe match, song/id toggle, default song
         (SETER_DEDUPE_MATCH, dedupe-match holding "song" or "id")
    All files live under the settings dir (same dir as
    ai-enabled). An env var already set wins over the file, and
    the menu says so instead of pretending a change took effect.
  * Deliberately NOT included: rediscover percent (not a size,
    confusing), rediscover max cap (500, a safety cap), AI batch
    size, AI time budget, preview count (display-only internals).
  * Wiring: cli.py _settings_from reads the new env vars
    (_env_int / _env_float: garbage reads as the default, out of
    range clamps into range); explicit CLI flags still win over
    env; --featuring-same-artist is a new BooleanOptionalAction
    flag. With no flags and no env, Settings defaults are
    unchanged. run.sh load_persisted_options exports the files
    into the env at startup, so direct commands, menu children,
    and the daily run all see the same settings; daily.sh needs
    no changes.
  * Menu input validation mirrors probe max age: a non-number or
    out-of-range value prints a plain message, leaves the old
    value unchanged, and stays in the submenu. AI blend accepts
    decimals (0, 0.x, 1, 1.0).
  * Banner (run.sh only, menu only): Spencer's own ASCII art —
    his "SeTeR" block in bold cyan, his "SHUFFLE" block in bold
    italic magenta (italic escape \\033[3m, closed with \\033[23m),
    then a dim "v3.5" line. The printf lines were
    generated from his files, never retyped. Colors exist only
    when stdout is a terminal; piped/test output stays
    byte-identical (no escape bytes anywhere). Subcommand and log
    output is never colorized.

No Mac is involved: SETER_AI_DIR is the test hook for the
settings dir, and the menu tests extract the shell functions
from run.sh and run them with bash -c, the same pattern as
test_menu_options.py. The banner pty test follows the existing
`script` pattern from test_menu_options.py.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
RUN_SH = ROOT / "run.sh"
RUN_TEXT = RUN_SH.read_text()

sys.path.insert(0, str(ROOT))

from seter_shuffle.cli import _settings_from, build_parser  # noqa: E402
from seter_shuffle.settings import Settings  # noqa: E402


def _function_lines(text, name):
    lines = text.splitlines()
    start = next(
        i for i, line in enumerate(lines) if line.startswith(name + "() {")
    )
    end = next(i for i in range(start + 1, len(lines)) if lines[i] == "}")
    return lines[start : end + 1]


FULL_FUNCS = [
    "options_dir",
    "options_ai_on",
    "options_ai_env_set",
    "options_set_ai",
    "options_split_collabs_on",
    "options_set_split_collabs",
    "options_probe_max_age",
    "options_write_probe_max_age",
    "options_flow_source",
    "options_flow_source_env_set",
    "options_write_flow_source",
    "options_set_flow_source",
    "options_flow_target",
    "options_flow_target_env_set",
    "options_write_flow_target",
    "options_set_flow_target",
    "options_read_file",
    "options_write_file",
    "options_read_int_file",
    "options_ai_blend",
    "options_ai_mood_cost",
    "options_flow_size",
    "options_flow_pool_max",
    "options_artist_spacing",
    "options_rediscover_size",
    "options_rediscover_max_per_artist",
    "options_rediscover_cooldown_days",
    "options_rediscover_stale_days",
    "options_featuring_on",
    "options_set_featuring",
    "options_dedupe_match",
    "options_set_dedupe_match",
    "options_set_ai_blend",
    "options_set_ai_mood_cost",
    "options_set_flow_size",
    "options_set_flow_pool_max",
    "options_set_artist_spacing",
    "options_set_rediscover_size",
    "options_set_rediscover_max_per_artist",
    "options_set_rediscover_cooldown_days",
    "options_set_rediscover_stale_days",
    "options_validate_number",
    "options_validate_blend",
    "options_env_note",
    "menu_options_set_value",
    "print_banner",
    "load_persisted_options",
    "menu_pick_playlist",
    "menu_options",
]

FULL_LIB = "\n".join(
    "\n".join(_function_lines(RUN_TEXT, name)) for name in FULL_FUNCS
)


def _run_full_script(tail, stdin, tmp, extra_env=None, list_names=None):
    """Run extracted run.sh option functions with a temp settings dir.

    Returns (stdout, stderr, returncode). The settings dir is tmp;
    SETER_AI_DIR points at it, HOME points at tmp too. list_names,
    when given, writes a SETER_MENU_LIST_FILE for the picker.
    """
    env = {
        "PATH": "/usr/bin:/bin",
        "HOME": str(tmp),
        "SETER_AI_DIR": str(tmp),
    }
    if list_names is not None:
        list_file = Path(tmp) / "list.txt"
        list_file.write_text("\n".join(list_names) + "\n", encoding="utf-8")
        env["SETER_MENU_LIST_FILE"] = str(list_file)
    if extra_env:
        env.update(extra_env)
    script = (
        "set -u\n"
        "BRIDGE=/nonexistent-bridge-dir\n"
        "MENU_PICKED=\n"
        "MENU_PICKED_LIBRARY=0\n"
        + FULL_LIB
        + "\n"
        + tail
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


def _getter(name):
    return f'printf "[%s]\\n" "$({name})"\n'


# (getter, file, default) for every new numeric setting.
NUMERIC = [
    ("options_ai_mood_cost", "ai-mood-cost", "4"),
    ("options_flow_size", "flow-size", "50"),
    ("options_flow_pool_max", "flow-pool-max", "400"),
    ("options_artist_spacing", "artist-spacing", "2"),
    ("options_rediscover_size", "rediscover-size", "30"),
    ("options_rediscover_max_per_artist", "rediscover-max-per-artist", "3"),
    ("options_rediscover_cooldown_days", "rediscover-cooldown-days", "14"),
    ("options_rediscover_stale_days", "rediscover-stale-days", "60"),
]

# (getter, file, low, high) for the clamp tests: a file below the
# low end clamps up, a file above the high end clamps down.
CLAMPS = [
    ("options_ai_mood_cost", "ai-mood-cost", 0, 10),
    ("options_flow_size", "flow-size", 10, 200),
    ("options_flow_pool_max", "flow-pool-max", 0, 1000),
    ("options_artist_spacing", "artist-spacing", 1, 5),
    ("options_rediscover_size", "rediscover-size", 5, 500),
    ("options_rediscover_max_per_artist", "rediscover-max-per-artist", 0, 10),
    ("options_rediscover_cooldown_days", "rediscover-cooldown-days", 0, 90),
    ("options_rediscover_stale_days", "rediscover-stale-days", 7, 365),
]


class FullOptionsDefaultsTests(unittest.TestCase):
    def test_all_numeric_defaults(self):
        with tempfile.TemporaryDirectory() as tmp:
            for getter, _file, default in NUMERIC:
                out, err, rc = _run_full_script(
                    _getter(getter), "", Path(tmp)
                )
                self.assertEqual(rc, 0, err)
                self.assertIn(f"[{default}]", out, getter)
            out, err, rc = _run_full_script(
                _getter("options_ai_blend"), "", Path(tmp)
            )
            self.assertEqual(rc, 0, err)
            self.assertIn("[0.6]", out)

    def test_numeric_files_read_back(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            values = {
                "ai-mood-cost": "7",
                "flow-size": "120",
                "flow-pool-max": "0",
                "artist-spacing": "1",
                "rediscover-size": "45",
                "rediscover-max-per-artist": "0",
                "rediscover-cooldown-days": "30",
                "rediscover-stale-days": "90",
            }
            for getter, file, _default in NUMERIC:
                (tmp / file).write_text(values[file] + "\n", encoding="utf-8")
                out, err, rc = _run_full_script(
                    _getter(getter), "", tmp
                )
                self.assertEqual(rc, 0, err)
                self.assertIn(f"[{values[file]}]", out, getter)
            (tmp / "ai-blend").write_text("0.25\n", encoding="utf-8")
            out, _, rc = _run_full_script(
                _getter("options_ai_blend"), "", tmp
            )
            self.assertEqual(rc, 0)
            self.assertIn("[0.25]", out)

    def test_garbage_files_read_as_default(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            for getter, file, default in NUMERIC:
                (tmp / file).write_text("abc\n", encoding="utf-8")
                out, err, rc = _run_full_script(
                    _getter(getter), "", tmp
                )
                self.assertEqual(rc, 0, err)
                self.assertIn(f"[{default}]", out, getter)
            for garbage in ("abc", "", "0.5.2"):
                (tmp / "ai-blend").write_text(garbage + "\n", encoding="utf-8")
                out, _, rc = _run_full_script(
                    _getter("options_ai_blend"), "", tmp
                )
                self.assertEqual(rc, 0)
                self.assertIn("[0.6]", out, garbage)

    def test_out_of_range_files_clamp(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            for getter, file, lo, hi in CLAMPS:
                (tmp / file).write_text(f"{hi + 500}\n", encoding="utf-8")
                out, err, rc = _run_full_script(
                    _getter(getter), "", tmp
                )
                self.assertEqual(rc, 0, err)
                self.assertIn(f"[{hi}]", out, getter)
                (tmp / file).write_text(f"{lo - 1}\n", encoding="utf-8")
                out, _, rc = _run_full_script(
                    _getter(getter), "", tmp
                )
                self.assertEqual(rc, 0)
                # A negative file value is not a number in the
                # unsigned scheme, so it reads as the default,
                # not as the low end; only a non-negative value
                # below the low end clamps up.
                if lo == 0:
                    default = dict(
                        (g, d) for g, _f, d in NUMERIC
                    )[getter]
                    self.assertIn(f"[{default}]", out, getter)
                else:
                    self.assertIn(f"[{lo}]", out, getter)
            (tmp / "ai-blend").write_text("2.5\n", encoding="utf-8")
            out, _, rc = _run_full_script(
                _getter("options_ai_blend"), "", tmp
            )
            self.assertEqual(rc, 0)
            self.assertIn("[1]", out)

    def test_featuring_default_on_and_file_off(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            tail = 'if options_featuring_on; then echo ON; else echo OFF; fi\n'
            out, err, rc = _run_full_script(tail, "", tmp)
            self.assertEqual(rc, 0, err)
            self.assertIn("ON", out)
            (tmp / "featuring-same-artist").write_text("0\n", encoding="utf-8")
            out, _, rc = _run_full_script(tail, "", tmp)
            self.assertEqual(rc, 0)
            self.assertIn("OFF", out)
            (tmp / "featuring-same-artist").write_text("1\n", encoding="utf-8")
            out, _, rc = _run_full_script(tail, "", tmp)
            self.assertEqual(rc, 0)
            self.assertIn("ON", out)
            (tmp / "featuring-same-artist").write_text("maybe\n", encoding="utf-8")
            out, _, rc = _run_full_script(tail, "", tmp)
            self.assertEqual(rc, 0)
            self.assertIn("ON", out)

    def test_dedupe_default_song_and_file_id(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            out, err, rc = _run_full_script(
                _getter("options_dedupe_match"), "", tmp
            )
            self.assertEqual(rc, 0, err)
            self.assertIn("[song]", out)
            (tmp / "dedupe-match").write_text("id\n", encoding="utf-8")
            out, _, rc = _run_full_script(
                _getter("options_dedupe_match"), "", tmp
            )
            self.assertEqual(rc, 0)
            self.assertIn("[id]", out)
            (tmp / "dedupe-match").write_text("junk\n", encoding="utf-8")
            out, _, rc = _run_full_script(
                _getter("options_dedupe_match"), "", tmp
            )
            self.assertEqual(rc, 0)
            self.assertIn("[song]", out)


class FullOptionsPersistTests(unittest.TestCase):
    def test_setters_write_files_and_keep_env_in_step(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            out, err, rc = _run_full_script(
                'options_set_flow_size 120\n'
                'options_set_ai_blend 0.75\n'
                'options_set_featuring 0\n'
                'options_set_dedupe_match id\n'
                'printf "ENV=[%s|%s|%s] VAR=[%s]\\n" '
                '"$SETER_FLOW_SIZE" "$SETER_AI_BLEND" '
                '"$SETER_FEATURING_SAME_ARTIST" "$DEDUPE_MATCH"\n',
                "",
                tmp,
            )
            self.assertEqual(rc, 0, err)
            self.assertIn("ENV=[120|0.75|0] VAR=[id]", out)
            self.assertEqual(
                (tmp / "flow-size").read_text(encoding="utf-8"), "120\n"
            )
            self.assertEqual(
                (tmp / "ai-blend").read_text(encoding="utf-8"), "0.75\n"
            )
            self.assertEqual(
                (tmp / "featuring-same-artist").read_text(encoding="utf-8"),
                "0\n",
            )
            self.assertEqual(
                (tmp / "dedupe-match").read_text(encoding="utf-8"), "id\n"
            )
            # No stray temp file left behind.
            self.assertEqual(
                [p.name for p in tmp.iterdir() if p.name.startswith(".")],
                [],
            )

    def test_loader_exports_new_settings_from_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            (tmp / "flow-size").write_text("120\n", encoding="utf-8")
            (tmp / "ai-blend").write_text("0.25\n", encoding="utf-8")
            (tmp / "rediscover-size").write_text("45\n", encoding="utf-8")
            (tmp / "featuring-same-artist").write_text("0\n", encoding="utf-8")
            (tmp / "dedupe-match").write_text("id\n", encoding="utf-8")
            out, err, rc = _run_full_script(
                'load_persisted_options\n'
                'printf "ENV=[%s|%s|%s|%s|%s]\\n" '
                '"$SETER_FLOW_SIZE" "$SETER_AI_BLEND" '
                '"$SETER_REDISCOVER_SIZE" "$SETER_FEATURING_SAME_ARTIST" '
                '"$DEDUPE_MATCH"\n',
                "",
                tmp,
            )
            self.assertEqual(rc, 0, err)
            self.assertIn("ENV=[120|0.25|45|0|id]", out)

    def test_loader_defaults_exported_when_nothing_set(self):
        with tempfile.TemporaryDirectory() as tmp:
            out, err, rc = _run_full_script(
                'load_persisted_options\n'
                'printf "ENV=[%s|%s|%s|%s]\\n" '
                '"$SETER_FLOW_SIZE" "$SETER_AI_BLEND" '
                '"$SETER_ARTIST_SPACING" "$SETER_REDISCOVER_STALE_DAYS"\n',
                "",
                Path(tmp),
            )
            self.assertEqual(rc, 0, err)
            self.assertIn("ENV=[50|0.6|2|60]", out)

    def test_loader_env_wins_over_file_and_records_markers(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            (tmp / "flow-size").write_text("120\n", encoding="utf-8")
            (tmp / "ai-blend").write_text("0.25\n", encoding="utf-8")
            out, err, rc = _run_full_script(
                'load_persisted_options\n'
                'printf "ENV=[%s|%s] MARK=[%s|%s]\\n" '
                '"$SETER_FLOW_SIZE" "$SETER_AI_BLEND" '
                '"${OPTIONS_FLOW_SIZE_ENV_SET:-unset}" '
                '"${OPTIONS_AI_BLEND_ENV_SET:-unset}"\n',
                "",
                tmp,
                extra_env={"SETER_FLOW_SIZE": "75", "SETER_AI_BLEND": "0.9"},
            )
            self.assertEqual(rc, 0, err)
            self.assertIn("ENV=[75|0.9] MARK=[1|1]", out)


class MenuFullOptionsTests(unittest.TestCase):
    def test_submenu_shows_all_sixteen_choices_grouped(self):
        with tempfile.TemporaryDirectory() as tmp:
            out, err, rc = _run_full_script("menu_options\n", "0\n", Path(tmp))
            self.assertEqual(rc, 0, err)
            for header in ("AI + Flow", "Shuffle", "Rediscover", "Dedupe + probes"):
                self.assertIn(header, out)
            for label in (
                "1) Toggle AI tagging",
                "2) Set AI blend (0.0-1.0)",
                "3) Set AI mood cost (0-10)",
                "4) Set Flow size (10-200 songs)",
                "5) Set Flow pool (0-1000, 0 = no cap)",
                "6) Set Flow source playlist",
                "7) Set Flow target playlist",
                "8) Set artist spacing (1-5)",
                "9) Toggle split collabs",
                '10) Toggle "feat." counts as same artist',
                "11) Set Rediscover size (5-500 songs)",
                "12) Set max per artist (0-10, 0 = no limit)",
                "13) Set Rediscover cooldown (0-90 days, 0 = off)",
                "14) Set stale after (7-365 days)",
                "15) Set probe max age (0-40 hours)",
                "16) Toggle dedupe match (song/id)",
                "0) Back",
            ):
                self.assertIn(label, out)
            for value in (
                "AI tagging for Flow: OFF",
                "AI blend: 0.6 (0-1)",
                "AI mood cost: 4 (0-10",
                "Flow size: 50 songs (10-200)",
                "Flow pool: 400 songs (0-1000, 0 = no cap)",
                "Flow source: Whole library",
                "Flow target: SeTeR Flow",
                "Artist spacing: 2 (1-5",
                "Split collabs: OFF",
                '"Feat." counts as same artist: ON',
                "Size: 30 songs (5-500)",
                "Max per artist: 3 (0-10, 0 = no limit)",
                "Cooldown: 14 days (0-90, 0 = off)",
                "Stale after: 60 days (7-365)",
                "Dedupe match: song (song = artist + title; id = track ID only)",
                "Probe max age: 0 hours",
            ):
                self.assertIn(value, out)

    def test_submenu_sets_blend_and_flow_size(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            out, err, rc = _run_full_script(
                "menu_options\n",
                "2\n0.75\n4\n120\n0\n",
                tmp,
            )
            self.assertEqual(rc, 0, err)
            self.assertIn("AI blend is now 0.75.", out)
            self.assertIn("Flow size is now 120 songs.", out)
            self.assertIn("AI blend: 0.75", out)
            self.assertIn("Flow size: 120 songs", out)
            self.assertEqual(
                (tmp / "ai-blend").read_text(encoding="utf-8"), "0.75\n"
            )
            self.assertEqual(
                (tmp / "flow-size").read_text(encoding="utf-8"), "120\n"
            )

    def test_submenu_rejects_bad_blend_and_keeps_old(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            out, err, rc = _run_full_script(
                "menu_options\n",
                "2\nabc\n2\n1.5\n2\n0.5\n0\n",
                tmp,
            )
            self.assertEqual(rc, 0, err)
            self.assertEqual(out.count("not a number 0.0-1.0"), 1)
            self.assertEqual(out.count("AI blend must be 0.0-1.0"), 1)
            self.assertIn("AI blend is now 0.5.", out)
            self.assertIn("AI blend: 0.5", out)
            self.assertEqual(
                (tmp / "ai-blend").read_text(encoding="utf-8"), "0.5\n"
            )
            # The submenu survived both bad inputs: it printed its
            # header again after each rejection.
            self.assertGreaterEqual(out.count("2) Set AI blend"), 3)

    def test_submenu_rejects_bad_numbers_and_keeps_old(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            out, err, rc = _run_full_script(
                "menu_options\n",
                "4\nabc\n4\n999\n4\n120\n0\n",
                tmp,
            )
            self.assertEqual(rc, 0, err)
            self.assertEqual(out.count("not a number 10-200"), 1)
            self.assertEqual(out.count("Flow size must be 10-200"), 1)
            self.assertIn("Flow size is now 120 songs.", out)
            self.assertEqual(
                (tmp / "flow-size").read_text(encoding="utf-8"), "120\n"
            )
            self.assertGreaterEqual(out.count("4) Set Flow size"), 3)

    def test_submenu_toggles_featuring_and_dedupe(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            out, err, rc = _run_full_script(
                "menu_options\n",
                "10\n16\n0\n",
                tmp,
            )
            self.assertEqual(rc, 0, err)
            self.assertIn('"Feat." counts as same artist is now OFF.', out)
            self.assertIn("Dedupe match is now id", out)
            self.assertIn('"Feat." counts as same artist: OFF', out)
            self.assertIn("Dedupe match: id", out)
            self.assertEqual(
                (tmp / "featuring-same-artist").read_text(encoding="utf-8"),
                "0\n",
            )
            self.assertEqual(
                (tmp / "dedupe-match").read_text(encoding="utf-8"), "id\n"
            )
            # Toggling again flips them back.
            out, _, rc = _run_full_script(
                "menu_options\n",
                "10\n16\n0\n",
                tmp,
            )
            self.assertEqual(rc, 0)
            self.assertIn('"Feat." counts as same artist is now ON.', out)
            self.assertIn("Dedupe match is now song", out)
            self.assertEqual(
                (tmp / "featuring-same-artist").read_text(encoding="utf-8"),
                "1\n",
            )
            self.assertEqual(
                (tmp / "dedupe-match").read_text(encoding="utf-8"), "song\n"
            )

    def test_submenu_env_override_refuses_new_settings(self):
        with tempfile.TemporaryDirectory() as tmp:
            out, err, rc = _run_full_script(
                "load_persisted_options\nmenu_options\n",
                "4\n2\n10\n16\n0\n",
                Path(tmp),
                extra_env={
                    "SETER_FLOW_SIZE": "75",
                    "SETER_AI_BLEND": "0.9",
                    "SETER_FEATURING_SAME_ARTIST": "0",
                    "SETER_DEDUPE_MATCH": "id",
                },
            )
            self.assertEqual(rc, 0, err)
            self.assertIn("SETER_FLOW_SIZE=75 in the environment", out)
            self.assertIn("SETER_AI_BLEND=0.9 in the environment", out)
            self.assertIn(
                "SETER_FEATURING_SAME_ARTIST=0 in the environment", out
            )
            self.assertIn("SETER_DEDUPE_MATCH=id in the environment", out)
            self.assertNotIn("Flow size is now", out)
            self.assertNotIn("AI blend is now", out)
            self.assertNotIn("counts as same artist is now", out)
            self.assertNotIn("Dedupe match is now", out)
            for name in (
                "flow-size",
                "ai-blend",
                "featuring-same-artist",
                "dedupe-match",
            ):
                self.assertFalse((Path(tmp) / name).exists())

    def test_submenu_flow_source_target_still_work_at_6_and_7(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            out, err, rc = _run_full_script(
                "menu_options\n",
                "6\n1\n7\n2\n0\n",
                tmp,
                list_names=["My Flow", "Other Flow"],
            )
            self.assertEqual(rc, 0, err)
            self.assertIn('Flow source is now "My Flow".', out)
            self.assertIn('Flow target is now "Other Flow".', out)
            self.assertEqual(
                (tmp / "flow-source-playlist").read_text(encoding="utf-8"),
                "My Flow\n",
            )
            self.assertEqual(
                (tmp / "flow-target-playlist").read_text(encoding="utf-8"),
                "Other Flow\n",
            )


class CliSettingsEnvTests(unittest.TestCase):
    def _settings(self, argv, env=None):
        with mock.patch.dict(os.environ, env or {}, clear=False):
            args = build_parser().parse_args(argv)
            return _settings_from(args)

    def test_env_vars_reach_settings(self):
        settings = self._settings(
            ["flow", "--library", "x"],
            {
                "SETER_ARTIST_SPACING": "4",
                "SETER_FLOW_SIZE": "120",
                "SETER_FLOW_POOL_MAX": "0",
                "SETER_REDISCOVER_SIZE": "45",
                "SETER_REDISCOVER_STALE_DAYS": "90",
                "SETER_REDISCOVER_MAX_PER_ARTIST": "1",
                "SETER_REDISCOVER_COOLDOWN_DAYS": "30",
                "SETER_AI_BLEND": "0.25",
                "SETER_AI_MOOD_COST": "7",
                "SETER_FEATURING_SAME_ARTIST": "0",
            },
        )
        self.assertEqual(settings.artist_spacing, 4)
        self.assertEqual(settings.flow_size, 120)
        self.assertEqual(settings.flow_pool_max, 0)
        self.assertEqual(settings.rediscover_min, 45)
        self.assertEqual(settings.stale_days, 90)
        self.assertEqual(settings.rediscover_max_per_artist, 1)
        self.assertEqual(settings.rediscover_cooldown_days, 30)
        self.assertEqual(settings.ai_blend, 0.25)
        self.assertEqual(settings.ai_mood_cost, 7)
        self.assertFalse(settings.featuring_is_same_artist)

    def test_garbage_env_reads_as_default(self):
        settings = self._settings(
            ["flow", "--library", "x"],
            {
                "SETER_ARTIST_SPACING": "abc",
                "SETER_FLOW_SIZE": "12.5",
                "SETER_FLOW_POOL_MAX": "",
                "SETER_REDISCOVER_SIZE": "many",
                "SETER_AI_BLEND": "high",
                "SETER_AI_MOOD_COST": "loud",
            },
        )
        base = Settings()
        self.assertEqual(settings.artist_spacing, base.artist_spacing)
        self.assertEqual(settings.flow_size, base.flow_size)
        self.assertEqual(settings.flow_pool_max, base.flow_pool_max)
        self.assertEqual(settings.rediscover_min, base.rediscover_min)
        self.assertEqual(settings.ai_blend, base.ai_blend)
        self.assertEqual(settings.ai_mood_cost, base.ai_mood_cost)

    def test_out_of_range_env_clamps(self):
        settings = self._settings(
            ["flow", "--library", "x"],
            {
                "SETER_ARTIST_SPACING": "99",
                "SETER_FLOW_SIZE": "1",
                "SETER_FLOW_POOL_MAX": "5000",
                "SETER_REDISCOVER_SIZE": "1",
                "SETER_REDISCOVER_STALE_DAYS": "9999",
                "SETER_AI_BLEND": "2.5",
                "SETER_AI_MOOD_COST": "-3",
            },
        )
        self.assertEqual(settings.artist_spacing, 5)
        self.assertEqual(settings.flow_size, 10)
        self.assertEqual(settings.flow_pool_max, 1000)
        self.assertEqual(settings.rediscover_min, 5)
        self.assertEqual(settings.stale_days, 365)
        self.assertEqual(settings.ai_blend, 1.0)
        self.assertEqual(settings.ai_mood_cost, 0)

    def test_flags_win_over_env(self):
        settings = self._settings(
            [
                "flow", "--library", "x",
                "--flow-size", "42",
                "--artist-spacing", "1",
                "--ai-blend", "0.1",
                "--no-featuring-same-artist",
            ],
            {
                "SETER_FLOW_SIZE": "120",
                "SETER_ARTIST_SPACING": "4",
                "SETER_AI_BLEND": "0.9",
                "SETER_FEATURING_SAME_ARTIST": "1",
            },
        )
        self.assertEqual(settings.flow_size, 42)
        self.assertEqual(settings.artist_spacing, 1)
        self.assertEqual(settings.ai_blend, 0.1)
        self.assertFalse(settings.featuring_is_same_artist)

    def test_featuring_flags(self):
        on = self._settings(
            ["flow", "--library", "x", "--featuring-same-artist"]
        )
        self.assertTrue(on.featuring_is_same_artist)
        off = self._settings(
            ["flow", "--library", "x", "--no-featuring-same-artist"]
        )
        self.assertFalse(off.featuring_is_same_artist)
        # Env off, flag on: the flag wins.
        env_off_flag_on = self._settings(
            ["flow", "--library", "x", "--featuring-same-artist"],
            {"SETER_FEATURING_SAME_ARTIST": "0"},
        )
        self.assertTrue(env_off_flag_on.featuring_is_same_artist)

    def test_defaults_unchanged_without_env_or_flags(self):
        # A bare environment: no SETER_* vars at all (other env
        # vars, e.g. HOME, stay so the CLI can still resolve
        # its paths).
        bare_env = {
            key: value
            for key, value in os.environ.items()
            if not key.startswith("SETER_")
        }
        with mock.patch.dict(os.environ, bare_env, clear=True):
            args = build_parser().parse_args(["flow", "--library", "x"])
            settings = _settings_from(args)
        self.assertEqual(settings, Settings())


class BannerColorTests(unittest.TestCase):
    def _run_sh(self, args, stdin, tmp, extra_env=None):
        env = dict(os.environ)
        env["HOME"] = str(tmp)
        env["SETER_AI_DIR"] = str(tmp)
        if extra_env:
            env.update(extra_env)
        return subprocess.run(
            ["bash", str(RUN_SH)] + args,
            input=stdin,
            capture_output=True,
            text=True,
            timeout=30,
            env=env,
        )

    def test_banner_plain_when_colors_unset(self):
        with tempfile.TemporaryDirectory() as tmp:
            out, err, rc = _run_full_script(
                "print_banner\n", "", Path(tmp)
            )
            self.assertEqual(rc, 0, err)
            self.assertNotIn("\x1b", out)
            # Spencer's art, byte for byte: distinctive lines from
            # both blocks (his SeTeR.txt and SHUFFLE.txt).
            self.assertIn("▄█▀▀▀█▄█", out)
            self.assertIn("█▀█████▀  ▀█████▀", out)
            self.assertIn("▄█▀▀▀█▄█████▀", out)
            self.assertIn("█▀█████▀▄████▄", out)
            self.assertNotIn("S H U F F L E", out)
            self.assertIn("v3.5", out)

    def test_banner_italic_escape_when_colors_set(self):
        colors = (
            "C_BOLD_CYAN=$'\\033[1;36m'\n"
            "C_BOLD_MAGENTA=$'\\033[1;35m'\n"
            "C_RESET=$'\\033[0m'\n"
            "C_ITALIC=$'\\033[3m'\n"
            "C_ITALIC_OFF=$'\\033[23m'\n"
            "C_DIM=$'\\033[2m'\n"
        )
        with tempfile.TemporaryDirectory() as tmp:
            out, err, rc = _run_full_script(
                colors + "print_banner\n", "", Path(tmp)
            )
            self.assertEqual(rc, 0, err)
            self.assertIn("\x1b[3m", out)
            self.assertIn("\x1b[23m", out)
            self.assertIn("\x1b[1;36m", out)
            self.assertIn("\x1b[1;35m", out)
            self.assertIn("▄█▀▀▀█▄█", out)
            self.assertIn("▄█▀▀▀█▄█████▀", out)
            self.assertNotIn("S H U F F L E", out)

    def test_menu_piped_has_no_escape_bytes(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc = self._run_sh(["menu"], "0\n", Path(tmp))
            self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
            self.assertNotIn("\x1b", proc.stdout)
            self.assertIn("SeTeR Shuffle", proc.stdout)
            self.assertIn("8) Options", proc.stdout)
            self.assertIn("▄█▀▀▀█▄█████▀", proc.stdout)

    def test_menu_under_pty_has_banner_and_italic(self):
        if shutil.which("script") is None:
            self.skipTest("no script(1) for a pty")
        with tempfile.TemporaryDirectory() as tmp:
            env = dict(os.environ)
            env["HOME"] = str(tmp)
            env["SETER_AI_DIR"] = str(tmp)
            proc = subprocess.run(
                ["script", "-qec", f"bash {RUN_SH} menu", "/dev/null"],
                input="0\n",
                capture_output=True,
                text=True,
                timeout=30,
                env=env,
            )
            self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
            self.assertIn("\x1b[3m", proc.stdout)
            self.assertIn("\x1b[1;35m", proc.stdout)
            self.assertIn("▄█▀▀▀█▄█████▀", proc.stdout)
            self.assertIn("▄█▀▀▀█▄█", proc.stdout)
            self.assertIn("SeTeR Shuffle", proc.stdout)
            self.assertIn("8) Options", proc.stdout)

    def test_subcommand_output_stays_plain(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc = self._run_sh(["nonsense"], "", Path(tmp))
            self.assertEqual(proc.returncode, 2)
            self.assertNotIn("\x1b", proc.stderr)


class FullOptionsWiringTests(unittest.TestCase):
    def test_all_new_settings_have_loader_and_menu_entries(self):
        for env_var in (
            "SETER_AI_BLEND",
            "SETER_AI_MOOD_COST",
            "SETER_FLOW_SIZE",
            "SETER_FLOW_POOL_MAX",
            "SETER_ARTIST_SPACING",
            "SETER_REDISCOVER_SIZE",
            "SETER_REDISCOVER_MAX_PER_ARTIST",
            "SETER_REDISCOVER_COOLDOWN_DAYS",
            "SETER_REDISCOVER_STALE_DAYS",
            "SETER_FEATURING_SAME_ARTIST",
            "SETER_DEDUPE_MATCH",
        ):
            self.assertIn(env_var, RUN_TEXT)
        for marker in (
            "OPTIONS_AI_BLEND_ENV_SET",
            "OPTIONS_FLOW_SIZE_ENV_SET",
            "OPTIONS_FEATURING_ENV_SET",
            "OPTIONS_DEDUPE_ENV_SET",
        ):
            self.assertIn(marker, RUN_TEXT)
        # The loader runs before dispatch, so direct commands,
        # menu children, and daily children all see it.
        lines = RUN_TEXT.splitlines()
        call_at = next(
            i for i, line in enumerate(lines) if line == "load_persisted_options"
        )
        dispatch_at = next(
            i for i, line in enumerate(lines) if "[ $# -eq 0 ]" in line
        )
        self.assertLess(call_at, dispatch_at)

    def test_banner_printed_by_main_menu_only(self):
        menu = RUN_TEXT.split('if [ "$CMD" = "menu" ]')[1].split(
            "# Sort-probe command"
        )[0]
        self.assertIn("print_banner", menu)
        # No other command path prints the banner: it appears
        # exactly twice in the file (definition + menu call).
        self.assertEqual(RUN_TEXT.count("print_banner"), 2)

    def test_no_new_empty_array_expansions(self):
        expansions = [line for line in RUN_TEXT.splitlines() if "[@]" in line]
        self.assertEqual(len(expansions), 1)
        self.assertIn("apply_args[@]", expansions[0])


if __name__ == "__main__":
    unittest.main()
