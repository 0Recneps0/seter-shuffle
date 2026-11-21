"""Library tag audit: tell a real data gap from a dump bug.

The audit reads a library JSON dump and counts what is actually in
it. It never touches Music and never writes anything except an
optional --out JSON file.

Why this exists: Spencer's 2026-10-28 flowPreview showed almost every
energy at exactly 50. Two very different causes look identical in a
preview: (a) his library genuinely lacks BPM data for most songs, or
(b) the dump script fails to read BPM. The audit separates them:

- If BPM is present for *some* songs but missing for most, the dump
  is working (a dump bug would lose BPM for all songs at once: the
  bridge's bulk read either returns a value per track or falls back
  to missing for the whole list) and the library really is missing
  BPM metadata. Apple Music does not analyse BPM for you: the BPM
  field comes from the track's own metadata, and it is often blank,
  especially for rips, older files, and tracks whose source never
  wrote a tempo tag.
- If BPM is present for *zero* songs, suspect the dump script first
  (bulk read, `favorited`/`loved` fallback, or a field Music cannot
  provide on that Mac) before concluding the library has no BPM.

Counts are reported with percentages of the total library, plus the
most common genre strings, so the next genre-map edit is driven by
real data instead of guesses. Genre strings are counted
case-insensitively (Flow matches genres case-insensitively, so
"Rock", "rock", and "ROCK" are one genre, not three); the displayed
label keeps the first-seen casing so the list still reads naturally.

Same-song copies are counted too: the library can hold the same
recording twice (a single plus the album version, a matched copy
plus an uploaded copy), and those are different library tracks.
The audit counts them with the same conservative rule dedupe uses,
so a dedupe total that lands below the library size has an
explanation instead of looking like songs went missing.
"""

from __future__ import annotations

from collections import Counter
from datetime import datetime
from typing import Sequence

from .flow import flow_energy
from .tracks import Track, split_duplicates


def _pct(count: int, total: int) -> float:
    return round(100.0 * count / total, 1) if total else 0.0


def _band(value: int) -> str:
    if value <= 0:
        return "0"
    if value <= 4:
        return "1-4"
    if value <= 19:
        return "5-19"
    if value <= 49:
        return "20-49"
    return "50+"


def _rating_band(rating: int) -> str:
    if rating <= 0:
        return "unrated"
    if rating <= 40:
        return "1-2 stars"
    if rating <= 60:
        return "3 stars"
    if rating <= 100:
        return "4-5 stars"
    return "other"


def audit_library(
    tracks: Sequence[Track], now: datetime | None = None
) -> dict:
    """Count tag coverage, familiarity bands, and Flow energy spread.

    `now` is the reference time for the played-date / date-added
    recency nudge inside the Flow energies. The CLI passes the real
    clock, so the "Flow energies (eligible)" range is the range Flow
    itself builds from the same dump: without it the audit scored
    every track clock-free and understated the real range by up to
    5 points (a song played 5 days ago scores 56 in Flow but 53 in
    a clock-free audit). With no `now` the energies stay
    deterministic (no recency contribution), which is what the
    existing tests rely on; the BPM path never uses `now` either
    way, so BPM energies are identical with or without it.
    """
    total = len(tracks)
    bpm_present = sum(1 for t in tracks if t.bpm is not None and t.bpm > 0)
    bpm_zero = sum(1 for t in tracks if t.bpm is not None and t.bpm <= 0)
    bpm_missing = total - bpm_present - bpm_zero
    # Genre strings are counted case-insensitively: Flow matches
    # genres with a lowered substring check, so "Rock", "rock", and
    # "ROCK" are the same genre for the map the audit informs, and
    # counting them apart would inflate genre_distinct and split the
    # top-genres list. The displayed label keeps the first-seen
    # casing, so the list still reads as the library wrote it.
    genre_counts: Counter[str] = Counter()
    genre_labels: dict[str, str] = {}
    for t in tracks:
        raw = t.genre.strip()
        if raw:
            key = raw.lower()
            genre_counts[key] += 1
            genre_labels.setdefault(key, raw)
    genre_present = sum(genre_counts.values())
    played_bands: Counter[str] = Counter()
    rating_bands: Counter[str] = Counter()
    for t in tracks:
        played_bands[_band(t.played_count)] += 1
        rating_bands[_rating_band(t.rating)] += 1
    eligible = [t for t in tracks if t.enabled and not t.disliked]
    eligible_missing_bpm = sum(
        1 for t in eligible if t.bpm is None or t.bpm <= 0
    )
    energies = [flow_energy(t, now=now) for t in eligible]
    missing_bpm_energies = [
        flow_energy(t, now=now)
        for t in eligible
        if t.bpm is None or t.bpm <= 0
    ]
    # Same-song library copies, same rule as dedupe: only "same song"
    # removals count here, so a repeated persistent ID (a dump error
    # the strict loader already rejects) never inflates this number.
    _kept, _removed = split_duplicates(list(tracks), "song")
    same_song = [r for r in _removed if r[2] == "same song"]
    same_song_groups = len({id(kept) for _entry, kept, _why in same_song})
    return {
        "total": total,
        "bpm_present": bpm_present,
        "bpm_present_pct": _pct(bpm_present, total),
        "bpm_missing": bpm_missing,
        "bpm_missing_pct": _pct(bpm_missing, total),
        "bpm_zero": bpm_zero,
        "bpm_zero_pct": _pct(bpm_zero, total),
        "genre_present": genre_present,
        "genre_present_pct": _pct(genre_present, total),
        "genre_missing": total - genre_present,
        "genre_missing_pct": _pct(total - genre_present, total),
        "genre_distinct": len(genre_counts),
        "genre_counts": sorted(
            ((genre_labels[key], count) for key, count in genre_counts.items()),
            key=lambda kv: (-kv[1], kv[0]),
        ),
        "played_bands": {
            band: played_bands.get(band, 0)
            for band in ("0", "1-4", "5-19", "20-49", "50+")
        },
        "rating_bands": {
            band: rating_bands.get(band, 0)
            for band in ("unrated", "1-2 stars", "3 stars", "4-5 stars", "other")
        },
        "favorited": sum(1 for t in tracks if t.favorited),
        "favorited_pct": _pct(sum(1 for t in tracks if t.favorited), total),
        "disliked": sum(1 for t in tracks if t.disliked),
        "enabled": sum(1 for t in tracks if t.enabled),
        "disabled": sum(1 for t in tracks if not t.enabled),
        "flow_eligible": len(eligible),
        "flow_eligible_missing_bpm": eligible_missing_bpm,
        "flow_eligible_missing_bpm_pct": _pct(eligible_missing_bpm, len(eligible)),
        "energy_min": min(energies) if energies else None,
        "energy_max": max(energies) if energies else None,
        "energy_distinct": len(set(energies)),
        "energy_distinct_missing_bpm": len(set(missing_bpm_energies)),
        "same_song_groups": same_song_groups,
        "same_song_extra": len(same_song),
    }


def format_audit(report: dict, top_genres: int = 20) -> list[str]:
    """Human-readable audit lines (no Music changes, no file writes)."""
    total = report["total"]
    lines = [
        f"Audit: {total} songs.",
        f"BPM: present {report['bpm_present']} ({report['bpm_present_pct']}%), "
        f"missing {report['bpm_missing']} ({report['bpm_missing_pct']}%), "
        f"zero {report['bpm_zero']} ({report['bpm_zero_pct']}%).",
        f"Genre: present {report['genre_present']} ({report['genre_present_pct']}%), "
        f"missing {report['genre_missing']} ({report['genre_missing_pct']}%), "
        f"{report['genre_distinct']} distinct.",
        "Top genres:",
    ]
    for genre, count in report["genre_counts"][:top_genres]:
        lines.append(f"  {count:>5}  {genre}")
    if not report["genre_counts"]:
        lines.append("  (none)")
    bands = report["played_bands"]
    lines.append(
        "Played counts: 0: {0}, 1-4: {1}, 5-19: {2}, 20-49: {3}, 50+: {4}.".format(
            bands["0"], bands["1-4"], bands["5-19"], bands["20-49"], bands["50+"]
        )
    )
    ratings = report["rating_bands"]
    lines.append(
        "Ratings: unrated: {0}, 1-2 stars: {1}, 3 stars: {2}, "
        "4-5 stars: {3}, other: {4}.".format(
            ratings["unrated"],
            ratings["1-2 stars"],
            ratings["3 stars"],
            ratings["4-5 stars"],
            ratings["other"],
        )
    )
    lines.append(
        f"Favorited: {report['favorited']} ({report['favorited_pct']}%), "
        f"disliked: {report['disliked']}, enabled: {report['enabled']}, "
        f"disabled: {report['disabled']}."
    )
    lines.append(
        f"Flow eligible: {report['flow_eligible']}, of which missing BPM: "
        f"{report['flow_eligible_missing_bpm']} "
        f"({report['flow_eligible_missing_bpm_pct']}%)."
    )
    if report["energy_min"] is not None:
        lines.append(
            f"Flow energies (eligible): {report['energy_min']}..{report['energy_max']}, "
            f"{report['energy_distinct']} distinct values; "
            f"{report['energy_distinct_missing_bpm']} distinct among missing-BPM songs."
        )
    else:
        lines.append("Flow energies (eligible): none.")
    lines.append(
        f"Same-song duplicates: {report['same_song_extra']} extra copies "
        f"across {report['same_song_groups']} songs (same artist + title "
        f"stored as different library tracks)."
    )
    lines.append("Nothing was changed.")
    return lines
