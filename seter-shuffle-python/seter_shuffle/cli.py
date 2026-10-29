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
  record-history       Append picked IDs to a Rediscover history file
                       (the runner calls this only after a successful
                       apply, so a failed apply never burns cooldown)

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

from .flow import flow_energy, prepare_flow
from .rediscover import (
    load_rediscover_history,
    pick_rediscover,
    record_rediscover_history,
)
from .settings import Settings
from .shuffle import shuffle_tracks
from .tracks import Track, load_library


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

    tracks = load_library(args.library)
    settings = _settings_from(args)
    rng = _rng(args.seed)
    now = datetime.now(timezone.utc)
    command = args.command

    if command == "shuffle":
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
        for line in _preview_lines(ordered, energies, settings.preview_show):
            print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
