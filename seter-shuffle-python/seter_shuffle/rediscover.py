"""Rediscover scoring and picking, ported from stable v2.6.

Rules (see the v2.6 header, reproduced here so this module stands alone):

- ELIGIBLE: not disliked, not unchecked (enabled), not skip-heavy
  (3+ skips AND more skips than plays), and forgotten: last played
  `stale_days` or more days ago, or, for never-played songs, added
  `stale_days` or more days ago. A song with no usable date at all is
  not excluded for recency (v2.6 only excludes when a date exists and
  is newer than the cutoff).
- WEIGHT = liked x forgotten:
    liked: never played 1.0 (the played-song base, 2026-11-18
      experimental: the old 0.4 capped a never-played song at 2.0
      against a 10-play song's 30.0, a 15:1 ratio no amount of
      forgottenness could close, so in an even pool never-played
      songs took ~8% of picks; 1.0 keeps played songs ahead at
      equal forgottenness while letting the plays tier, not a 60%
      unplayed discount, separate played from unplayed);
      otherwise 1 + min(plays, 10) * 0.5
    boosts: favorited x3; rating 80+ (4-5 stars) x2; rating 1..40
      (1-2 stars) x0.25; then divided by (1 + skips)
    forgotten: days since last play (or add) / stale_days, capped at 5x;
      no multiplier when no date exists.
- VARIETY: at most `rediscover_max_per_artist` songs per artist, and
  nothing picked in the last `rediscover_cooldown_days` days (history
  file: one "YYYY-MM-DD<TAB>persistent_id" line per pick, same format
  as v2.6). If the pool is too small to fill the target, the rules are
  relaxed in stages rather than leaving the playlist short, and
  finally the highest-weight remaining candidates fill any
  remaining slots. The stages relax one rule at a time, in this order: (1) both rules
  enforced, (2) cooldown enforced, artist cap relaxed, so a slot is
  filled by an extra song from an already-picked artist before any
  recently picked song is repeated, (3) artist cap enforced,
  cooldown relaxed, so a recently picked song is repeated before
  the cap is broken as well, (4) neither rule enforced. v2.6
  relaxed both rules in a single pass; this keeps that as the
  last resort only, so a small pool does not break the cooldown
  when an artist-cap break would have filled the slot, or break
  the cap when a cooldown break would have.
- ORDER: picks are shuffled (Fisher-Yates) and spread by artist, so the
  playlist does not play best-songs-first. rediscover-preview also
  prints a one-line summary of the whole pick list (never-played /
  favorited / 4-5-star counts, forgotten range, max per artist), so
  the capped preview list does not hide what the picks are made of;
  the summary describes picks already computed and changes nothing.

Sampling is weighted random without replacement via cumulative weights
and binary search, exactly as v2.6's samplePicks. An explicit rng makes
picks replayable in tests.
"""

from __future__ import annotations

import bisect
import math
import random
from datetime import date, timedelta
from pathlib import Path
from typing import Iterable, Sequence

from .artists import artist_compare_key
from .settings import Settings
from .shuffle import fisher_yates, spread_artists
from .tracks import Track, split_duplicates


def rediscover_target(library_count: int, settings: Settings) -> int:
    """Target Rediscover size: percent of library, clamped to min..max.

    Rounding is half-up (AppleScript `round ... rounding to nearest`
    on positive values), not Python's banker's rounding.
    """
    raw = library_count * settings.rediscover_percent / 100.0
    size = int(math.floor(raw + 0.5))
    return max(settings.rediscover_min, min(settings.rediscover_max, size))


def _base_date(track: Track) -> datetime | None:
    """Last play if played and a play date exists, else the date added."""
    if track.played_count > 0 and track.played_date is not None:
        return track.played_date
    return track.date_added


def is_rediscover_eligible(
    track: Track, now: datetime, settings: Settings
) -> bool:
    """Eligibility check, independent of weight (testable on its own)."""
    if not track.enabled:
        return False
    if track.disliked:
        return False
    if track.skipped_count >= 3 and track.skipped_count > track.played_count:
        return False
    base = _base_date(track)
    if base is not None:
        stale_days = max(1, settings.stale_days)
        if base >= now - timedelta(days=stale_days):
            return False
    return True


def rediscover_weight(track: Track, now: datetime, settings: Settings) -> float:
    """Weight for an eligible track. Returns 0.0 for ineligible tracks."""
    if not is_rediscover_eligible(track, now, settings):
        return 0.0
    plays = max(0, track.played_count)
    if plays == 0:
        # The played-song base (2026-11-18 experimental): a
        # never-played song is unproven, not disliked, so it starts
        # where every played song starts and the plays tier is what
        # separates played from unplayed. The old 0.4 capped it at
        # 2.0 against a 10-play song's 30.0, a 15:1 ratio the
        # forgotten multiplier (capped at 5x for everyone) could
        # never close, so never-played songs were nearly invisible
        # in a mixed pool. At 1.0 a never-played song tops out at
        # 5.0, still below a once-played song's 7.5 at the same
        # forgottenness.
        weight = 1.0
    else:
        weight = 1.0 + min(plays, 10) * 0.5
    if track.favorited:
        weight *= 3.0
    if track.rating >= 80:
        weight *= 2.0
    elif 1 <= track.rating <= 40:
        weight *= 0.25
    weight /= 1.0 + max(0, track.skipped_count)
    base = _base_date(track)
    if base is not None:
        stale_days = max(1, settings.stale_days)
        days = (now - base).total_seconds() / 86400.0
        weight *= min(days / stale_days, 5.0)
    return weight


def _sample_picks(
    cumulative: list[float],
    total: float,
    candidates: list[Track],
    picked: list[int],
    picked_keys: list[str],
    history_ids: set[str],
    target: int,
    settings: Settings,
    rng: random.Random,
    enforce_history: bool = True,
    enforce_artist: bool = True,
) -> tuple[list[int], list[str]]:
    """Weighted draws until target is reached or attempts run out.

    The two variety rules are enforced independently, so the caller
    can relax them one at a time (see pick_rediscover): cooldown
    first, artist cap second, neither last.
    """
    max_attempts = target * 40 + 200
    attempts = 0
    picked_set = set(picked)
    while len(picked) < target and attempts < max_attempts:
        attempts += 1
        point = rng.random() * total
        idx = bisect.bisect_left(cumulative, point)
        if idx >= len(candidates):
            idx = len(candidates) - 1
        if idx in picked_set:
            continue
        track = candidates[idx]
        key = artist_compare_key(
            track.artist, settings.featuring_is_same_artist, settings.split_collabs
        )
        ok = True
        if enforce_history and track.persistent_id in history_ids:
            ok = False
        if (
            ok
            and enforce_artist
            and settings.rediscover_max_per_artist > 0
            and key != ""
            and picked_keys.count(key) >= settings.rediscover_max_per_artist
        ):
            ok = False
        if ok:
            picked.append(idx)
            picked_keys.append(key)
            picked_set.add(idx)
    return picked, picked_keys


def pick_rediscover(
    tracks: Sequence[Track],
    now: datetime,
    settings: Settings,
    history_ids: Iterable[str] = (),
    rng: random.Random | None = None,
) -> tuple[list[Track], int, int]:
    """Pick Rediscover songs.

    Returns (ordered picks, candidate count, target size). The picks are
    shuffled and artist-spread, matching v2.6's final order. When there
    are fewer candidates than slots, all candidates are taken.
    """
    rng = rng or random.Random()
    candidates: list[Track] = []
    weights: list[float] = []
    for track in tracks:
        weight = rediscover_weight(track, now, settings)
        if weight > 0:
            candidates.append(track)
            weights.append(weight)
    target = rediscover_target(len(tracks), settings)
    if not candidates:
        return [], 0, target
    # One song stored as two library tracks must not take two slots. Of
    # each same-song group the highest-weight copy stays; ties keep the
    # earlier one. The survivors keep their original relative order.
    by_weight = sorted(range(len(candidates)), key=lambda i: (-weights[i], i))
    survivors, _dropped = split_duplicates([candidates[i] for i in by_weight], "song")
    survivor_ids = {id(track) for track in survivors}
    if len(survivor_ids) != len(candidates):
        pairs = [(c, w) for c, w in zip(candidates, weights) if id(c) in survivor_ids]
        candidates = [c for c, _w in pairs]
        weights = [w for _c, w in pairs]
    if len(candidates) <= target:
        picked_idx = list(range(len(candidates)))
    else:
        cumulative: list[float] = []
        running = 0.0
        for weight in weights:
            running += weight
            cumulative.append(running)
        history = set(history_ids)
        picked_idx: list[int] = []
        picked_keys: list[str] = []
        # Relax one rule at a time, in order: both rules, cooldown
        # only, artist cap only, neither. A small pool therefore
        # breaks the artist cap before it repeats a recent pick,
        # and repeats a recent pick before it breaks both rules.
        # The weight-ordered fill below still guarantees a full
        # playlist when sampling alone cannot reach the target.
        for enforce_history, enforce_artist in (
            (True, True),
            (True, False),
            (False, True),
            (False, False),
        ):
            if len(picked_idx) >= target:
                break
            picked_idx, picked_keys = _sample_picks(
                cumulative, running, candidates, picked_idx, picked_keys,
                history, target, settings, rng,
                enforce_history=enforce_history,
                enforce_artist=enforce_artist,
            )
        if len(picked_idx) < target:
            # Last resort only: sampling could not fill the target
            # even with neither rule enforced. Fill from the
            # highest-weight unpicked candidates, not the front of
            # the candidate list in library order: the weights are
            # what ranked the sampled picks, so the remaining slots
            # go to the best songs left by the same measure. Ties
            # keep library order, so a pool of equal-weight songs
            # fills exactly as before.
            picked_set = set(picked_idx)
            by_weight = sorted(
                range(len(candidates)), key=lambda i: (-weights[i], i)
            )
            for j in by_weight:
                if len(picked_idx) >= target:
                    break
                if j not in picked_set:
                    picked_idx.append(j)
                    picked_set.add(j)
    picked = [candidates[i] for i in picked_idx]
    keys = [
        artist_compare_key(
            t.artist, settings.featuring_is_same_artist, settings.split_collabs
        )
        for t in picked
    ]
    order = spread_artists(
        fisher_yates(range(len(picked)), rng), keys, settings.artist_spacing, rng
    )
    return [picked[i] for i in order], len(candidates), target


def rediscover_summary(
    picks: Sequence[Track],
    now: datetime | None,
    featuring_is_same_artist: bool = True,
) -> str | None:
    """One-line summary of a Rediscover pick list.

    rediscover and rediscover-preview print only the first
    `preview_show` songs, so the first page hid what the full pick
    list is actually made of: how much of it was never played at
    all, how much is favorited or highly rated, how long the picks
    were forgotten, and whether one artist dominates the list. This
    line covers the whole ordered list: its size, its never-played /
    favorited / 4-5-star counts, the forgotten range in days over
    picks with a usable date, and the most songs by one artist. It
    changes nothing: it only describes picks already computed. `now`
    is the reference time for the forgotten range; with no `now`, or
    no pick with a usable date, the forgotten clause is left out
    rather than guessed. Picks with no artist string do not count
    toward the per-artist max, and when no pick names an artist at
    all the max clause is left out too.
    """
    if not picks:
        return None
    noun = "song" if len(picks) == 1 else "songs"
    parts = [
        f"{len(picks)} {noun}",
        f"{sum(1 for t in picks if t.played_count <= 0)} never played",
        f"{sum(1 for t in picks if t.favorited)} favorited",
        f"{sum(1 for t in picks if t.rating >= 80)} rated 4-5 stars",
    ]
    if now is not None:
        forgotten = [
            max(0, (now - base).days)
            for track in picks
            if (base := _base_date(track)) is not None
        ]
        if forgotten:
            parts.append(f"forgotten {min(forgotten)}..{max(forgotten)} days")
    per_artist: dict[str, int] = {}
    for track in picks:
        key = artist_compare_key(track.artist, featuring_is_same_artist)
        if key != "":
            per_artist[key] = per_artist.get(key, 0) + 1
    if per_artist:
        parts.append(f"max {max(per_artist.values())} per artist")
    return "Rediscover picks: " + ", ".join(parts) + "."


def load_rediscover_history(
    path: str | Path, cooldown_days: int, today: date | None = None
) -> set[str]:
    """Persistent IDs picked within the cooldown window.

    Same file format as v2.6 (YYYY-MM-DD<TAB>id, one per pick). A
    missing or malformed history degrades to "no history", never to a
    failed run, matching v2.6's never-throws history load.
    """
    if cooldown_days < 1:
        return set()
    today = today or date.today()
    cutoff = today - timedelta(days=cooldown_days)
    history: set[str] = set()
    try:
        lines = Path(path).read_text(encoding="utf-8").splitlines()
    except OSError:
        return set()
    for line in lines:
        parts = line.split("\t")
        if len(parts) != 2:
            continue
        try:
            day = date.fromisoformat(parts[0].strip())
        except ValueError:
            continue
        if day >= cutoff:
            history.add(parts[1].strip())
    return history


def record_rediscover_history(
    path: str | Path,
    picked_ids: Iterable[str],
    cooldown_days: int,
    today: date | None = None,
) -> int:
    """Append today's picks and prune entries older than the window.

    This is intentionally a separate step from picking: the runner calls
    it only after the playlist was successfully applied, so a failed
    apply never burns a song's cooldown.

    Returns the number of IDs appended (0 when nothing was written:
    no picks, or a cooldown under 1 day).
    """
    if cooldown_days < 1:
        return 0
    picked = list(picked_ids)
    if not picked:
        return 0
    today = today or date.today()
    cutoff = today - timedelta(days=cooldown_days)
    kept: list[str] = []
    try:
        lines = Path(path).read_text(encoding="utf-8").splitlines()
    except OSError:
        lines = []
    for line in lines:
        parts = line.split("\t")
        if len(parts) != 2:
            continue
        try:
            day = date.fromisoformat(parts[0].strip())
        except ValueError:
            continue
        if day >= cutoff:
            kept.append(line)
    kept.extend(f"{today.isoformat()}\t{pid}" for pid in picked)
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(kept) + "\n", encoding="utf-8")
    return len(picked)
