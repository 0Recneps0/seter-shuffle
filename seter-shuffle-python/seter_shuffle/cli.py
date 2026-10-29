"""Command line for the Python experimental core.

The CLI works only on files. It reads a library JSON dump, computes an
ordering, and writes that ordering to files the caller asks for. It
never opens Music, never edits the dump, and never writes a playlist
by itself: writing to Music is the bridge's job, and the runner only
calls the bridge after this step succeeds.

Commands:
  shuffle              Fisher-Yates shuffle + artist spacing
  rediscover           Rediscover picks (does NOT record history)
  rediscover-preview   Same picks, printed, no files written except --out
  flow                 Flow ordering (ordered IDs only; no Music write)
  flowPreview          Flow ordering printed with energy scores
  audit                Tag-coverage audit of a library dump (changes
                       nothing; tells a real BPM gap from a dump bug)
  record-history       Append picked IDs to a Rediscover history file
                       (the runner calls this only after a successful
                       apply, so a failed apply never burns cooldown)
  library-manifest     Write a daily library manifest TSV
                       (persistent_id, artist, album, title), the
                       Python form of v2.6's daily manifest backup
  dedupe               Unique songs of a playlist dump, first
                       occurrence order (removes duplicate entries;
                       never invents or drops a distinct song)
  validate-order       Safety gate: check an order text file against
                       the library dump and (optionally) the order
                       JSON before the bridge ever runs. Refuses an
                       empty, duplicate, missing-ID, truncated, or
                       wrong-count order; never silently fixes one.
  validate-backup      Check a backup file is readable and well-formed
                       (duplicates allowed: a real playlist can hold
                       the same song twice; an empty file is valid:
                       it snapshots an empty playlist)

Common options:
  --library PATH       library JSON dump (required, except record-history)
  --out PATH           write {"command", "ids", ...} JSON here
  --order-txt PATH     write one persistent ID per line (bridge input)
  --seed N             replayable randomness (default: OS randomness)
  --size N             cap the output (shuffle / flow)
  --playlist NAME      playlist name recorded in --out (cosmetic here;
                       the bridge is what actually targets a playlist)
  --history PATH       Rediscover cooldown history (read-only for picks)
  --quiet              print nothing but errors

Exit codes: 0 on success, 2 on bad arguments / unreadable input,
1 on an empty result where a playlist was expected (the runner treats
an empty order as "do not touch the playlist").
"""

from __future__ import annotations

import argparse
import json
import random
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .audit import audit_library, format_audit
from .flow import flow_energy, prepare_flow
from .manifest import write_library_manifest
from .rediscover import (
    load_rediscover_history,
    pick_rediscover,
    record_rediscover_history,
)
from .settings import Settings
from .shuffle import shuffle_tracks
from .tracks import Track, load_library
from .validate import validate_backup_file, validate_order_file


def _rng(seed: int | None) -> random.Random:
    return random.Random(seed) if seed is not None else random.Random()


def _write_order_files(
    out: str | None, order_txt: str | None, payload: dict[str, Any]
) -> None:
    if out is not None:
        Path(out).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    if order_txt is not None:
        Path(order_txt).write_text(
            "\n".join(payload["ids"]) + ("\n" if payload["ids"] else ""),
            encoding="utf-8",
        )


def _preview_lines(
    tracks: list[Track], energies: list[int] | None, show: int
) -> list[str]:
    lines: list[str] = []
    for i, track in enumerate(tracks[:show]):
        energy = f" (energy {energies[i]})" if energies is not None else ""
        lines.append(f"{i + 1}. {track.artist} - {track.name}{energy}")
    if len(tracks) > show:
        lines.append(f"... and {len(tracks) - show} more")
    return lines


def _add_common(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--library", required=True, help="library JSON dump")
    parser.add_argument("--out", default=None, help="write result JSON here")
    parser.add_argument("--order-txt", default=None, help="write IDs, one per line")
    parser.add_argument("--seed", type=int, default=None, help="replayable randomness")
    parser.add_argument("--quiet", action="store_true")


def _add_settings(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--artist-spacing", type=int, default=None)
    parser.add_argument("--flow-size", type=int, default=None)
    parser.add_argument("--flow-pool-max", type=int, default=None)
    parser.add_argument("--rediscover-min", type=int, default=None)
    parser.add_argument("--rediscover-max", type=int, default=None)
    parser.add_argument("--stale-days", type=int, default=None)
    parser.add_argument("--max-per-artist", type=int, default=None)
    parser.add_argument("--cooldown-days", type=int, default=None)


def _settings_from(args: argparse.Namespace) -> Settings:
    base = Settings()
    overrides: dict[str, Any] = {}
    mapping = {
        "artist_spacing": args.artist_spacing,
        "flow_size": args.flow_size,
        "flow_pool_max": args.flow_pool_max,
        "rediscover_min": args.rediscover_min,
        "rediscover_max": args.rediscover_max,
        "stale_days": args.stale_days,
        "rediscover_max_per_artist": args.max_per_artist,
        "rediscover_cooldown_days": args.cooldown_days,
    }
    for key, value in mapping.items():
        if value is not None:
            overrides[key] = value
    return Settings(**{**base.__dict__, **overrides})


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="seter_shuffle", description="SeTeR Shuffle Python experimental core"
    )
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("shuffle", help="shuffle a track list")
    _add_common(p)
    _add_settings(p)
    p.add_argument("--size", type=int, default=None, help="cap the output")
    p.add_argument("--playlist", default=None)
    # Only for one-playlist shuffles: a playlist dump repeats an ID
    # for each duplicate playlist entry, and those entries must be
    # preserved as positions. A whole-library shuffle must NOT pass
    # this: in a library dump one ID is one song, so a repeat there
    # is a dump error and must still fail closed. run.sh passes this
    # flag only when it dumped one playlist, never for the library.
    p.add_argument("--allow-duplicates", action="store_true")

    p = sub.add_parser("rediscover", help="Rediscover picks (no history write)")
    _add_common(p)
    _add_settings(p)
    p.add_argument("--history", default=None, help="cooldown history TSV")
    p.add_argument("--playlist", default="SeTeR Rediscover")

    p = sub.add_parser(
        "rediscover-preview", help="Rediscover picks, printed, nothing applied"
    )
    _add_common(p)
    _add_settings(p)
    p.add_argument("--history", default=None, help="cooldown history TSV")
    p.add_argument("--playlist", default="SeTeR Rediscover")

    p = sub.add_parser("flow", help="Flow ordering (IDs only)")
    _add_common(p)
    _add_settings(p)
    p.add_argument("--size", type=int, default=None, help="cap the output")
    p.add_argument("--playlist", default="SeTeR Flow")

    p = sub.add_parser(
        "flowPreview", aliases=["flow-preview"],
        help="Flow ordering printed with energy scores",
    )
    _add_common(p)
    _add_settings(p)
    p.add_argument("--size", type=int, default=None, help="cap the output")
    p.add_argument("--playlist", default="SeTeR Flow")

    p = sub.add_parser(
        "dedupe",
        help="unique songs of a playlist dump, first occurrence order",
    )
    _add_common(p)
    _add_settings(p)
    p.add_argument("--playlist", default=None)

    p = sub.add_parser(
        "audit", help="tag-coverage audit of a library dump (changes nothing)"
    )
    p.add_argument("--library", required=True, help="library JSON dump")
    p.add_argument("--out", default=None, help="write audit JSON here")
    p.add_argument("--top-genres", type=int, default=20)

    p = sub.add_parser(
        "validate-order",
        help="safety gate: validate an order file before any bridge write",
    )
    p.add_argument("--library", required=True, help="library JSON dump")
    p.add_argument("--order-txt", required=True, help="one ID per line")
    p.add_argument("--order-json", default=None, help="order JSON to agree with")
    p.add_argument(
        "--mode",
        default=None,
        choices=["shuffle", "shuffle-size", "flow", "rediscover", "dedupe"],
    )
    p.add_argument("--expected-count", type=int, default=None)

    p = sub.add_parser(
        "validate-backup",
        help="check a backup file is readable and well-formed",
    )
    p.add_argument("--backup", required=True, help="backup file to check")

    p = sub.add_parser(
        "library-manifest",
        help="write a daily library manifest TSV from a library dump",
    )
    p.add_argument("--library", required=True, help="library JSON dump")
    p.add_argument("--out", required=True, help="manifest TSV to write")

    p = sub.add_parser(
        "record-history",
        help="append picked IDs to a Rediscover history file (after apply)",
    )
    p.add_argument("--history", required=True, help="cooldown history TSV")
    p.add_argument("--ids-file", required=True, help="file with one ID per line")
    p.add_argument("--cooldown-days", type=int, default=14)
    p.add_argument("--today", default=None, help="YYYY-MM-DD (tests only)")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return _run(args)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


def _run(args: argparse.Namespace) -> int:
    if args.command == "validate-order":
        ids = validate_order_file(
            args.library,
            args.order_txt,
            order_json_path=args.order_json,
            mode=args.mode,
            expected_count=args.expected_count,
        )
        print(f"Order valid: {len(ids)} IDs (mode: {args.mode or 'any'}).")
        return 0

    if args.command == "validate-backup":
        ids = validate_backup_file(args.backup)
        print(f"Backup valid: {len(ids)} IDs.")
        return 0

    if args.command == "library-manifest":
        tracks = load_library(args.library)
        count = write_library_manifest(tracks, args.out)
        print(f"Library manifest: {count} tracks written to {args.out}.")
        return 0

    if args.command == "audit":
        tracks = load_library(args.library)
        report = audit_library(tracks)
        if args.out is not None:
            Path(args.out).write_text(
                json.dumps(report, indent=2) + "\n", encoding="utf-8"
            )
        for line in format_audit(report, top_genres=args.top_genres):
            print(line)
        return 0

    if args.command == "record-history":
        from datetime import date

        today = date.fromisoformat(args.today) if args.today else None
        ids = [
            line.strip()
            for line in Path(args.ids_file).read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]
        record_rediscover_history(args.history, ids, args.cooldown_days, today)
        return 0

    # Only a one-playlist shuffle may see duplicate IDs in a dump
    # (see --allow-duplicates above), plus dedupe itself, whose
    # whole job is reading a dump that repeats IDs. Every other
    # command keeps the strict default: in a library dump one ID is
    # one song, so a repeat there is still a dump error, not two
    # songs.
    tracks = load_library(
        args.library,
        allow_duplicates=(
            args.command == "dedupe"
            or (args.command == "shuffle" and getattr(args, "allow_duplicates", False))
        ),
    )
    settings = _settings_from(args)
    rng = _rng(args.seed)
    now = datetime.now(timezone.utc)
    command = args.command

    if command == "dedupe":
        # Unique songs, first occurrence order: the dedupe order is
        # a subset of the dump, never an invented ID, and it keeps
        # the current list-read order of first appearances. It does
        # NOT restore a backup order: on a reversed doubled playlist
        # the result is unique songs in reversed order, and a
        # backup-order restore is a separate step afterwards.
        # Every removed duplicate entry is logged by name/artist
        # (v2.6 parity), not counts only: the names come from the
        # dump itself, so a removed entry is always identifiable
        # in the run log.
        seen: set[str] = set()
        ordered = []
        removed_tracks: list[Track] = []
        for track in tracks:
            if track.persistent_id not in seen:
                seen.add(track.persistent_id)
                ordered.append(track)
            else:
                removed_tracks.append(track)
        removed = len(removed_tracks)
        energies = None
        eligible = len(tracks)
        header = (
            f"Dedupe: {len(ordered)} unique songs from {len(tracks)} "
            f"input tracks ({removed} duplicate entr{'y' if removed == 1 else 'ies'} removed)."
        )
    elif command == "shuffle":
        ordered = shuffle_tracks(
            tracks,
            spacing=settings.artist_spacing,
            featuring_is_same_artist=settings.featuring_is_same_artist,
            rng=rng,
            size=args.size,
        )
        energies: list[int] | None = None
        eligible = len(tracks)
        header = f"Shuffle: {len(ordered)} songs from {eligible} input tracks."
    elif command in ("rediscover", "rediscover-preview"):
        history: set[str] = set()
        if args.history:
            history = load_rediscover_history(
                args.history, settings.rediscover_cooldown_days
            )
        ordered, candidates, target = pick_rediscover(
            tracks, now, settings, history, rng
        )
        energies = None
        eligible = candidates
        header = (
            f"Rediscover: {len(ordered)} songs picked "
            f"({candidates} eligible, target {target})."
        )
        if command == "rediscover-preview":
            header += " Nothing was changed."
    elif command in ("flow", "flowPreview", "flow-preview"):
        if args.size is not None:
            settings = Settings(**{**settings.__dict__, "flow_size": args.size})
        ordered, flow_energies, eligible = prepare_flow(tracks, settings, rng)
        energies = flow_energies
        header = f"Flow: {len(ordered)} songs from {eligible} eligible tracks."
        if command in ("flowPreview", "flow-preview"):
            header += " Nothing was changed."
    else:  # argparse prevents this; kept so a new command fails loudly
        print(f"error: unknown command {command}", file=sys.stderr)
        return 2

    if not ordered:
        print(f"{header}\nNo songs ordered; nothing to write.", file=sys.stderr)
        return 1

    payload: dict[str, Any] = {
        "command": command,
        "playlist": getattr(args, "playlist", None),
        "ids": [t.persistent_id for t in ordered],
        "count": len(ordered),
        "eligible": eligible,
    }
    _write_order_files(args.out, args.order_txt, payload)
    if not args.quiet:
        print(header)
        if command == "dedupe":
            for track in removed_tracks:
                print(f"Removed duplicate: {track.artist} - {track.name}")
        for line in _preview_lines(ordered, energies, settings.preview_show):
            print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
