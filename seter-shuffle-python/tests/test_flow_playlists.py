"""Tests for the v3.0.11 exp 2026-11-20.5 Flow playlist settings: the
Flow source pool (whole library or one named playlist) and the Flow
target playlist are configurable, in menu Options (choice 8, entries
4 and 5), in SETER_FLOW_SOURCE / SETER_FLOW_TARGET, and in the
flow-source-playlist / flow-target-playlist files under the
SeTeRShuffle settings dir. Defaults stay exactly as before: whole
library into "SeTeR Flow".

Design, so the tests pin the right contract:

  * The source pool is the whole library unless SETER_FLOW_SOURCE
    names a playlist; the file holds a playlist name or the literal
    word "library" (any case); absent file = library. A bad file
    (empty, or only whitespace) reads as the default, never as a
    blank playlist name. Playlist names keep their spaces.
  * The target is "SeTeR Flow" unless SETER_FLOW_TARGET names a
    playlist; the file holds a playlist name; absent file =
    "SeTeR Flow". A bad file reads as the default.
  * An env var already set wins over the file, and the menu says
    so instead of pretending a change took effect (same rule as
    probe max age / split collabs).
  * The Options entries pick from the numbered playlist list
    (menu_pick_playlist), so a mistyped name can never point Flow
    at a playlist that does not exist. The source picker also
    offers whole Library as an explicit choice, and typing
    "library" selects it. An empty name is rejected and the old
    value kept. 0 returns to the submenu without quitting the menu.
  * The daily run resolves the same settings from the same files
    (load_flow_settings, mirroring load_probe_max_age): it probes
    and checks the configured target, and its dry-run log line
    names the configured source and target. The flow step stays
    `run.sh flow`, and run.sh resolves the same settings, so daily
    and menu agree.
  * The flow branch probes/applies the configured target and
    passes --playlist "$TARGET" to the CLI, so the order payload
    label matches the real target. flowPreview follows the same
    source and label, and changes nothing.
  * Safety is unchanged: a flow order is unique by construction
    (the CLI loads the pool with duplicates refused and emits each
    song once), so a doubled source playlist fails the compute
    closed before any apply, and apply_order forces allow_dupes
    "0" for flow the same way dedupe already forces it — the
    doubled-source path must not loosen the bridge's check.

No Mac is involved: SETER_AI_DIR is the test hook for the
settings dir, and the menu tests extract the shell functions
from run.sh and run them with bash -c, the same pattern as
test_menu_options.py. The daily tests reuse the stub-run.sh
harness from test_selfprobe.py.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUN_SH = ROOT / "run.sh"
DAILY_SH = ROOT / "daily.sh"
RUN_TEXT = RUN_SH.read_text()
DAILY_TEXT = DAILY_SH.read_text()
FIXTURE = ROOT / "tests" / "fixtures" / "sample-library.json"

sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "tests"))

import test_selfprobe as _selfprobe  # noqa: E402  (harness for the daily tests)
from test_menu_options import DailyProbeAgeFileTests  # noqa: E402


def _function_lines(text, name):
    lines = text.splitlines()
    start = next(
        i for i, line in enumerate(lines) if line.startswith(name + "() {")
    )
    end = next(i for i in range(start + 1, len(lines)) if lines[i] == "}")
    return lines[start : end + 1]


FLOW_FUNCS = [
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
    "load_persisted_options",
    "menu_pick_playlist",
    "menu_options",
]

FLOW_LIB = "\n".join(
    "\n".join(_function_lines(RUN_TEXT, name)) for name in FLOW_FUNCS
)


def _run_flow_script(tail, stdin, tmp, extra_env=None, list_names=None):
    """Run extracted run.sh Flow-option functions with a temp settings dir.

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
        + FLOW_LIB
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


def _state(tail, tmp, extra_env=None):
    return _run_flow_script(tail, "", Path(tmp), extra_env=extra_env)


class FlowSettingsTests(unittest.TestCase):
    def test_defaults_no_env_no_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            out, err, rc = _state(
                'printf "SRC=[%s] TGT=[%s]\\n" "$(options_flow_source)" "$(options_flow_target)"\n',
                tmp,
            )
            self.assertEqual(rc, 0, err)
            self.assertIn("SRC=[library] TGT=[SeTeR Flow]", out)

    def test_files_fallback(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            (tmp / "flow-source-playlist").write_text(
                "My New Sandwich Recipe\n", encoding="utf-8"
            )
            (tmp / "flow-target-playlist").write_text("My Flow\n", encoding="utf-8")
            out, err, rc = _state(
                'printf "SRC=[%s] TGT=[%s]\\n" "$(options_flow_source)" "$(options_flow_target)"\n',
                tmp,
            )
            self.assertEqual(rc, 0, err)
            self.assertIn("SRC=[My New Sandwich Recipe] TGT=[My Flow]", out)

    def test_env_wins_over_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            (tmp / "flow-source-playlist").write_text("File Source\n", encoding="utf-8")
            (tmp / "flow-target-playlist").write_text("File Target\n", encoding="utf-8")
            out, err, rc = _state(
                'load_persisted_options\n'
                'printf "SRC=[%s] TGT=[%s] SENV=[%s] TENV=[%s]\\n" '
                '"$(options_flow_source)" "$(options_flow_target)" '
                '"${OPTIONS_FLOW_SOURCE_ENV_SET:-unset}" "${OPTIONS_FLOW_TARGET_ENV_SET:-unset}"\n',
                tmp,
                extra_env={
                    "SETER_FLOW_SOURCE": "Env Source",
                    "SETER_FLOW_TARGET": "Env Target",
                },
            )
            self.assertEqual(rc, 0, err)
            self.assertIn(
                "SRC=[Env Source] TGT=[Env Target] SENV=[1] TENV=[1]", out
            )

    def test_library_value_in_env_and_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            for value in ("library", "Library", "LIBRARY", "LiBrArY"):
                (tmp / "flow-source-playlist").write_text(
                    value + "\n", encoding="utf-8"
                )
                out, err, rc = _state(
                    'printf "SRC=[%s]\\n" "$(options_flow_source)"\n', tmp
                )
                self.assertEqual(rc, 0, err)
                self.assertIn("SRC=[library]", out, value)
            out, _, rc = _state(
                'printf "SRC=[%s]\\n" "$(options_flow_source)"\n',
                tmp,
                extra_env={"SETER_FLOW_SOURCE": "Library"},
            )
            self.assertEqual(rc, 0)
            self.assertIn("SRC=[library]", out)

    def test_bad_files_fall_back_to_defaults(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            (tmp / "flow-source-playlist").write_text("", encoding="utf-8")
            (tmp / "flow-target-playlist").write_text("", encoding="utf-8")
            out, err, rc = _state(
                'printf "SRC=[%s] TGT=[%s]\\n" "$(options_flow_source)" "$(options_flow_target)"\n',
                tmp,
            )
            self.assertEqual(rc, 0, err)
            self.assertIn("SRC=[library] TGT=[SeTeR Flow]", out)
            (tmp / "flow-source-playlist").write_text("   \n", encoding="utf-8")
            (tmp / "flow-target-playlist").write_text("  \t \n", encoding="utf-8")
            out, _, rc = _state(
                'printf "SRC=[%s] TGT=[%s]\\n" "$(options_flow_source)" "$(options_flow_target)"\n',
                tmp,
            )
            self.assertEqual(rc, 0)
            self.assertIn("SRC=[library] TGT=[SeTeR Flow]", out)

    def test_names_keep_spaces_trailing_space_stripped(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            (tmp / "flow-source-playlist").write_text(
                "My  Flow   Playlist   \n", encoding="utf-8"
            )
            (tmp / "flow-target-playlist").write_text(
                "My Flow Playlist   \n", encoding="utf-8"
            )
            out, err, rc = _state(
                'printf "SRC=[%s] TGT=[%s]\\n" "$(options_flow_source)" "$(options_flow_target)"\n',
                tmp,
            )
            self.assertEqual(rc, 0, err)
            self.assertIn("SRC=[My  Flow   Playlist] TGT=[My Flow Playlist]", out)

    def test_loader_exports_from_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            # No files, no env: the loader exports the defaults.
            out, err, rc = _state(
                'load_persisted_options\n'
                'printf "SRC=[%s] TGT=[%s]\\n" "${SETER_FLOW_SOURCE:-unset}" "${SETER_FLOW_TARGET:-unset}"\n',
                tmp,
            )
            self.assertEqual(rc, 0, err)
            self.assertIn("SRC=[library] TGT=[SeTeR Flow]", out)
            # Files present: the loader exports the file values.
            (tmp / "flow-source-playlist").write_text(
                "My New Sandwich Recipe\n", encoding="utf-8"
            )
            (tmp / "flow-target-playlist").write_text("My Flow\n", encoding="utf-8")
            out, _, rc = _state(
                'load_persisted_options\n'
                'printf "SRC=[%s] TGT=[%s]\\n" "${SETER_FLOW_SOURCE:-unset}" "${SETER_FLOW_TARGET:-unset}"\n',
                tmp,
            )
            self.assertEqual(rc, 0)
            self.assertIn("SRC=[My New Sandwich Recipe] TGT=[My Flow]", out)

    def test_setters_write_files_and_keep_env_in_step(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            out, err, rc = _state(
                'options_set_flow_source "Picked Name"\n'
                'options_set_flow_target "My Flow"\n'
                'printf "SRC=[%s] TGT=[%s]\\n" "$SETER_FLOW_SOURCE" "$SETER_FLOW_TARGET"\n',
                tmp,
            )
            self.assertEqual(rc, 0, err)
            self.assertIn("SRC=[Picked Name] TGT=[My Flow]", out)
            self.assertEqual(
                (tmp / "flow-source-playlist").read_text(encoding="utf-8"),
                "Picked Name\n",
            )
            self.assertEqual(
                (tmp / "flow-target-playlist").read_text(encoding="utf-8"),
                "My Flow\n",
            )
            # No stray temp file left behind.
            self.assertEqual(
                [p.name for p in tmp.iterdir() if p.name.startswith(".flow-")], []
            )
            # Writing "library" stores the literal word, and the
            # loader then reads it as the whole library.
            out, _, rc = _state(
                'options_set_flow_source library\n'
                'printf "SRC=[%s]\\n" "$(options_flow_source)"\n',
                tmp,
            )
            self.assertEqual(rc, 0)
            self.assertIn("SRC=[library]", out)
            self.assertEqual(
                (tmp / "flow-source-playlist").read_text(encoding="utf-8"),
                "library\n",
            )


class MenuFlowOptionsTests(unittest.TestCase):
    def test_submenu_shows_flow_values_by_default(self):
        with tempfile.TemporaryDirectory() as tmp:
            out, err, rc = _run_flow_script("menu_options\n", "0\n", Path(tmp))
            self.assertEqual(rc, 0, err)
            self.assertIn("Flow source: Whole library", out)
            self.assertIn("Flow target: SeTeR Flow", out)
            self.assertIn("4) Set Flow source playlist", out)
            self.assertIn("5) Set Flow target playlist", out)

    def test_submenu_shows_flow_values_from_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            (tmp / "flow-source-playlist").write_text(
                "My New Sandwich Recipe\n", encoding="utf-8"
            )
            (tmp / "flow-target-playlist").write_text("My Flow\n", encoding="utf-8")
            out, err, rc = _run_flow_script("menu_options\n", "0\n", tmp)
            self.assertEqual(rc, 0, err)
            self.assertIn("Flow source: My New Sandwich Recipe", out)
            self.assertIn("Flow target: My Flow", out)

    def test_submenu_set_source_via_numbered_picker(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            out, err, rc = _run_flow_script(
                "menu_options\n",
                "4\n2\n0\n",
                tmp,
                list_names=["Alpha", "My New Sandwich Recipe", "Gamma"],
            )
            self.assertEqual(rc, 0, err)
            self.assertIn("  2) My New Sandwich Recipe", out)
            self.assertIn('Flow source is now "My New Sandwich Recipe".', out)
            self.assertIn("Flow source: My New Sandwich Recipe", out)
            self.assertEqual(
                (tmp / "flow-source-playlist").read_text(encoding="utf-8"),
                "My New Sandwich Recipe\n",
            )

    def test_submenu_set_source_via_library_choice(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            (tmp / "flow-source-playlist").write_text("Alpha\n", encoding="utf-8")
            out, err, rc = _run_flow_script(
                "menu_options\n",
                "4\nL\n0\n",
                tmp,
                list_names=["Alpha", "Beta"],
            )
            self.assertEqual(rc, 0, err)
            self.assertIn("  L) Whole library (Flow pool)", out)
            self.assertIn("Flow source is now the whole library.", out)
            self.assertIn("Flow source: Whole library", out)
            self.assertEqual(
                (tmp / "flow-source-playlist").read_text(encoding="utf-8"),
                "library\n",
            )

    def test_submenu_set_source_by_typing_library(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            (tmp / "flow-source-playlist").write_text("Alpha\n", encoding="utf-8")
            out, err, rc = _run_flow_script(
                "menu_options\n",
                "4\n0\nlibrary\n0\n",
                tmp,
                list_names=["Alpha"],
            )
            self.assertEqual(rc, 0, err)
            self.assertIn("Flow source is now the whole library.", out)
            self.assertEqual(
                (tmp / "flow-source-playlist").read_text(encoding="utf-8"),
                "library\n",
            )

    def test_submenu_set_source_rejects_empty_name(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            out, err, rc = _run_flow_script(
                "menu_options\n",
                "4\n0\n\n0\n",
                tmp,
                list_names=["Alpha"],
            )
            self.assertEqual(rc, 0, err)
            self.assertIn("empty name; Flow source unchanged.", out)
            self.assertFalse((tmp / "flow-source-playlist").exists())

    def test_submenu_set_target_via_numbered_picker(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            out, err, rc = _run_flow_script(
                "menu_options\n",
                "5\n1\n0\n",
                tmp,
                list_names=["My Flow", "Other"],
            )
            self.assertEqual(rc, 0, err)
            self.assertIn("  1) My Flow", out)
            self.assertNotIn("Whole library (Flow pool)", out)
            self.assertIn('Flow target is now "My Flow".', out)
            self.assertIn("Flow target: My Flow", out)
            self.assertEqual(
                (tmp / "flow-target-playlist").read_text(encoding="utf-8"),
                "My Flow\n",
            )

    def test_submenu_set_target_rejects_empty_name(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            out, err, rc = _run_flow_script(
                "menu_options\n",
                "5\n0\n\n0\n",
                tmp,
                list_names=["My Flow"],
            )
            self.assertEqual(rc, 0, err)
            self.assertIn("empty name; Flow target unchanged.", out)
            self.assertFalse((tmp / "flow-target-playlist").exists())

    def test_submenu_env_override_is_reported_not_pretended(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            out, err, rc = _run_flow_script(
                "load_persisted_options\nmenu_options\n",
                "4\n5\n0\n",
                tmp,
                extra_env={
                    "SETER_FLOW_SOURCE": "Env Source",
                    "SETER_FLOW_TARGET": "Env Target",
                },
            )
            self.assertEqual(rc, 0, err)
            self.assertIn("Flow source: Env Source", out)
            self.assertIn("Flow target: Env Target", out)
            self.assertIn("SETER_FLOW_SOURCE=Env Source in the environment", out)
            self.assertIn("SETER_FLOW_TARGET=Env Target in the environment", out)
            self.assertNotIn("Flow source is now", out)
            self.assertNotIn("Flow target is now", out)
            self.assertFalse((tmp / "flow-source-playlist").exists())
            self.assertFalse((tmp / "flow-target-playlist").exists())

    def test_submenu_quit_returns_without_quitting(self):
        # Choosing 4 or 5 and then 0 returns to the caller, and
        # the submenu re-prints its header after each choice.
        with tempfile.TemporaryDirectory() as tmp:
            out, err, rc = _run_flow_script(
                "menu_options\nprintf 'BACK-IN-CALLER\\n'\n",
                "4\n0\n\n0\n",
                Path(tmp),
                list_names=["Alpha"],
            )
            self.assertEqual(rc, 0, err)
            self.assertIn("BACK-IN-CALLER", out)
            self.assertGreaterEqual(out.count("4) Set Flow source playlist"), 2)


class CliFlowPlaylistLabelTests(unittest.TestCase):
    def run_cli(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, "-m", "seter_shuffle.cli", *args],
            cwd=ROOT, capture_output=True, text=True, check=False,
        )

    def test_flow_playlist_label_in_payload(self):
        with tempfile.TemporaryDirectory() as tmp:
            out_path = Path(tmp) / "order.json"
            txt_path = Path(tmp) / "order.txt"
            result = self.run_cli(
                "flow", "--library", str(FIXTURE), "--seed", "42",
                "--out", str(out_path), "--order-txt", str(txt_path),
                "--playlist", "My Custom Flow",
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            payload = json.loads(out_path.read_text(encoding="utf-8"))
            self.assertEqual(payload["command"], "flow")
            self.assertEqual(payload["playlist"], "My Custom Flow")
            self.assertEqual(payload["count"], len(payload["ids"]))
            self.assertEqual(len(payload["ids"]), len(set(payload["ids"])))

    def test_flow_preview_playlist_label_in_payload(self):
        with tempfile.TemporaryDirectory() as tmp:
            out_path = Path(tmp) / "order.json"
            txt_path = Path(tmp) / "order.txt"
            result = self.run_cli(
                "flowPreview", "--library", str(FIXTURE), "--seed", "42",
                "--out", str(out_path), "--order-txt", str(txt_path),
                "--playlist", "My Custom Flow",
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            payload = json.loads(out_path.read_text(encoding="utf-8"))
            self.assertEqual(payload["command"], "flowPreview")
            self.assertEqual(payload["playlist"], "My Custom Flow")

    def test_flow_default_label_is_seter_flow(self):
        with tempfile.TemporaryDirectory() as tmp:
            out_path = Path(tmp) / "order.json"
            txt_path = Path(tmp) / "order.txt"
            result = self.run_cli(
                "flow", "--library", str(FIXTURE), "--seed", "42",
                "--out", str(out_path), "--order-txt", str(txt_path),
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            payload = json.loads(out_path.read_text(encoding="utf-8"))
            self.assertEqual(payload["playlist"], "SeTeR Flow")


class FlowWiringTests(unittest.TestCase):
    def test_flow_branch_probes_configured_target(self):
        self.assertIn('flow) ensure_mapping_for "$(options_flow_target)"', RUN_TEXT)

    def test_menu_flow_choice_probes_configured_target(self):
        menu = RUN_TEXT.split('if [ "$CMD" = "menu" ]')[1].split(
            "# Sort-probe command"
        )[0]
        choice5 = menu.split("      5)")[1].split("      6)")[0]
        self.assertIn('ensure_mapping_for "$(options_flow_target)"', choice5)
        self.assertIn('bash "$ROOT/run.sh" flow ||', choice5)

    def test_flow_dump_uses_configured_source(self):
        self.assertIn(
            'elif { [ "$CMD" = "flow" ] || [ "$CMD" = "flowPreview" ]; } && [ "$(options_flow_source)" != "library" ]; then',
            RUN_TEXT,
        )
        self.assertIn(
            'step "dump playlist $SOURCE_PLAYLIST for flow" osascript "$BRIDGE/dump-library.applescript" "$DUMP" "$SOURCE_PLAYLIST"',
            RUN_TEXT,
        )

    def test_flow_compute_passes_target_label(self):
        flow = RUN_TEXT.split("  flow)\n")[1].split("  shuffle)")[0]
        self.assertIn('TARGET_PLAYLIST="$(options_flow_target)"', flow)
        self.assertIn('--playlist "$TARGET_PLAYLIST"', flow)
        preview = RUN_TEXT.split("  flowPreview)\n")[1].split("  flow)")[0]
        self.assertIn('--playlist "$(options_flow_target)"', preview)

    def test_flow_allow_dupes_forced_zero(self):
        # A doubled source playlist must not loosen the bridge's
        # duplicate check for flow: the force sits next to the
        # dedupe force in apply_order_mapped.
        self.assertIn(
            'if [ "$mode" = "dedupe" ] || [ "$mode" = "flow" ]; then',
            RUN_TEXT,
        )
        section = RUN_TEXT.split("if [ \"$mode\" = \"dedupe\" ]")[1].split(
            "stamp_flag="
        )[0]
        self.assertIn('allow_dupes="0"', section)

    def test_picker_offers_library_for_flow_source_only(self):
        self.assertIn(
            'elif [ "$mode" = "flow-source" ]; then',
            RUN_TEXT,
        )
        self.assertIn("  L) Whole library (Flow pool)", RUN_TEXT)
        self.assertIn(
            'if [ "$mode" = "shuffle" ] || [ "$mode" = "flow-source" ]; then',
            RUN_TEXT,
        )
        # The target picker has no library choice.
        picker = RUN_TEXT.split("menu_pick_playlist() {")[1].split(
            "# Options submenu"
        )[0]
        self.assertNotIn("flow-target", picker.split("L) Whole library")[0])
        self.assertEqual(picker.count("Whole library (Flow pool)"), 1)

    def test_daily_resolves_flow_settings(self):
        self.assertIn("load_flow_settings", DAILY_TEXT)
        self.assertIn("flow-target-playlist", DAILY_TEXT)
        self.assertIn("flow-source-playlist", DAILY_TEXT)
        self.assertIn('FLOW_SOURCE="$SETER_FLOW_SOURCE"', DAILY_TEXT)
        self.assertIn('FLOW_PLAYLIST="$SETER_FLOW_TARGET"', DAILY_TEXT)
        lines = DAILY_TEXT.splitlines()
        call_at = next(
            i for i, line in enumerate(lines) if line == "load_flow_settings"
        )
        assign_at = next(
            i
            for i, line in enumerate(lines)
            if line.startswith('FLOW_PLAYLIST="$SETER_FLOW_TARGET"')
        )
        self.assertLess(call_at, assign_at)
        # The dry-run log line names the configured source and target.
        self.assertIn(
            "flow (source $FLOW_SOURCE_LABEL, target '$FLOW_PLAYLIST')",
            DAILY_TEXT,
        )

    def test_loader_runs_before_dispatch(self):
        lines = RUN_TEXT.splitlines()
        call_at = next(
            i for i, line in enumerate(lines) if line == "load_persisted_options"
        )
        dispatch_at = next(
            i for i, line in enumerate(lines) if "[ $# -eq 0 ]" in line
        )
        self.assertLess(call_at, dispatch_at)

    def test_no_new_empty_array_expansions(self):
        expansions = [line for line in RUN_TEXT.splitlines() if "[@]" in line]
        self.assertEqual(len(expansions), 1)
        self.assertIn("apply_args[@]", expansions[0])


class DailyFlowSettingsTests(DailyProbeAgeFileTests):
    def test_dry_run_names_configured_source_and_target(self):
        for target in (
            "My New Sandwich Recipe",
            "SeTeR Rediscover",
            "My Custom Flow",
        ):
            self.write_mapping(target, 1)
        (self.settings / "flow-target-playlist").write_text(
            "My Custom Flow\n", encoding="utf-8"
        )
        (self.settings / "flow-source-playlist").write_text(
            "My New Sandwich Recipe\n", encoding="utf-8"
        )
        result = self.run_daily(
            {
                "SETER_AI_DIR": str(self.settings),
                "SETER_DAILY_DRY_RUN": "1",
            }
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        combined = result.stdout + result.stderr
        self.assertIn("planned probes: 'My New Sandwich Recipe', 'SeTeR Rediscover', 'My Custom Flow'", combined)
        self.assertIn(
            "flow (source 'My New Sandwich Recipe', target 'My Custom Flow')",
            combined,
        )

    def test_dry_run_defaults_are_library_and_seter_flow(self):
        for target in (
            "My New Sandwich Recipe",
            "SeTeR Rediscover",
            "SeTeR Flow",
        ):
            self.write_mapping(target, 1)
        result = self.run_daily(
            {
                "SETER_AI_DIR": str(self.settings),
                "SETER_DAILY_DRY_RUN": "1",
            }
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        combined = result.stdout + result.stderr
        self.assertIn("planned probes: 'My New Sandwich Recipe', 'SeTeR Rediscover', 'SeTeR Flow'", combined)
        self.assertIn(
            "flow (source whole library, target 'SeTeR Flow')", combined
        )

    def test_dry_run_source_library_file_means_library(self):
        for target in (
            "My New Sandwich Recipe",
            "SeTeR Rediscover",
            "SeTeR Flow",
        ):
            self.write_mapping(target, 1)
        (self.settings / "flow-source-playlist").write_text(
            "library\n", encoding="utf-8"
        )
        result = self.run_daily(
            {
                "SETER_AI_DIR": str(self.settings),
                "SETER_DAILY_DRY_RUN": "1",
            }
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(
            "flow (source whole library, target 'SeTeR Flow')",
            result.stdout + result.stderr,
        )

    def test_flow_target_env_wins_over_file(self):
        for target in (
            "My New Sandwich Recipe",
            "SeTeR Rediscover",
            "Env Flow",
        ):
            self.write_mapping(target, 1)
        (self.settings / "flow-target-playlist").write_text(
            "File Flow\n", encoding="utf-8"
        )
        result = self.run_daily(
            {
                "SETER_AI_DIR": str(self.settings),
                "SETER_DAILY_DRY_RUN": "1",
                "SETER_FLOW_TARGET": "Env Flow",
            }
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        combined = result.stdout + result.stderr
        self.assertIn("planned probes: 'My New Sandwich Recipe', 'SeTeR Rediscover', 'Env Flow'", combined)
        self.assertNotIn("File Flow", combined)

    def test_flow_target_file_drives_probe_calls(self):
        # A non-dry run probes the configured target (the stub
        # run.sh records the selfprobe calls and writes fresh
        # mappings), not "SeTeR Flow".
        (self.settings / "flow-target-playlist").write_text(
            "My Custom Flow\n", encoding="utf-8"
        )
        result = self.run_daily({"SETER_AI_DIR": str(self.settings)})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = self.calls.read_text(encoding="utf-8").splitlines()
        self.assertIn("selfprobe My Custom Flow", calls)
        self.assertNotIn("selfprobe SeTeR Flow", calls)
        self.assertIn("flow", calls)


if __name__ == "__main__":
    unittest.main()
