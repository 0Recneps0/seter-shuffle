"""Tests for the v3.0.11 exp 2026-11-20.3 menu changes: bare ./run.sh
opens the menu, and the menu has an Options submenu (AI tagging,
split collabs, probe max age) persisted in small files under the
SeTeRShuffle settings dir.

Design, so the tests pin the right contract:

  * Bare ./run.sh opens the interactive menu only when stdin is a
    terminal. With piped or redirected stdin it keeps the old
    behaviour (usage to stderr, exit 2), so a bare run in a script
    or launchd job can never hang waiting for input nobody will
    type. Every named subcommand works exactly as before.
  * The options persist in three small files under the settings
    dir (${SETER_AI_DIR:-$HOME/Documents/SeTeRShuffle}, the same
    dir the AI marker and tag cache already use):
      ai-enabled             empty marker: AI tagging for Flow is on
      split-collabs-enabled  empty marker: "A & B" counts as artist "A"
      probe-max-age-hours    one number 0-40: the daily run skips a
                             target's self-probe while its mapping is
                             younger than N hours (0 = probe every day)
    The Python CLI already reads the AI marker itself and
    SETER_SPLIT_COLLABS, so run.sh only has to turn the
    split-collabs marker into that env var (load_persisted_options),
    and daily.sh only has to read the probe-age file
    (load_probe_max_age). An env var already set wins over the
    file, and the menu says so instead of pretending a toggle
    took effect.
  * No Mac is involved: SETER_AI_DIR is the test hook for the
    settings dir, and the menu tests extract the shell functions
    from run.sh and run them with bash -c, the same pattern as
    test_menu_picker.py. The daily tests reuse the stub-run.sh
    harness from test_selfprobe.py.

The options change nothing in Music and authorize nothing: AI
tagging only takes effect inside a later Flow compute (which
still needs sudo fm license once plus ai-selftest first),
split collabs only changes how the next shuffle/flow/rediscover
counts artists, and the probe age only changes how often the
daily run self-probes.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUN_SH = ROOT / "run.sh"
DAILY_SH = ROOT / "daily.sh"
RUN_TEXT = RUN_SH.read_text()
DAILY_TEXT = DAILY_SH.read_text()

sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "tests"))

import test_selfprobe as _selfprobe  # noqa: E402  (harness for the daily tests)


def _function_lines(text, name):
    lines = text.splitlines()
    start = next(
        i for i, line in enumerate(lines) if line.startswith(name + "() {")
    )
    end = next(i for i in range(start + 1, len(lines)) if lines[i] == "}")
    return lines[start : end + 1]


OPTION_FUNCS = [
    "options_dir",
    "options_ai_on",
    "options_ai_env_set",
    "options_set_ai",
    "options_split_collabs_on",
    "options_set_split_collabs",
    "options_probe_max_age",
    "options_write_probe_max_age",
    "load_persisted_options",
    "menu_options",
]

OPTIONS_LIB = "\n".join(
    "\n".join(_function_lines(RUN_TEXT, name)) for name in OPTION_FUNCS
)


def _run_options_script(tail, stdin, tmp, extra_env=None):
    """Run extracted run.sh option functions with a temp settings dir.

    Returns (stdout, stderr, returncode). The settings dir is tmp;
    SETER_AI_DIR points at it, HOME points at tmp too.
    """
    env = {
        "PATH": "/usr/bin:/bin",
        "HOME": str(tmp),
        "SETER_AI_DIR": str(tmp),
    }
    if extra_env:
        env.update(extra_env)
    script = "set -u\n" + OPTIONS_LIB + "\n" + tail
    proc = subprocess.run(
        ["bash", "-c", script],
        input=stdin,
        capture_output=True,
        text=True,
        timeout=30,
        env=env,
    )
    return proc.stdout, proc.stderr, proc.returncode


def _run_sh(args, stdin, tmp, extra_env=None):
    """Run the real run.sh with HOME and SETER_AI_DIR pointed at tmp."""
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


class OptionsStateTests(unittest.TestCase):
    def test_ai_off_by_default(self):
        with tempfile.TemporaryDirectory() as tmp:
            out, err, rc = _run_options_script(
                'if options_ai_on; then echo ON; else echo OFF; fi\n',
                "",
                Path(tmp),
            )
            self.assertEqual(rc, 0, err)
            self.assertIn("OFF", out)

    def test_ai_marker_turns_it_on(self):
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, "ai-enabled").touch()
            out, err, rc = _run_options_script(
                'if options_ai_on; then echo ON; else echo OFF; fi\n',
                "",
                Path(tmp),
            )
            self.assertEqual(rc, 0, err)
            self.assertIn("ON", out)

    def test_ai_env_wins_over_marker(self):
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, "ai-enabled").touch()
            out, err, rc = _run_options_script(
                'if options_ai_on; then echo ON; else echo OFF; fi\n',
                "",
                Path(tmp),
                extra_env={"SETER_AI": "0"},
            )
            self.assertEqual(rc, 0, err)
            self.assertIn("OFF", out)
            out, _, rc = _run_options_script(
                'if options_ai_env_set; then echo ENV; else echo FILE; fi\n',
                "",
                Path(tmp),
                extra_env={"SETER_AI": "0"},
            )
            self.assertEqual(rc, 0)
            self.assertIn("ENV", out)

    def test_ai_env_on_without_marker(self):
        with tempfile.TemporaryDirectory() as tmp:
            out, err, rc = _run_options_script(
                'if options_ai_on; then echo ON; else echo OFF; fi\n',
                "",
                Path(tmp),
                extra_env={"SETER_AI": "1"},
            )
            self.assertEqual(rc, 0, err)
            self.assertIn("ON", out)

    def test_ai_garbage_env_falls_through_to_marker(self):
        # Mirrors ai_enabled_by_environment: an unrecognized
        # SETER_AI value does not decide, the marker does.
        with tempfile.TemporaryDirectory() as tmp:
            out, err, rc = _run_options_script(
                'if options_ai_on; then echo ON; else echo OFF; fi\n',
                "",
                Path(tmp),
                extra_env={"SETER_AI": "maybe"},
            )
            self.assertEqual(rc, 0, err)
            self.assertIn("OFF", out)

    def test_split_collabs_marker_and_loader(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            # No marker, no env: off, and the loader exports nothing.
            out, err, rc = _run_options_script(
                'load_persisted_options\n'
                'if options_split_collabs_on; then echo ON; else echo OFF; fi\n'
                'printf "ENV=[%s]\\n" "${SETER_SPLIT_COLLABS:-unset}"\n',
                "",
                tmp,
            )
            self.assertEqual(rc, 0, err)
            self.assertIn("OFF", out)
            self.assertIn("ENV=[unset]", out)
            # Marker present: the loader exports SETER_SPLIT_COLLABS=1.
            (tmp / "split-collabs-enabled").touch()
            out, err, rc = _run_options_script(
                'load_persisted_options\n'
                'if options_split_collabs_on; then echo ON; else echo OFF; fi\n'
                'printf "ENV=[%s]\\n" "${SETER_SPLIT_COLLABS:-unset}"\n',
                "",
                tmp,
            )
            self.assertEqual(rc, 0, err)
            self.assertIn("ON", out)
            self.assertIn("ENV=[1]", out)

    def test_split_collabs_env_wins_over_marker(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            (tmp / "split-collabs-enabled").touch()
            out, err, rc = _run_options_script(
                'load_persisted_options\n'
                'if options_split_collabs_on; then echo ON; else echo OFF; fi\n'
                'printf "RECORDED=[%s]\\n" "${OPTIONS_SPLIT_ENV_SET:-unset}"\n',
                "",
                tmp,
                extra_env={"SETER_SPLIT_COLLABS": "0"},
            )
            self.assertEqual(rc, 0, err)
            self.assertIn("OFF", out)
            self.assertIn("RECORDED=[1]", out)

    def test_toggle_keeps_env_in_step_with_marker(self):
        # The stale-env trap: the loader exports 1 at startup from
        # the marker; toggling off must also clear the in-process
        # env, or a menu child would inherit a stale 1.
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            (tmp / "split-collabs-enabled").touch()
            out, err, rc = _run_options_script(
                'load_persisted_options\n'
                'options_set_split_collabs off\n'
                'printf "ENV=[%s] MARKER=" "${SETER_SPLIT_COLLABS:-unset}"\n'
                'if [ -f "$(options_dir)/split-collabs-enabled" ]; then echo yes; else echo no; fi\n'
                'load_persisted_options\n'
                'printf "AFTER-RELOAD ENV=[%s]\\n" "${SETER_SPLIT_COLLABS:-unset}"\n'
                'if options_split_collabs_on; then echo ON; else echo OFF; fi\n',
                "",
                tmp,
            )
            self.assertEqual(rc, 0, err)
            self.assertIn("ENV=[0] MARKER=no", out)
            self.assertIn("AFTER-RELOAD ENV=[0]", out)
            self.assertIn("OFF", out)

    def test_probe_max_age_defaults_and_clamps(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            out, err, rc = _run_options_script(
                'printf "AGE=[%s]\\n" "$(options_probe_max_age)"\n',
                "",
                tmp,
            )
            self.assertEqual(rc, 0, err)
            self.assertIn("AGE=[0]", out)
            (tmp / "probe-max-age-hours").write_text("12\n", encoding="utf-8")
            out, _, rc = _run_options_script(
                'printf "AGE=[%s]\\n" "$(options_probe_max_age)"\n',
                "",
                tmp,
            )
            self.assertEqual(rc, 0)
            self.assertIn("AGE=[12]", out)
            (tmp / "probe-max-age-hours").write_text("99\n", encoding="utf-8")
            out, _, rc = _run_options_script(
                'printf "AGE=[%s]\\n" "$(options_probe_max_age)"\n',
                "",
                tmp,
            )
            self.assertEqual(rc, 0)
            self.assertIn("AGE=[40]", out)
            (tmp / "probe-max-age-hours").write_text("abc\n", encoding="utf-8")
            out, _, rc = _run_options_script(
                'printf "AGE=[%s]\\n" "$(options_probe_max_age)"\n',
                "",
                tmp,
            )
            self.assertEqual(rc, 0)
            self.assertIn("AGE=[0]", out)

    def test_probe_max_age_write_is_atomic_and_replaces(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            (tmp / "probe-max-age-hours").write_text("12\n", encoding="utf-8")
            out, err, rc = _run_options_script(
                'options_write_probe_max_age 24\n'
                'printf "AGE=[%s]\\n" "$(options_probe_max_age)"\n',
                "",
                tmp,
            )
            self.assertEqual(rc, 0, err)
            self.assertIn("AGE=[24]", out)
            self.assertEqual(
                (tmp / "probe-max-age-hours").read_text(encoding="utf-8"), "24\n"
            )
            # No stray temp file left behind.
            self.assertEqual(
                [p.name for p in tmp.iterdir() if p.name.startswith(".probe")], []
            )


class MenuOptionsTests(unittest.TestCase):
    def test_submenu_toggles_and_sets_then_returns_to_menu(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            out, err, rc = _run_options_script(
                "menu_options\n",
                "1\n2\n3\n12\n0\n",
                tmp,
            )
            self.assertEqual(rc, 0, err)
            self.assertIn("AI tagging for Flow: OFF", out)
            self.assertIn("AI tagging is now ON.", out)
            self.assertIn("AI tagging for Flow: ON", out)
            self.assertIn("Split collabs is now ON", out)
            self.assertIn("Split collabs: ON", out)
            self.assertIn("Probe max age is now 12 hours.", out)
            self.assertIn("Probe max age: 12 hours", out)
            self.assertIn("sudo fm license once + ai-selftest", out)
            self.assertTrue((tmp / "ai-enabled").exists())
            self.assertTrue((tmp / "split-collabs-enabled").exists())
            self.assertEqual(
                (tmp / "probe-max-age-hours").read_text(encoding="utf-8"), "12\n"
            )

    def test_submenu_rejects_bad_probe_numbers_and_stays(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            out, err, rc = _run_options_script(
                "menu_options\n",
                "3\n41\n3\nabc\n3\n0\n0\n",
                tmp,
            )
            self.assertEqual(rc, 0, err)
            self.assertEqual(out.count("probe max age must be 0-40"), 1)
            self.assertEqual(out.count("not a number 0-40"), 1)
            self.assertIn("Probe max age is now 0 hours.", out)
            self.assertIn("Probe max age: 0 hours", out)
            # The submenu survived both bad inputs: it printed its
            # header again after each rejection.
            self.assertGreaterEqual(out.count("3) Set probe max age"), 3)

    def test_submenu_unknown_choice_stays_in_submenu(self):
        with tempfile.TemporaryDirectory() as tmp:
            out, err, rc = _run_options_script(
                "menu_options\n",
                "9\n0\n",
                Path(tmp),
            )
            self.assertEqual(rc, 0, err)
            self.assertIn("unknown choice: 9", out)
            self.assertGreaterEqual(out.count("1) Toggle AI tagging"), 2)

    def test_submenu_toggle_off_removes_markers(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            (tmp / "ai-enabled").touch()
            (tmp / "split-collabs-enabled").touch()
            out, err, rc = _run_options_script(
                "menu_options\n",
                "1\n2\n0\n",
                tmp,
            )
            self.assertEqual(rc, 0, err)
            self.assertIn("AI tagging is now OFF.", out)
            self.assertIn("Split collabs is now OFF.", out)
            self.assertFalse((tmp / "ai-enabled").exists())
            self.assertFalse((tmp / "split-collabs-enabled").exists())

    def test_submenu_env_override_is_reported_not_pretended(self):
        with tempfile.TemporaryDirectory() as tmp:
            # The real run.sh calls load_persisted_options at
            # startup, which records that the env was already
            # set; the extracted functions need the same call.
            out, err, rc = _run_options_script(
                "load_persisted_options\nmenu_options\n",
                "1\n2\n0\n",
                Path(tmp),
                extra_env={"SETER_AI": "1", "SETER_SPLIT_COLLABS": "0"},
            )
            self.assertEqual(rc, 0, err)
            self.assertIn("SETER_AI=1 in the environment", out)
            self.assertIn("SETER_SPLIT_COLLABS=0 in the environment", out)
            self.assertNotIn("AI tagging is now", out)
            self.assertNotIn("Split collabs is now", out)
            # Neither toggle wrote a marker file.
            self.assertFalse((Path(tmp) / "ai-enabled").exists())
            self.assertFalse((Path(tmp) / "split-collabs-enabled").exists())

    def test_submenu_quit_returns_without_quitting(self):
        # menu_options returning must hand control back to the
        # caller (the main menu loop), not exit the process:
        # the tail prints AFTER the submenu returns.
        with tempfile.TemporaryDirectory() as tmp:
            out, err, rc = _run_options_script(
                "menu_options\nprintf 'BACK-IN-CALLER\\n'\n",
                "0\n",
                Path(tmp),
            )
            self.assertEqual(rc, 0, err)
            self.assertIn("BACK-IN-CALLER", out)


class NoArgMenuTests(unittest.TestCase):
    def test_bare_run_with_piped_stdin_prints_usage_and_exits_2(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc = _run_sh([], "", Path(tmp))
            self.assertEqual(proc.returncode, 2)
            self.assertIn("usage:", proc.stderr)
            self.assertIn("no arguments in a terminal to open the menu", proc.stderr)

    def test_unknown_command_still_prints_usage_and_exits_2(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc = _run_sh(["nonsense"], "", Path(tmp))
            self.assertEqual(proc.returncode, 2)
            self.assertIn("usage:", proc.stderr)

    def test_explicit_menu_with_piped_stdin_still_works(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc = _run_sh(["menu"], "0\n", Path(tmp))
            self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
            self.assertIn("SeTeR Shuffle", proc.stdout)
            self.assertIn("8) Options", proc.stdout)

    def test_bare_run_with_tty_opens_menu(self):
        if shutil.which("script") is None:
            self.skipTest("no script(1) for a pty")
        with tempfile.TemporaryDirectory() as tmp:
            env = dict(os.environ)
            env["HOME"] = str(tmp)
            env["SETER_AI_DIR"] = str(tmp)
            proc = subprocess.run(
                ["script", "-qec", f"bash {RUN_SH}", "/dev/null"],
                input="0\n",
                capture_output=True,
                text=True,
                timeout=30,
                env=env,
            )
            self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
            self.assertIn("SeTeR Shuffle", proc.stdout)
            self.assertIn("8) Options", proc.stdout)
            self.assertNotIn("usage:", proc.stdout)

    def test_menu_options_entry_reaches_submenu(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc = _run_sh(["menu"], "8\n0\n0\n", Path(tmp))
            self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
            self.assertIn("AI tagging for Flow: OFF", proc.stdout)
            self.assertIn("Split collabs: OFF", proc.stdout)
            self.assertIn("Probe max age: 0 hours", proc.stdout)


class OptionsWiringTests(unittest.TestCase):
    def test_no_arg_dispatch_is_tty_gated(self):
        self.assertIn("[ $# -eq 0 ] && [ -t 0 ]", RUN_TEXT)
        self.assertIn('CMD="menu"', RUN_TEXT)
        # The old bare path (empty CMD falling into usage) is gone:
        # an empty $1 no longer reaches the usage case on a TTY.
        dispatch = RUN_TEXT.split('CMD="${1:-}"')[0]
        self.assertIn('[ $# -eq 0 ]', dispatch)

    def test_menu_has_options_entry(self):
        menu = RUN_TEXT.split('if [ "$CMD" = "menu" ]')[1].split(
            "# Sort-probe command"
        )[0]
        self.assertIn("8) Options", menu)
        self.assertIn("menu_options", menu)
        # The other choices are untouched.
        for dispatch in (
            'bash "$ROOT/run.sh" rediscover',
            'bash "$ROOT/run.sh" flow ||',
            'bash "$ROOT/run.sh" flowPreview',
            'bash "$ROOT/run.sh" audit',
        ):
            self.assertIn(dispatch, menu)

    def test_loader_turns_marker_into_cli_env(self):
        self.assertIn("load_persisted_options", RUN_TEXT)
        self.assertIn("SETER_SPLIT_COLLABS=1", RUN_TEXT)
        self.assertIn("split-collabs-enabled", RUN_TEXT)
        # The loader runs before dispatch, so direct commands,
        # menu children, and daily children all see it.
        lines = RUN_TEXT.splitlines()
        call_at = next(i for i, line in enumerate(lines) if line == "load_persisted_options")
        dispatch_at = next(i for i, line in enumerate(lines) if "[ $# -eq 0 ]" in line)
        self.assertLess(call_at, dispatch_at)

    def test_daily_reads_probe_age_file(self):
        self.assertIn("load_probe_max_age", DAILY_TEXT)
        self.assertIn("probe-max-age-hours", DAILY_TEXT)
        lines = DAILY_TEXT.splitlines()
        call_at = next(i for i, line in enumerate(lines) if line == "load_probe_max_age")
        assign_at = next(
            i
            for i, line in enumerate(lines)
            if line.startswith('PROBE_MAX_AGE_HOURS="${SETER_PROBE_MAX_AGE_HOURS:-0}"')
        )
        self.assertLess(call_at, assign_at)

    def test_no_new_empty_array_expansions(self):
        expansions = [
            line for line in RUN_TEXT.splitlines() if "[@]" in line
        ]
        self.assertEqual(len(expansions), 1)
        self.assertIn("apply_args[@]", expansions[0])


class DailyProbeAgeFileTests(_selfprobe.DailyAutoProbeTests):
    def setUp(self) -> None:
        super().setUp()
        self.settings = self.base / "settings"
        self.settings.mkdir()

    def write_mapping(self, target, age_hours):
        import hashlib
        import time

        safe = target.replace(" ", "_").replace("/", "_")
        digest = hashlib.sha256(target.encode()).hexdigest()[:12]
        ts = int(time.time() - age_hours * 3600)
        (self.state / f"sort-mapping-{safe}-{digest}.txt").write_text(
            f"MAPPING: reversed\nTHROWAWAY: {target}\nTARGET: {target}\n"
            f"SORT: self-probe: target's own sort\nTIMESTAMP: {ts}\n",
            encoding="utf-8",
        )

    def probe_calls(self):
        if not self.calls.exists():
            return []
        return [
            line
            for line in self.calls.read_text().splitlines()
            if line.startswith("selfprobe")
        ]

    def test_probe_age_file_skips_probes_for_young_mappings(self):
        for target in (
            "My New Sandwich Recipe",
            "SeTeR Rediscover",
            "SeTeR Flow",
        ):
            self.write_mapping(target, 1)
        (self.settings / "probe-max-age-hours").write_text("12\n", encoding="utf-8")
        result = self.run_daily({"SETER_AI_DIR": str(self.settings)})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.probe_calls(), [])
        combined = result.stdout + result.stderr
        self.assertIn("self-probe skipped for 'My New Sandwich Recipe'", combined)

    def test_probe_age_file_zero_still_probes(self):
        for target in (
            "My New Sandwich Recipe",
            "SeTeR Rediscover",
            "SeTeR Flow",
        ):
            self.write_mapping(target, 1)
        (self.settings / "probe-max-age-hours").write_text("0\n", encoding="utf-8")
        result = self.run_daily({"SETER_AI_DIR": str(self.settings)})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(self.probe_calls()), 3)

    def test_probe_age_env_wins_over_file(self):
        for target in (
            "My New Sandwich Recipe",
            "SeTeR Rediscover",
            "SeTeR Flow",
        ):
            self.write_mapping(target, 1)
        (self.settings / "probe-max-age-hours").write_text("12\n", encoding="utf-8")
        result = self.run_daily(
            {
                "SETER_AI_DIR": str(self.settings),
                "SETER_PROBE_MAX_AGE_HOURS": "0",
            }
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(self.probe_calls()), 3)

    def test_probe_age_file_over_40_clamps_to_40(self):
        # A 30-hour-old mapping is older than the 12-hour default
        # but younger than the 40-hour clamp, so a file saying 99
        # must still skip the probe (clamped to 40, not ignored).
        for target in (
            "My New Sandwich Recipe",
            "SeTeR Rediscover",
            "SeTeR Flow",
        ):
            self.write_mapping(target, 30)
        (self.settings / "probe-max-age-hours").write_text("99\n", encoding="utf-8")
        result = self.run_daily({"SETER_AI_DIR": str(self.settings)})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.probe_calls(), [])


if __name__ == "__main__":
    unittest.main()
