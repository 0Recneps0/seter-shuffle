"""Artist keys: how "same artist" is judged for spacing.

Mirrors v2.6's artistKey handler exactly, including its quirks:
- With featuring_is_same_artist, "Artist feat. X" / "Artist (ft. X)" count
  as "Artist", so a featured track cannot sneak in next to the main
  artist's songs.
- Matching is case-insensitive (AppleScript string comparison is
  case-insensitive by default), and the first matching marker wins in
  the order listed below, because each truncation feeds the next search.
- A trailing space left by a marker is stripped; v2.6's markers mostly
  start with a space, so the two agree on real-world names.
"""

from __future__ import annotations

# Ordered exactly as in v2.6's artistKey.
_FEATURING_MARKERS = (
    " feat.",
    " feat ",
    " ft.",
    " ft ",
    " featuring",
    " (feat",
    " (ft",
)


def artist_key(artist: str | None, featuring_is_same_artist: bool = True) -> str:
    """Return the comparable artist key for a raw artist string."""
    if artist is None:
        return ""
    name = str(artist)
    if not featuring_is_same_artist:
        return name
    lowered = name.lower()
    if " f" not in lowered and " (f" not in lowered:
        return name
    result = name
    for marker in _FEATURING_MARKERS:
        idx = result.lower().find(marker)
        if idx > 0:
            result = result[:idx]
    return result.rstrip()
