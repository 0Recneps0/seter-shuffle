"""Settings for the Python experimental core.

Defaults mirror stable v2.6 (AppleScript properties) plus the experimental
Flow settings from the AppleScript experimental build, so the Python core
behaves like the scripts it is meant to replace, not like a new product
with new defaults.

All settings are plain data: the core never reads Music, the network, or
any file on its own. Callers pass a Settings object explicitly, which is
what makes the core unit-testable.
"""

from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    # Rediscover (v2.6)
    rediscover_percent: float = 1.0
    rediscover_min: int = 30
    rediscover_max: int = 500
    stale_days: int = 60
    rediscover_max_per_artist: int = 3  # 0 = no limit
    rediscover_cooldown_days: int = 14  # 0 = off
    # Shuffle / Flow artist spacing (v2.6, v2.5)
    artist_spacing: int = 2  # 1 = just not back-to-back; best effort
    # Flow album spacing shares this window (2026-11-27 experimental):
    # a repeated album within the last `artist_spacing` picks costs
    # the same as a repeated artist. No separate setting.
    featuring_is_same_artist: bool = True
    # "A & B" / "A, B" / "A x B" count as artist "A" for spacing and caps.
    # Off by default so existing orders keep v2.6 behaviour.
    split_collabs: bool = False
    # Flow (experimental AppleScript build)
    flow_size: int = 50
    flow_pool_max: int = 400  # 0 = no pool cap
    # Preview display
    preview_show: int = 25
    # AI tagging for Flow (optional; see ai_tags.py). Off by default: the
    # core stays offline and deterministic unless the caller opts in.
    ai_enabled: bool = False
    ai_blend: float = 0.6  # weight of the AI energy vs the heuristic, 0..1
    ai_mood_cost: int = 4  # extra walk cost for an unrelated mood, 0 = off
    ai_batch_size: int = 20
