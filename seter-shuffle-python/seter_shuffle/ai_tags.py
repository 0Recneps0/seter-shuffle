"""Optional AI vibe tagging for Flow, via Apple's on-device `fm` CLI.

What this is: a small, defensive wrapper that asks the macOS 27
Foundation Models CLI (`fm respond`, on-device by default) to tag
songs with an energy score (0..100) and one mood bucket, caches every
tag on disk, and hands Flow a {persistent_id: AiTag} map. Flow blends
the AI energy with its own metadata heuristic (Settings.ai_blend) and
adds a small mood-continuity cost to its walk. The AI never orders
anything: it only scores songs. Ordering stays deterministic code.

Design rules (same spirit as the rest of the core):

- OPTIONAL AND FAIL-SOFT. No `fm`, a license that has not been
  accepted, a timeout, bad JSON, a refused batch: every failure ends
  with the affected songs simply keeping their heuristic energy. Flow
  never fails because of the AI, and a run with no tags is identical
  to a run without this module.
- NOTHING IS TRUSTED. Every model reply is validated: each input line
  number must come back exactly once, energy must be a number (clamped
  to 0..100), mood must be one of MOODS (anything else is dropped,
  the energy is kept). A reply that fails validation is not
  half-trusted: the missing songs are retried one at a time, and a
  song that still fails is left untagged.
- CACHED. Tags live in a JSON file keyed by persistent ID with a
  signature of the metadata they were made from, so a song is tagged
  once, and re-tagged only if its title, artist, genre, year or BPM
  changed or PROMPT_VERSION was bumped. The cache is written
  atomically after every batch, so a crash loses at most one batch.
- BOUNDED. A per-run time budget and a consecutive-failure limit stop
  a stuck model from hanging the daily run; whatever was tagged so
  far is kept.
- ON-DEVICE BY DEFAULT. Uses `--model system` (the default). Songs'
  title/artist/genre/year/BPM leave the machine only if the caller
  passes a different --model in extra_args (for example `pcc`).

Standard library only. Subprocess calls go through an injectable
runner so tests never need a Mac or a real `fm`.

UNVERIFIED ON A REAL MAC (this was written on Linux against the
documented `fm` help text): the exact JSON shape `fm respond --schema`
prints, and whether `fm schema ... --array` takes the property before
or after `--schema`. The code tries both orders, accepts several reply
shapes, and falls back to one song per call. Run `ai-selftest` on the
Mac first: it prints the raw output and says what worked.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from datetime import date
from pathlib import Path
from typing import Callable, Mapping, Sequence

from .flow import MOODS, AiTag
from .tracks import Track

PROMPT_VERSION = 2  # v2 (2026-11-20): BPM 0 is sent as unknown. On
# Spencer's Mac the model copied the BPM number straight into energy
# (72 -> 72, 116 -> 116, no BPM -> 0), and his whole library dumps
# BPM 0, so every song came back energy 0. Bumping the version
# retires those cached zero tags: their sigs were made under v1.
CACHE_FORMAT = 1

# (argv, stdin_text) -> (returncode, stdout, stderr). Never raises.
Runner = Callable[[Sequence[str], str], "tuple[int, str, str]"]

INSTRUCTIONS = (
    "You tag songs for a playlist generator. Each input line is: "
    "n|title|artist|genre|year|bpm. Return exactly one tag for every line, "
    "copying n unchanged. energy is an integer from 0 (very calm, sparse, "
    "slow) to 100 (very intense, loud, fast, danceable). mood is exactly "
    "one of: " + ", ".join(MOODS) + ". If you do not recognise a song, "
    "judge it from its genre, year and bpm. Do not skip lines and do not "
    "add commentary."
)

# Property descriptions baked into the schemas (the CLI has no enums or
# min/max, so the limits live in the text and in validate_tags).
_DESC_N = "Input line number, copied exactly"
_DESC_ENERGY = "Energy from 0 (very calm) to 100 (very intense)"
_DESC_MOOD = "Exactly one of: " + ", ".join(MOODS)


class AiUnavailable(Exception):
    """The `fm` tool cannot be used for the rest of this run."""


def default_runner(timeout: float = 120.0) -> Runner:
    """Real subprocess runner. Never raises: failures become return codes."""

    def run(argv: Sequence[str], stdin: str) -> tuple[int, str, str]:
        try:
            proc = subprocess.run(
                list(argv),
                input=stdin,
                capture_output=True,
                text=True,
                timeout=timeout,
            )
        except subprocess.TimeoutExpired:
            return 124, "", "timeout"
        except FileNotFoundError:
            return 127, "", "fm not found"
        except OSError as exc:
            return 126, "", str(exc)
        return proc.returncode, proc.stdout, proc.stderr

    return run


# ---------------------------------------------------------------------------
# Prompt and reply handling (pure functions, unit-tested)
# ---------------------------------------------------------------------------


def _field(value: object, limit: int = 80) -> str:
    text = "" if value is None else str(value)
    text = text.replace("|", " ").replace("\r", " ").replace("\n", " ")
    return " ".join(text.split())[:limit]


def _bpm_field(bpm: float | None) -> str:
    """BPM as sent to the model and hashed into the signature.

    0 means unknown, like a missing BPM: the dump writes 0 for songs
    with no BPM, and the model echoes the number into energy.
    """
    if bpm is None or bpm <= 0:
        return ""
    return f"{bpm:g}"


def track_signature(track: Track) -> str:
    """Short hash of the metadata a tag was made from."""
    bpm = _bpm_field(track.bpm)
    raw = "\x1f".join(
        (
            str(PROMPT_VERSION),
            _field(track.name), _field(track.artist), _field(track.genre),
            "" if track.year is None else str(track.year), bpm,
        )
    )
    return hashlib.sha1(raw.encode("utf-8")).hexdigest()[:12]


def build_prompt(tracks: Sequence[Track]) -> str:
    """One `n|title|artist|genre|year|bpm` line per track, n from 1."""
    lines = []
    for n, t in enumerate(tracks, start=1):
        bpm = _bpm_field(t.bpm)
        year = "" if t.year is None else str(t.year)
        lines.append("|".join((str(n), _field(t.name), _field(t.artist), _field(t.genre), year, bpm)))
    return "\n".join(lines)


_FENCE = re.compile(r"^```[a-zA-Z0-9_-]*\s*|\s*```\s*$")


def _extract_json(text: str) -> object:
    """Parse model output as JSON, tolerating code fences and stray prose."""
    cleaned = _FENCE.sub("", text.strip()).strip()
    try:
        return json.loads(cleaned)
    except ValueError:
        pass
    for open_c, close_c in (("[", "]"), ("{", "}")):
        start, end = cleaned.find(open_c), cleaned.rfind(close_c)
        if 0 <= start < end:
            try:
                return json.loads(cleaned[start : end + 1])
            except ValueError:
                continue
    raise ValueError("no JSON found in model output")


def _as_number(value: object) -> float | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value.strip())
        except ValueError:
            return None
    return None


def validate_tags(text: str, expected: Sequence[int]) -> dict[int, AiTag]:
    """Validate a model reply against the line numbers that were sent.

    Returns {n: AiTag} for every n that came back exactly once with a
    numeric energy. Anything else (unknown n, duplicate n, missing or
    non-numeric energy) is simply absent from the result, so the
    caller can retry those songs alone. Raises ValueError only when
    the reply is not JSON at all.
    """
    data = _extract_json(text)
    if isinstance(data, dict):
        lists = [v for v in data.values() if isinstance(v, list)]
        if isinstance(data.get("tags"), list):
            data = data["tags"]
        elif len(lists) == 1 and "energy" not in data:
            data = lists[0]  # any single-list wrapper, whatever its key
        else:
            data = [data]
    if not isinstance(data, list):
        raise ValueError("model output is not a list of tags")
    wanted = set(expected)
    seen: dict[int, int] = {}
    found: dict[int, AiTag] = {}
    for entry in data:
        if not isinstance(entry, dict):
            continue
        n_raw = entry.get("n")
        if n_raw is None and len(wanted) == 1:
            n = next(iter(wanted))  # one-song reply may omit n
        else:
            n_num = _as_number(n_raw)
            if n_num is None or n_num != int(n_num):
                continue
            n = int(n_num)
        if n not in wanted:
            continue
        seen[n] = seen.get(n, 0) + 1
        energy = _as_number(entry.get("energy"))
        if energy is None:
            continue
        mood_raw = entry.get("mood")
        mood = mood_raw.strip().casefold() if isinstance(mood_raw, str) else None
        if mood not in MOODS:
            mood = None
        found[n] = AiTag(energy=int(round(max(0.0, min(100.0, energy)))), mood=mood)
    return {n: tag for n, tag in found.items() if seen.get(n) == 1}


# ---------------------------------------------------------------------------
# Cache
# ---------------------------------------------------------------------------


class TagCache:
    """JSON file of tags keyed by persistent ID, with atomic saves."""

    def __init__(self, path: str | Path):
        self.path = Path(path)
        self.entries: dict[str, dict] = {}
        self.load()

    def load(self) -> None:
        self.entries = {}
        try:
            raw = json.loads(self.path.read_text(encoding="utf-8"))
        except FileNotFoundError:
            return
        except (OSError, ValueError):
            self._quarantine()
            return
        entries = raw.get("entries") if isinstance(raw, dict) else None
        if not isinstance(entries, dict) or raw.get("format") != CACHE_FORMAT:
            self._quarantine()
            return
        for pid, entry in entries.items():
            if isinstance(entry, dict) and isinstance(entry.get("energy"), int):
                self.entries[str(pid)] = entry

    def _quarantine(self) -> None:
        """Keep an unreadable cache for inspection instead of deleting it."""
        try:
            self.path.replace(self.path.with_name(self.path.name + ".bad"))
        except OSError:
            pass

    def get(self, track: Track) -> AiTag | None:
        entry = self.entries.get(track.persistent_id)
        if entry is None or entry.get("sig") != track_signature(track):
            return None
        mood = entry.get("mood")
        return AiTag(energy=entry["energy"], mood=mood if mood in MOODS else None)

    def put(self, track: Track, tag: AiTag) -> None:
        self.entries[track.persistent_id] = {
            "energy": tag.energy,
            "mood": tag.mood,
            "sig": track_signature(track),
            "at": date.today().isoformat(),
        }

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        payload = {"format": CACHE_FORMAT, "entries": self.entries}
        fd, tmp = tempfile.mkstemp(prefix=self.path.name + ".", dir=str(self.path.parent))
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                json.dump(payload, handle, indent=1, sort_keys=True)
                handle.write("\n")
            os.replace(tmp, self.path)
        except BaseException:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            raise


# ---------------------------------------------------------------------------
# fm client
# ---------------------------------------------------------------------------


class FmClient:
    """Thin wrapper over `fm schema` and `fm respond`."""

    def __init__(
        self,
        state_dir: str | Path,
        runner: Runner | None = None,
        fm: str = "fm",
        extra_args: Sequence[str] = (),
        require_binary: bool = True,
    ):
        self.state_dir = Path(state_dir)
        self.runner = runner or default_runner()
        self.fm = fm
        self.extra_args = list(extra_args)
        self.require_binary = require_binary and runner is None
        self.fatal: str | None = None
        self.batch_schema: Path | None = None
        self.item_schema: Path | None = None
        self._schemas_ready = False
        self.notes: list[str] = []

    # -- availability -------------------------------------------------
    def check(self) -> None:
        if self.fatal:
            raise AiUnavailable(self.fatal)
        if self.require_binary and shutil.which(self.fm) is None:
            self.fatal = "`fm` not found (it ships with macOS 27)"
            raise AiUnavailable(self.fatal)

    def _fail_fatal(self, stderr: str) -> None:
        low = stderr.lower()
        if "license" in low or "terms" in low:
            self.fatal = "run `sudo fm license` once to accept Apple's terms"
            raise AiUnavailable(self.fatal)
        if "apple intelligence" in low and ("not" in low or "disabled" in low or "unavailable" in low):
            self.fatal = "Apple Intelligence is not enabled or its models are not downloaded"
            raise AiUnavailable(self.fatal)

    # -- schemas ------------------------------------------------------
    def _schema_path(self, name: str) -> Path:
        return self.state_dir / "ai-schemas" / f"{name}-v{PROMPT_VERSION}.json"

    def _gen_item(self) -> str | None:
        for int_flag in ("--integer", "--int"):
            argv = [
                self.fm, "schema", "object", "--name", "TrackTag",
                int_flag, "n", "--description", _DESC_N,
                int_flag, "energy", "--description", _DESC_ENERGY,
                "--string", "mood", "--description", _DESC_MOOD,
            ]
            rc, out, _err = self.runner(argv, "")
            if rc == 0 and _is_json_object(out):
                return out.strip()
        return None

    def _gen_batch(self, item_json: str) -> str | None:
        orders = (
            ["--object", "tags", "--schema", item_json, "--array"],
            ["--object", "tags", "--array", "--schema", item_json],
        )
        for tail in orders:
            argv = [self.fm, "schema", "object", "--name", "BatchTags", *tail]
            rc, out, _err = self.runner(argv, "")
            if rc == 0 and _is_json_object(out) and '"array"' in out:
                return out.strip()
        return None

    def ensure_schemas(self) -> None:
        """Create the schema files once (reused from disk afterwards)."""
        if self._schemas_ready:
            return
        self.check()
        item_p, batch_p = self._schema_path("item"), self._schema_path("batch")
        if item_p.is_file():
            self.item_schema = item_p
        if batch_p.is_file():
            self.batch_schema = batch_p
        if self.item_schema is None:
            item = self._gen_item()
            if item is None:
                self.fatal = "could not generate a schema with `fm schema object`"
                raise AiUnavailable(self.fatal)
            item_p.parent.mkdir(parents=True, exist_ok=True)
            item_p.write_text(item + "\n", encoding="utf-8")
            self.item_schema = item_p
        if self.batch_schema is None:
            batch = self._gen_batch(self.item_schema.read_text(encoding="utf-8"))
            if batch is not None:
                batch_p.write_text(batch + "\n", encoding="utf-8")
                self.batch_schema = batch_p
            else:
                self.notes.append("array schema unavailable: tagging one song per call")
        self._schemas_ready = True

    # -- respond ------------------------------------------------------
    def respond(self, tracks: Sequence[Track], schema: Path) -> str | None:
        """One `fm respond` call; the raw stdout, or None on failure."""
        base = [
            self.fm, "respond", "--use-case", "content-tagging", "--greedy",
            "--no-stream", "--schema", str(schema), "--instructions", INSTRUCTIONS,
            *self.extra_args,
        ]
        prompt = build_prompt(tracks)
        rc, out, err = self.runner(base, prompt)
        if rc != 0 and "guardrail" in err.lower():
            rc, out, err = self.runner(
                base + ["--guardrails", "permissive-content-transformations"], prompt
            )
        if rc != 0:
            self._fail_fatal(err)
            return None
        return out


def _is_json_object(text: str) -> bool:
    try:
        return isinstance(json.loads(text), dict)
    except ValueError:
        return False


# ---------------------------------------------------------------------------
# Flow tagger
# ---------------------------------------------------------------------------


class FlowTagger:
    """Callable for prepare_flow(tagger=...): tags pool tracks, cached."""

    def __init__(
        self,
        cache: TagCache,
        client: FmClient,
        batch_size: int = 20,
        time_budget: float = 600.0,
        max_consecutive_failures: int = 3,
        clock: Callable[[], float] = time.monotonic,
        log: Callable[[str], None] | None = None,
    ):
        self.cache = cache
        self.client = client
        self.batch_size = max(1, batch_size)
        self.time_budget = time_budget
        self.max_failures = max(1, max_consecutive_failures)
        self.clock = clock
        self.log = log or (lambda msg: print(msg, file=sys.stderr))
        self.stats = {"cached": 0, "tagged": 0, "failed": 0, "skipped": 0}
        self.stopped: str | None = None
        self._started = 0.0

    def summary(self) -> str:
        s = self.stats
        text = (
            f"AI tags: {s['cached']} cached, {s['tagged']} new, "
            f"{s['failed']} failed, {s['skipped']} skipped"
        )
        return text + (f" (stopped: {self.stopped})" if self.stopped else "")

    def __call__(self, tracks: Sequence[Track]) -> Mapping[str, AiTag]:
        unique: dict[str, Track] = {}
        for t in tracks:
            unique.setdefault(t.persistent_id, t)
        result: dict[str, AiTag] = {}
        need: list[Track] = []
        for pid, t in unique.items():
            tag = self.cache.get(t)
            if tag is not None:
                result[pid] = tag
                self.stats["cached"] += 1
            else:
                need.append(t)
        if need:
            self._tag_missing(need, result)
        return result

    def _tag_missing(self, need: list[Track], result: dict[str, AiTag]) -> None:
        self._started = self.clock()
        started = self._started
        try:
            self.client.ensure_schemas()
        except AiUnavailable as exc:
            self._stop(str(exc), len(need))
            return
        batch_schema = self.client.batch_schema
        failures = 0
        i = 0
        while i < len(need):
            if self.clock() - started > self.time_budget:
                self._stop("time budget reached", len(need) - i)
                break
            if failures >= self.max_failures:
                self._stop(f"{failures} failures in a row", len(need) - i)
                break
            size = self.batch_size if batch_schema is not None else 1
            chunk = need[i : i + size]
            i += size
            try:
                got = self._tag_chunk(chunk, batch_schema)
            except AiUnavailable as exc:
                self._stop(str(exc), len(need) - (i - len(chunk)))
                break
            if got:
                failures = 0
            else:
                failures += 1
            for t, tag in got:
                self.cache.put(t, tag)
                result[t.persistent_id] = tag
            self.stats["tagged"] += len(got)
            self.stats["failed"] += len(chunk) - len(got)
            if got:
                self.cache.save()

    def _tag_chunk(
        self, chunk: list[Track], batch_schema: Path | None
    ) -> list[tuple[Track, AiTag]]:
        """Tag one batch; retry songs the batch missed one at a time."""
        done: dict[int, AiTag] = {}
        if batch_schema is not None and len(chunk) > 1:
            out = self.client.respond(chunk, batch_schema)
            if out is not None:
                try:
                    done = validate_tags(out, list(range(1, len(chunk) + 1)))
                except ValueError:
                    done = {}
        for n, t in enumerate(chunk, start=1):
            if n in done:
                continue
            if self.clock() - self._started > self.time_budget:
                break  # a stuck model must not run a 20-call retry past the budget
            out = self.client.respond([t], self.client.item_schema)  # type: ignore[arg-type]
            if out is None:
                continue
            try:
                one = validate_tags(out, [1])
            except ValueError:
                continue
            if 1 in one:
                done[n] = one[1]
        return [(chunk[n - 1], tag) for n, tag in sorted(done.items())]

    def _stop(self, reason: str, remaining: int) -> None:
        self.stopped = reason
        self.stats["skipped"] += remaining
        self.log(f"AI tagging stopped: {reason}; {remaining} songs keep heuristic energy")


# ---------------------------------------------------------------------------
# Self-test (run on the Mac before turning AI on)
# ---------------------------------------------------------------------------

_SAMPLE = (
    ("Bohemian Rhapsody", "Queen", "Rock", 1975, 72.0),
    ("Get Lucky", "Daft Punk", "Electronic", 2013, 116.0),
    ("Clair de Lune", "Claude Debussy", "Classical", 1905, None),
)


def selftest(client: FmClient, out: Callable[[str], None] = print) -> bool:
    """Exercise schemas and one batch; print what happened. True if usable."""
    tracks = [
        Track(persistent_id=f"T{i}", name=n, artist=a, genre=g, year=y, bpm=b)
        for i, (n, a, g, y, b) in enumerate(_SAMPLE, start=1)
    ]
    try:
        client.ensure_schemas()
    except AiUnavailable as exc:
        out(f"FAIL: {exc}")
        return False
    out(f"item schema:  {client.item_schema}")
    out(f"batch schema: {client.batch_schema or '(none: will tag one song per call)'}")
    for note in client.notes:
        out(f"note: {note}")
    schema = client.batch_schema or client.item_schema
    subject = tracks if client.batch_schema else tracks[:1]
    first = client.respond(subject, schema)  # type: ignore[arg-type]
    if first is None:
        out(f"FAIL: `fm respond` failed ({client.fatal or 'see stderr above'})")
        return False
    out("raw reply:\n" + first.strip())
    try:
        parsed = validate_tags(first, list(range(1, len(subject) + 1)))
    except ValueError as exc:
        out(f"FAIL: reply is not usable JSON ({exc})")
        return False
    for n, t in enumerate(subject, start=1):
        tag = parsed.get(n)
        out(f"  {t.artist} - {t.name}: " + (f"energy {tag.energy}, mood {tag.mood}" if tag else "MISSING"))
    if len(parsed) != len(subject):
        out("FAIL: not every song came back exactly once")
        return False
    second = client.respond(subject, schema)  # type: ignore[arg-type]
    out("determinism (--greedy): " + ("same reply twice" if second == first else "replies differ (tags may drift between runs)"))
    out("OK: AI tagging is usable.")
    return True


def default_ai_dir() -> Path:
    override = os.environ.get("SETER_AI_DIR")
    return Path(override) if override else Path.home() / "Documents" / "SeTeRShuffle"


def ai_enabled_by_environment() -> bool:
    """SETER_AI=1/true/yes, or the marker file <ai dir>/ai-enabled exists."""
    flag = os.environ.get("SETER_AI", "").strip().lower()
    if flag in ("1", "true", "yes", "on"):
        return True
    if flag in ("0", "false", "no", "off"):
        return False
    return (default_ai_dir() / "ai-enabled").exists()
