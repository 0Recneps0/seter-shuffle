"""SeTeR Shuffle, Python experimental core.

Standard library only. The core computes orderings from a library JSON
dump; it never touches the Music app itself. The AppleScript bridge in
../bridge/ is the only part that talks to Music, and it is the only
part that still needs a Mac to verify.
"""

__version__ = "experimental-python-2026-10-28"
