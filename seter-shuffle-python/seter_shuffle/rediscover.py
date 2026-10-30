"""Rediscover scoring and picking, ported from stable v2.6.

Rules (see the v2.6 header, reproduced here so this module stands alone):

- ELIGIBLE: not disliked, not unchecked (enabled), not skip-heavy
  (3+ skips AND more skips than plays), and forgotten: last played
  `stale_days` or more days ago, or, for never-played songs, added
  `stale_days` or more days ago. A song with no usable date at all is
  not excluded for recency (v2.6 only excludes when a date exists and
  is newer than the cutoff).
- WEIGHT = liked x forgotten:
    liked: never played 0.4; otherwise 1 + min(plays, 10) * 0.5
    boosts: favorited x3; rating 80+ (4-5 stars) x2; rating 1..40
      (1-2 stars) x0.25; then divided by (1 + skips)
    forgotten: days since last play (or add) / stale_days, capped at 5x;
      no multiplier when no date exists.
- VARIETY: at most `rediscover_max_per_artist` songs per artist, and
  nothing picked in the last `rediscover_cooldown_days` days (history
  file: one "YYYY-MM-DD<TAB>persistent_id" line per pick, same format
  as v2.6). If the pool is too small to fill the target, the rules are
  relaxed rather than leaving the playlist short (pass 2), and finally
  the front of the candidate list fills any remaining slots (pass 3).
- ORDER: picks are shuffled (Fisher-Yates) and spread by artist, so the
  playlist does not play best-songs-first.

Sampling is weighted random without replacement via cumulative weights
and binary search, exactly as v2.6's samplePicks. An explicit rng makes
picks replayable in tests.
"""

from __future__ import annotations

import bisect
import math
import random
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Iterable, Sequence

from .artists import artist_key
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
        weight = 0.4
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
    enforce_rules: bool,
) -> tuple[list[int], list[str]]:
    """Weighted draws until target is reached or attempts run out."""
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
        key = artist_key(track.artist, settings.featuring_is_same_artist)
        ok = True
        if enforce_rules:
            if track.persistent_id in history_ids:
                ok = False
            if (
                ok
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
        picked_idx, picked_keys = _sample_picks(
            cumulative, running, candidates, picked_idx, picked_keys,
            history, target, settings, rng, enforce_rules=True,
        )
        if len(picked_idx) < target:
            picked_idx, picked_keys = _sample_picks(
                cumulative, running, candidates, picked_idx, picked_keys,
                history, target, settings, rng, enforce_rules=False,
            )
        if len(picked_idx) < target:
            for j in range(len(candidates)):
                if len(picked_idx) >= target:
                    break
                if j not in picked_idx:
                    picked_idx.append(j)
    picked = [candidates[i] for i in picked_idx]
    keys = [artist_key(t.artist, settings.featuring_is_same_artist) for t in picked]
    order = spread_artists(
        fisher_yates(range(len(picked)), rng), keys, settings.artist_spacing, rng
    )
    return [picked[i] for i in order], len(candidates), target


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
    today = today or datetime.now(timezone.utc).date()
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
) -> None:
    """Append today's picks and prune entries older than the window.

    This is intentionally a separate step from picking: the runner calls
    it only after the playlist was successfully applied, so a failed
    apply never burns a song's cooldown.
    """
    if cooldown_days < 1:
        return
    picked = list(picked_ids)
    if not picked:
        return
    today = today or datetime.now(timezone.utc).date()
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
