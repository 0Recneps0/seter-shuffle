"""Order and backup validation: the safety gate before any bridge write.

This module is the Python half of the bridge safety contract. It runs
in run.sh AFTER the core computes an order and BEFORE osascript ever
runs, so a bad order is refused while the playlist is still untouched.
The bridge re-validates the same rules on its own side (it cannot
know the intended count, so it also verifies the exact final order
and restores on any mismatch), but this module is what catches
truncation and corruption, which the bridge alone cannot see: a
truncated order file still "verifies" against itself, so the check
against the dump and the order JSON has to happen here.

Refuse rules for an order file (any mode):
  - The file must exist and be readable UTF-8 text.
  - It must contain at least one ID. An empty order never wipes a
    playlist: there is no legitimate "apply an empty order" operation.
    (Emptying a playlist is done explicitly through undo with an
    empty backup, a different, deliberate path.)
  - Every line must be a single ID: no blank lines except one
    trailing newline at the end of the file, no leading/trailing
    whitespace, no whitespace or control characters inside an ID.
    A blank line in the middle, or a missing trailing structure, is
    treated as corruption, not skipped silently.
  - No ID may appear more times than it appears in the dump. The
    core never emits a duplicate for a whole-library order, so a
    repeat there is corruption. But a one-playlist shuffle may
    legitimately repeat an ID exactly as many times as the playlist
    itself repeats that song (Music allows duplicate entries in one
    playlist), so the rule is multiplicity, not a blanket refusal:
    an order with more copies of an ID than the dump has is refused,
    and a shuffle order must match the dump's multiset exactly (see
    below). The bridge applies the same rule via its duplicate
    allowance flag for playlist shuffles.
  - Every ID must be present in the library dump. An ID the dump does
    not know is refused with the missing IDs listed, never silently
    skipped (skipping would shift every later song and, worse, would
    let a stale order silently drop a song the user still owns).
  - If an order JSON file is given, its "ids" list must equal the
    text file exactly (same IDs, same order, same count) and its
    "count", if present, must agree. This is the truncation check:
    if the text file was cut short after the core wrote it, the two
    disagree and the run stops before Music is touched.
  - If an expected count is given, the order count must equal it.

Mode rules (on top of the above):
  - shuffle: the order must be exactly the dump's song set, no more,
    no less. For a whole-library shuffle the dump is the library; for
    a one-playlist shuffle the dump is that playlist, so the rule is
    the same either way: a shuffle reorders, it never adds or drops.
  - flow / rediscover: every ID must be Flow-eligible (enabled and
    not disliked). The core already filters this; validation is the
    second check, not the picker.

Backup files follow different rules, on purpose:
  - A backup is a snapshot of a real playlist, and a real playlist
    CAN contain the same song twice (Music allows duplicate entries
    in a user playlist), so duplicates are ALLOWED in a backup.
  - A backup must exist and be readable. A missing backup is refused
    before anything is deleted.
  - Blank lines in the middle and whitespace inside an ID are still
    corruption and are refused.
  - An empty backup file is legitimate: it means the playlist was
    empty when the snapshot was taken (first-run "SeTeR Flow", for
    example). Undo of an empty backup restores an empty playlist,
    it does not fail.

All failures raise ValueError with every problem found, so the
caller can print the full list instead of failing on the first
symptom and hiding the rest.
"""

from __future__ import annotations

import json
import re
from collections import Counter
from pathlib import Path
from typing import Mapping, Sequence

from .tracks import Track, load_library

# An ID with whitespace or a control character in it cannot be a real
# persistent ID, and passing one to Music would fail the lookup in a
# way that is hard to tell apart from a genuinely missing song. Reject
# it up front. The character set is deliberately loose beyond that:
# Music persistent IDs are opaque strings, and restricting them to
# hex (say) would risk refusing a real ID on some Mac.
_ID_BAD_CHARS = re.compile(r"[\s\x00-\x1f\x7f]")


def _read_lines(path: str | Path) -> tuple[list[str], list[str]]:
    """Read a one-ID-per-line file strictly.

    Returns (ids, errors). A trailing newline at end of file is the
    only blank line allowed: the core writes one, and the bridge
    writes none, so a blank line anywhere else is corruption.
    """
    errors: list[str] = []
    try:
        text = Path(path).read_text(encoding="utf-8")
    except OSError as exc:
        return [], [f"cannot read {path}: {exc}"]
    except UnicodeDecodeError as exc:
        return [], [f"{path} is not valid UTF-8 text: {exc}"]
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    if all(line == "" for line in lines):
        # A file with no IDs at all (empty, or only newlines) is
        # empty, not corrupt: the caller decides what empty means
        # (an order refuses it; a backup accepts it as an empty
        # playlist). A blank line among real IDs is still corruption
        # and is caught below.
        return [], []
    ids: list[str] = []
    for i, line in enumerate(lines, start=1):
        if line == "":
            errors.append(f"line {i} is blank (corrupt or truncated file)")
            continue
        if line != line.strip():
            errors.append(f"line {i} has leading or trailing whitespace: {line!r}")
            continue
        if _ID_BAD_CHARS.search(line):
            errors.append(f"line {i} contains whitespace or control characters: {line!r}")
            continue
        ids.append(line)
    return ids, errors


def validate_backup_file(path: str | Path) -> list[str]:
    """Validate a backup file. Returns its IDs (duplicates allowed).

    Raises ValueError on a missing/unreadable file, a blank line in
    the middle, or a malformed ID. An empty file returns [] and is
    valid: it snapshots an empty playlist.
    """
    ids, errors = _read_lines(path)
    if errors:
        raise ValueError("; ".join(errors))
    return ids


def validate_order_file(
    library_path: str | Path,
    order_txt_path: str | Path,
    order_json_path: str | Path | None = None,
    mode: str | None = None,
    expected_count: int | None = None,
) -> list[str]:
    """Validate an order file against a library dump.

    mode is None, "shuffle", "flow", or "rediscover". Raises
    ValueError listing every problem found. Returns the validated
    IDs in order on success.
    """
    errors: list[str] = []
    # A one-playlist dump may repeat an ID (duplicate playlist
    # entries), so the dump is loaded with duplicates allowed and the
    # checks below are multiplicity checks, not set checks. A
    # whole-library dump has no repeats, so nothing is loosened there.
    tracks: list[Track] = load_library(library_path, allow_duplicates=True)
    library_ids = {t.persistent_id for t in tracks}
    by_id = {t.persistent_id: t for t in tracks}
    dump_counts = Counter(t.persistent_id for t in tracks)

    ids, read_errors = _read_lines(order_txt_path)
    errors.extend(read_errors)
    if not ids and not read_errors:
        errors.append("order file is empty: refusing to wipe a playlist to empty")

    order_counts = Counter(ids)
    over = [
        pid
        for pid, count in order_counts.items()
        if count > dump_counts.get(pid, 0)
    ]
    if over:
        errors.append(
            f"order file repeats IDs more times than the dump does "
            f"(would invent duplicate playlist entries): {', '.join(over[:10])}"
            + (f" and {len(over) - 10} more" if len(over) > 10 else "")
        )

    missing = [pid for pid in ids if pid not in library_ids]
    if missing:
        errors.append(
            f"{len(missing)} order ID(s) are not in the library dump "
            f"(refusing, never silently skipping): {', '.join(missing[:10])}"
            + (f" and {len(missing) - 10} more" if len(missing) > 10 else "")
        )

    if order_json_path is not None:
        try:
            payload = json.loads(Path(order_json_path).read_text(encoding="utf-8"))
        except OSError as exc:
            errors.append(f"cannot read order JSON {order_json_path}: {exc}")
            payload = None
        except json.JSONDecodeError as exc:
            errors.append(f"order JSON {order_json_path} is malformed: {exc}")
            payload = None
        if payload is not None:
            if not isinstance(payload, dict) or not isinstance(payload.get("ids"), list):
                errors.append(f"order JSON {order_json_path} has no 'ids' list")
            else:
                json_ids = [str(x) for x in payload["ids"]]
                if json_ids != ids:
                    errors.append(
                        "order text file does not match order JSON "
                        f"(text has {len(ids)} IDs, JSON has {len(json_ids)}; "
                        "the text file may be truncated or corrupt)"
                    )
                if "count" in payload and payload["count"] != len(ids):
                    errors.append(
                        f"order JSON count {payload['count']} does not match "
                        f"order text count {len(ids)}"
                    )

    if mode == "shuffle":
        # Multiset equality, not set equality: a playlist shuffle
        # must preserve duplicate entries exactly (same songs, same
        # multiplicities), and a set check would pass an order that
        # dropped a duplicate entry while keeping one copy of the song.
        if Counter(ids) != dump_counts:
            errors.append(
                f"shuffle order must be exactly the dump's songs "
                f"(same songs, same multiplicities): "
                f"order has {len(ids)} IDs, dump has {len(tracks)} songs"
            )
    elif mode in ("flow", "rediscover"):
        ineligible = [
            pid
            for pid in ids
            if pid in by_id and (not by_id[pid].enabled or by_id[pid].disliked)
        ]
        if ineligible:
            errors.append(
                f"{mode} order contains ineligible songs (unchecked or "
                f"disliked): {', '.join(ineligible[:10])}"
                + (f" and {len(ineligible) - 10} more" if len(ineligible) > 10 else "")
            )
    elif mode is not None:
        errors.append(f"unknown validation mode: {mode!r}")

    if expected_count is not None and len(ids) != expected_count:
        errors.append(
            f"order has {len(ids)} IDs but {expected_count} were expected"
        )

    if errors:
        raise ValueError("; ".join(errors))
    return ids


def validate_order_text(
    ids: Sequence[str],
    library_ids: set[str],
    mode: str | None = None,
    eligible_ids: set[str] | None = None,
    library_counts: Mapping[str, int] | None = None,
) -> None:
    """In-memory form of the same rules, for tests and callers that
    already hold the IDs (no file involved). Raises ValueError.

    library_counts, when given, is the dump's ID multiplicity, and the
    shuffle check becomes multiset equality against it (so a playlist
    shuffle that preserves duplicate entries passes, and one that
    drops a duplicate entry fails). Without it, the shuffle check is
    set equality plus a length check, which still catches a dropped
    duplicate when the library set has no repeats.
    """
    errors: list[str] = []
    id_list = list(ids)
    if not id_list:
        errors.append("order is empty: refusing to wipe a playlist to empty")
    if library_counts is not None:
        over = [
            pid
            for pid, count in Counter(id_list).items()
            if count > library_counts.get(pid, 0)
        ]
        if over:
            errors.append(
                f"order repeats IDs more times than the library does: "
                f"{', '.join(over[:10])}"
            )
    else:
        seen: set[str] = set()
        duplicates = [pid for pid in id_list if pid in seen or seen.add(pid)]
        if duplicates:
            errors.append(f"duplicate persistent IDs in order: {', '.join(duplicates[:10])}")
    missing = [pid for pid in id_list if pid not in library_ids]
    if missing:
        errors.append(f"order IDs not in library: {', '.join(missing[:10])}")
    if mode == "shuffle":
        if library_counts is not None:
            if Counter(id_list) != Counter(dict(library_counts)):
                errors.append("shuffle order must be exactly the library songs (same multiplicities)")
        elif set(id_list) != library_ids or len(id_list) != len(library_ids):
            errors.append("shuffle order must be exactly the library song set")
    if mode in ("flow", "rediscover") and eligible_ids is not None:
        bad = [pid for pid in id_list if pid not in eligible_ids]
        if bad:
            errors.append(f"{mode} order contains ineligible songs: {', '.join(bad[:10])}")
    if errors:
        raise ValueError("; ".join(errors))
