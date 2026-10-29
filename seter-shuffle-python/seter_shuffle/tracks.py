"""Track model and library-JSON loading.

The JSON interchange format is deliberately boring: one object per track,
with the same fields the AppleScript bridge can actually read from Music.
No field is invented. Fields the bridge cannot supply stay null and the
core treats them with the same neutral defaults v2.6 uses.

Accepted field aliases (the bridge writes the canonical names):
  persistent_id / id / persistentId
  played_count / playedCount, skipped_count / skippedCount,
  played_date / playedDate, date_added / dateAdded

Dates may be ISO-8601 strings (with or without a trailing Z), epoch
seconds (int/float), or null. Unparseable dates are treated as null, the
same way v2.6 treats a missing date: the song is not excluded for being
recent, and it simply gets no "time forgotten" multiplier.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional


@dataclass
class Track:
    persistent_id: str
    name: str = ""
    artist: str = ""
    genre: str = ""
    album: str = ""
    bpm: Optional[float] = None
    year: Optional[int] = None
    played_count: int = 0
    skipped_count: int = 0
    rating: int = 0  # Music rating: 0 = unrated, 20..100 in steps of 20
    favorited: bool = False
    disliked: bool = False
    enabled: bool = True  # Music "checked" state; False = unchecked
    played_date: Optional[datetime] = None
    date_added: Optional[datetime] = None

    @property
    def is_song(self) -> bool:
        """Every record in the interchange file is a song; kept for clarity."""
        return True


def _as_int(value: Any, default: int = 0) -> int:
    if value is None or isinstance(value, bool):
        return default
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def _as_float(value: Any) -> Optional[float]:
    if value is None or isinstance(value, bool):
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _as_bool(value: Any, default: bool = False) -> bool:
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value != 0
    if isinstance(value, str):
        return value.strip().lower() in ("true", "yes", "1")
    return default


def parse_date(value: Any) -> Optional[datetime]:
    """Parse an ISO string or epoch seconds into an aware datetime."""
    if value is None:
        return None
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        try:
            return datetime.fromtimestamp(value, tz=timezone.utc)
        except (OverflowError, OSError, ValueError):
            return None
    if isinstance(value, str):
        text = value.strip()
        if not text:
            return None
        try:
            parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
        except ValueError:
            return None
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return parsed
    return None


def _first(mapping: dict, *names: str) -> Any:
    for name in names:
        if name in mapping and mapping[name] is not None:
            return mapping[name]
    return None


def track_from_dict(data: dict) -> Track:
    """Build a Track, applying v2.6's neutral defaults for missing signals."""
    pid = _first(data, "persistent_id", "persistentId", "id")
    if pid is None:
        raise ValueError("track record is missing a persistent_id")
    favorited = _as_bool(_first(data, "favorited"), False)
    if "favorited" not in data and "loved" in data:
        # v2.6 falls back to `loved` when `favorited` is unavailable.
        favorited = _as_bool(data.get("loved"), False)
    enabled = True
    if "enabled" in data and data["enabled"] is not None:
        enabled = _as_bool(data["enabled"], True)
    elif "checked" in data and data["checked"] is not None:
        enabled = _as_bool(data["checked"], True)
    return Track(
        persistent_id=str(pid),
        name=str(_first(data, "name", "title") or ""),
        artist=str(_first(data, "artist") or ""),
        genre=str(_first(data, "genre") or ""),
        album=str(_first(data, "album") or ""),
        bpm=_as_float(_first(data, "bpm")),
        year=_as_int(_first(data, "year"), 0) or None,
        played_count=_as_int(_first(data, "played_count", "playedCount")),
        skipped_count=_as_int(_first(data, "skipped_count", "skippedCount")),
        rating=_as_int(_first(data, "rating")),
        favorited=favorited,
        disliked=_as_bool(_first(data, "disliked"), False),
        enabled=enabled,
        played_date=parse_date(_first(data, "played_date", "playedDate")),
        date_added=parse_date(_first(data, "date_added", "dateAdded")),
    )


def load_library(path: str | Path, allow_duplicates: bool = False) -> list[Track]:
    """Load a library JSON file: {"tracks": [...]} or a bare [...] list.

    Raises ValueError on malformed input instead of silently dropping
    tracks: a half-loaded library must never be written to a playlist.

    By default a duplicate persistent_id is refused: in a whole-library
    dump one ID is one song, so a repeat is a dump problem. But a
    one-playlist dump CAN legitimately repeat an ID, because Music
    allows the same song twice as two entries in one user playlist.
    Callers that shuffle one playlist pass allow_duplicates=True so
    those entries survive as separate positions (the shuffle then
    reorders them, it never merges them); every other caller keeps
    the strict default. Validation still checks the result against
    the dump by multiplicity (see validate_order_file), so allowing
    duplicates here cannot silently drop or invent a playlist entry.
    """
    raw = json.loads(Path(path).read_text(encoding="utf-8"))
    if isinstance(raw, dict):
        records = raw.get("tracks")
        if records is None:
            raise ValueError("library JSON object has no 'tracks' list")
    elif isinstance(raw, list):
        records = raw
    else:
        raise ValueError("library JSON must be an object or a list")
    if not isinstance(records, list):
        raise ValueError("'tracks' must be a list")
    tracks: list[Track] = []
    seen: set[str] = set()
    for i, record in enumerate(records):
        if not isinstance(record, dict):
            raise ValueError(f"track record {i} is not an object")
        track = track_from_dict(record)
        if track.persistent_id in seen and not allow_duplicates:
            # A duplicate ID in the dump is a dump problem, not two songs.
            raise ValueError(f"duplicate persistent_id in library: {track.persistent_id}")
        seen.add(track.persistent_id)
        tracks.append(track)
    return tracks


def track_to_dict(track: Track) -> dict:
    """Serialize a Track back to the interchange format (for previews)."""
    return {
        "persistent_id": track.persistent_id,
        "name": track.name,
        "artist": track.artist,
        "genre": track.genre,
        "album": track.album,
        "bpm": track.bpm,
        "year": track.year,
        "played_count": track.played_count,
        "skipped_count": track.skipped_count,
        "rating": track.rating,
        "favorited": track.favorited,
        "disliked": track.disliked,
        "enabled": track.enabled,
        "played_date": track.played_date.isoformat() if track.played_date else None,
        "date_added": track.date_added.isoformat() if track.date_added else None,
    }
