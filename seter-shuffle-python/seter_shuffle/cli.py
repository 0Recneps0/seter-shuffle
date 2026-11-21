"""Command line for the Python core.

The CLI works only on files. It reads a library JSON dump, computes an
ordering, and writes that ordering to files the caller asks for. It
never opens Music, never edits the dump, and never writes a playlist
by itself: writing to Music is the bridge's job, and the runner only
calls the bridge after this step succeeds.

Commands:
  shuffle              Fisher-Yates shuffle + artist spacing, plus a
                       full-list spacing summary
  rediscover           Rediscover picks (does NOT record history),
                       plus a full-list pick summary
  rediscover-preview   Same picks, printed, plus a full-list pick
                       summary, no files written except --out
  flow                 Flow ordering (ordered IDs only; no Music write)
  flowPreview          Flow ordering printed with energy scores, plus a
                       full-list arc summary (the preview list itself is
                       capped at preview_show songs)
  ai-selftest          Check Apple's `fm` AI tagging works on this Mac
                       (writes only schema files; changes nothing else).
                       Turn AI on for Flow with --ai, SETER_AI=1, or by
                       creating ~/Documents/SeTeRShuffle/ai-enabled.
  audit                Tag-coverage audit of a library dump (changes
                       nothing; tells a real BPM gap from a dump bug)
  record-history       Append picked IDs to a Rediscover history file
                       (the runner calls this only after a successful
                       apply, so a failed apply never burns cooldown)
                       and print a one-line confirmation of what was
                       recorded
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
import os
import random
import sys
from pathlib import Path
from typing import Any

from .ai_tags import (
    FlowTagger,
    FmClient,
    TagCache,
    ai_enabled_by_environment,
    default_ai_dir,
    selftest,
)
from .audit import audit_library, format_audit
from .flow import flow_arc_summary, prepare_flow
from .manifest import write_library_manifest
from .rediscover import (
    load_rediscover_history,
    pick_rediscover,
    record_rediscover_history,
    rediscover_summary,
)
from .settings import Settings
from .shuffle import shuffle_summary, shuffle_tracks
from .tracks import Track, dump_now, load_library, split_duplicates
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
    parser.add_argument(
        "--split-collabs", action=argparse.BooleanOptionalAction, default=None,
        help='count "A & B" / "A, B" / "A x B" as artist "A" for spacing and caps',
    )
    parser.add_argument(
        "--featuring-same-artist", action=argparse.BooleanOptionalAction,
        default=None,
        help='"Artist feat. X" / "Artist (ft. X)" counts as the same artist '
        "for spacing and caps (default: on; SETER_FEATURING_SAME_ARTIST "
        "also sets it)",
    )
    parser.add_argument(
        "--ai", action=argparse.BooleanOptionalAction, default=None,
        help="Flow: tag songs with Apple's on-device `fm` model (default: off; "
        "SETER_AI=1 or an ai-enabled marker file also turns it on)",
    )
    parser.add_argument("--ai-blend", type=float, default=None,
                        help="weight of the AI energy vs the heuristic, 0..1")
    parser.add_argument("--ai-mood-cost", type=int, default=None,
                        help="extra Flow walk cost for an unrelated mood, 0 = off")
    parser.add_argument("--ai-batch-size", type=int, default=None)
    parser.add_argument("--ai-dir", default=None,
                        help="folder for the AI tag cache and schemas "
                        "(default: ~/Documents/SeTeRShuffle, or SETER_AI_DIR)")


def _env_flag(name: str) -> bool | None:
    value = os.environ.get(name, "").strip().lower()
    if value in ("1", "true", "yes", "on"):
        return True
    if value in ("0", "false", "no", "off"):
        return False
    return None


def _env_int(name: str, lo: int, hi: int, default: int) -> int:
    """An integer setting from the environment: garbage reads as the
    default, out of range clamps into [lo, hi]. A missing env var
    is the default, so callers stay on Settings defaults unless
    the user set something."""
    raw = os.environ.get(name, "").strip()
    if not raw:
        return default
    try:
        value = int(raw)
    except ValueError:
        return default
    return max(lo, min(hi, value))


def _env_float(name: str, lo: float, hi: float, default: float) -> float:
    """A float setting from the environment: same rule as _env_int."""
    raw = os.environ.get(name, "").strip()
    if not raw:
        return default
    try:
        value = float(raw)
    except ValueError:
        return default
    return max(lo, min(hi, value))


def _settings_from(args: argparse.Namespace) -> Settings:
    base = Settings()
    overrides: dict[str, Any] = {}
    # Explicit CLI flags win; otherwise an env var sets the value
    # (garbage reads as the Settings default, out of range clamps
    # into range — see _env_int / _env_float); otherwise the
    # Settings default stands. The menu Options submenu persists
    # these same values in files under the settings dir and
    # run.sh's loader exports them into the env at startup, so
    # menu, direct commands, and the daily run all agree.
    mapping = {
        "artist_spacing": (
            args.artist_spacing
            if getattr(args, "artist_spacing", None) is not None
            else _env_int("SETER_ARTIST_SPACING", 1, 5, base.artist_spacing)
        ),
        "flow_size": (
            args.flow_size
            if getattr(args, "flow_size", None) is not None
            else _env_int("SETER_FLOW_SIZE", 10, 200, base.flow_size)
        ),
        "flow_pool_max": (
            args.flow_pool_max
            if getattr(args, "flow_pool_max", None) is not None
            else _env_int("SETER_FLOW_POOL_MAX", 0, 1000, base.flow_pool_max)
        ),
        "rediscover_min": (
            args.rediscover_min
            if getattr(args, "rediscover_min", None) is not None
            else _env_int("SETER_REDISCOVER_SIZE", 5, 500, base.rediscover_min)
        ),
        "rediscover_max": args.rediscover_max,
        "stale_days": (
            args.stale_days
            if getattr(args, "stale_days", None) is not None
            else _env_int(
                "SETER_REDISCOVER_STALE_DAYS", 7, 365, base.stale_days
            )
        ),
        "rediscover_max_per_artist": (
            args.max_per_artist
            if getattr(args, "max_per_artist", None) is not None
            else _env_int(
                "SETER_REDISCOVER_MAX_PER_ARTIST",
                0,
                10,
                base.rediscover_max_per_artist,
            )
        ),
        "rediscover_cooldown_days": (
            args.cooldown_days
            if getattr(args, "cooldown_days", None) is not None
            else _env_int(
                "SETER_REDISCOVER_COOLDOWN_DAYS",
                0,
                90,
                base.rediscover_cooldown_days,
            )
        ),
        "split_collabs": (
            args.split_collabs
            if getattr(args, "split_collabs", None) is not None
            else _env_flag("SETER_SPLIT_COLLABS")
        ),
        "featuring_is_same_artist": (
            args.featuring_same_artist
            if getattr(args, "featuring_same_artist", None) is not None
            else _env_flag("SETER_FEATURING_SAME_ARTIST")
        ),
        "ai_enabled": (
            args.ai
            if getattr(args, "ai", None) is not None
            else ai_enabled_by_environment()
        ),
        "ai_blend": (
            args.ai_blend
            if getattr(args, "ai_blend", None) is not None
            else _env_float("SETER_AI_BLEND", 0.0, 1.0, base.ai_blend)
        ),
        "ai_mood_cost": (
            args.ai_mood_cost
            if getattr(args, "ai_mood_cost", None) is not None
            else _env_int("SETER_AI_MOOD_COST", 0, 10, base.ai_mood_cost)
        ),
        "ai_batch_size": getattr(args, "ai_batch_size", None),
    }
    for key, value in mapping.items():
        if value is not None:
            overrides[key] = value
    return Settings(**{**base.__dict__, **overrides})


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="seter_shuffle", description="SeTeR Shuffle Python core"
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

    p = sub.add_parser(
        "ai-selftest",
        help="check that `fm` AI tagging works on this Mac (changes nothing)",
    )
    p.add_argument("--ai-dir", default=None, help="folder for the schema files")

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
    p.add_argument(
        "--match",
        choices=["id", "song"],
        default="song",
        help="what counts as a duplicate: 'song' (default) = same track ID, or "
        "same artist + title (and length, when known); 'id' = same track ID only",
    )

    p = sub.add_parser(
        "dedupe-positions",
        help="1-based dump positions of duplicate entries, strictly "
        "descending, for in-place dedupe (v3.0.9): same rule as dedupe, "
        "but positions instead of an order",
    )
    p.add_argument("--library", required=True, help="library JSON dump")
    p.add_argument("--out", required=True, help="positions file to write")
    p.add_argument(
        "--match",
        choices=["id", "song"],
        default="song",
        help="what counts as a duplicate (same choices as dedupe)",
    )

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
    p.add_argument(
        "--dedupe-match",
        choices=["id", "song"],
        default="song",
        help="for --mode dedupe: the match rule the order was computed with",
    )

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
    if args.command == "ai-selftest":
        ai_dir = Path(args.ai_dir) if args.ai_dir else default_ai_dir()
        return 0 if selftest(FmClient(ai_dir)) else 1

    if args.command == "dedupe-positions":
        # A playlist dump repeats IDs by definition: that is
        # exactly what dedupe is removing.
        tracks = load_library(args.library, allow_duplicates=True)
        _kept, removed = split_duplicates(tracks, args.match)
        # Removed entries are elements of the input list, so
        # their dump positions are found by object identity,
        # not by ID: two entries can share an ID, and a
        # same-song entry shares no ID with its kept copy.
        positions_by_id = {id(t): i + 1 for i, t in enumerate(tracks)}
        positions = sorted(
            (positions_by_id[id(t)] for t, _kept_t, _why in removed),
            reverse=True,
        )
        Path(args.out).write_text(
            "\n".join(str(p) for p in positions) + ("\n" if positions else ""),
            encoding="utf-8",
        )
        print(f"Dedupe positions: {len(positions)} duplicate entries.")
        return 0

    if args.command == "validate-order":
        ids = validate_order_file(
            args.library,
            args.order_txt,
            order_json_path=args.order_json,
            mode=args.mode,
            expected_count=args.expected_count,
            dedupe_match=args.dedupe_match,
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
        # The dump-frame clock (see tracks.dump_now), so the Flow
        # energy range in the report is the range Flow itself builds
        # from this dump (see audit_library): a clock-free audit
        # understates it by up to 5 points whenever recency applies,
        # and a true-UTC clock skews every age by the UTC offset
        # because the dump labels local time as UTC.
        report = audit_library(tracks, now=dump_now())
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
        recorded = record_rediscover_history(
            args.history, ids, args.cooldown_days, today
        )
        # The one step of the daily run that writes state but used to
        # print nothing: run.sh tees this step's stdout into the run
        # log, so the confirmation is the log's proof the cooldown
        # was recorded after a successful apply. Print-only: the
        # history rule and file content are unchanged.
        if args.cooldown_days < 1:
            print(
                f"History not recorded: cooldown is {args.cooldown_days} days, "
                "nothing was written."
            )
        elif recorded == 0:
            print("History recorded: 0 IDs; nothing appended (empty IDs file).")
        else:
            print(
                f"History recorded: {recorded} "
                f"ID{'s' if recorded != 1 else ''} appended to "
                f"{args.history} (cooldown {args.cooldown_days} days)."
            )
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
    now = dump_now()
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
        ordered, removed_pairs = split_duplicates(tracks, args.match)
        removed_tracks = [entry for entry, _kept, _why in removed_pairs]
        removed = len(removed_tracks)
        energies = None
        eligible = len(tracks)
        header = (
            f"Dedupe: {len(ordered)} unique songs from {len(tracks)} "
            f"input tracks ({removed} duplicate entr{'y' if removed == 1 else 'ies'} removed; "
            f"matching by {'exact track ID and same artist + title' if args.match == 'song' else 'exact track ID only'})."
        )
    elif command == "shuffle":
        ordered = shuffle_tracks(
            tracks,
            spacing=settings.artist_spacing,
            featuring_is_same_artist=settings.featuring_is_same_artist,
            rng=rng,
            size=args.size,
            split_collabs=settings.split_collabs,
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
        tagger = None
        if settings.ai_enabled:
            ai_dir = Path(args.ai_dir) if getattr(args, "ai_dir", None) else default_ai_dir()
            tagger = FlowTagger(
                TagCache(ai_dir / "ai-tags.json"),
                FmClient(ai_dir),
                batch_size=settings.ai_batch_size,
                time_budget=float(os.environ.get("SETER_AI_BUDGET", "600")),
            )
        ordered, flow_energies, eligible = prepare_flow(
            tracks, settings, rng, tagger=tagger
        )
        energies = flow_energies
        header = f"Flow: {len(ordered)} songs from {eligible} eligible tracks."
        if tagger is not None and not args.quiet:
            print(tagger.summary(), file=sys.stderr)
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
            for track, kept_track, why in removed_pairs:
                print(f"Removed duplicate: {track.artist} - {track.name} ({why})")
            if args.match == "id":
                _kept, would_remove = split_duplicates(tracks, "song")
                extra = len(would_remove) - len(removed_pairs)
                if extra > 0:
                    print(
                        f"Note: {extra} more entr{'y looks' if extra == 1 else 'ies look'} like the "
                        "same song stored as a different library track; "
                        "re-run with --match song to remove them."
                    )
        for line in _preview_lines(ordered, energies, settings.preview_show):
            print(line)
        if command == "shuffle":
            summary = shuffle_summary(
                ordered, settings.artist_spacing, settings.featuring_is_same_artist
            )
            if summary is not None:
                print(summary)
        if command in ("flow", "flowPreview", "flow-preview") and energies:
            summary = flow_arc_summary(energies)
            if summary is not None:
                print(summary)
        if command in ("rediscover", "rediscover-preview"):
            summary = rediscover_summary(
                ordered, now, settings.featuring_is_same_artist
            )
            if summary is not None:
                print(summary)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
