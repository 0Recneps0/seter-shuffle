# Investigation: second bridge failure, 2026-10-28 (23:46 PT run)

Status: INVESTIGATION, NOT A FIX. Nothing in this note has been proven
on a Mac. No bridge script has ever executed here (no osascript, no
Music app on this Linux VM). Do not touch the real playlist again
until the gate at the end of this note is met.

## 1. Evidence, re-verified from the uploads (not taken on faith)

- 2026-10-28 23:46 PT, exp-2026-10-28.5, `./run.sh shuffle
  "My New Sandwich Recipe"`, 806 songs, on the real playlist again.
- Probe (same run log): PROBE_PICKED / PROBE_LIST / PROBE_INDEX_ORDER
  all `5749EA8757818761 5CC874E66EF2DDAB B96A7381C73F46AC`,
  PROBE_POS_FIRST `5749EA8757818761`, PROBE_POS_LAST
  `B96A7381C73F46AC`, PROBE_VERDICT `forward`, PROBE_CLEANUP_OK.
  All three probe channels agreed on a fresh 3-song playlist.
- Apply failed: "verification failed AND restore failed", 23:46:48 to
  23:48:35 (~107 s). run.sh's undo restore failed: "verification
  failed AND pre-undo restore failed", to 23:50:14 (~99 s).
- Backup files, compared programmatically (all 806 IDs, 806 unique):
  - Backup taken at the START of the .5 run == the ORIGINAL backup
    from the .4 run, exactly, same order. The .prev copy also ==
    the original. So the .5 run started from the original list-read
    order, which also proves the .4 run ended back at the original
    list-read order.
  - Pre-undo snapshot taken during the .5 undo == the EXACT REVERSE
    of the original backup, 806/806, same set. Identical pattern to
    the .4 run, second time in a row.
- No songs left the library in either run. Only playlist order is at
  stake, and the original order is preserved in backup files (and in
  this VM's uploads).

## 2. What the .5 trace proves, step by step

Mode was `forward` throughout (log: "probe mode for My New Sandwich
Recipe: forward"). In forward mode the .5 code is unambiguous, read
directly from `bridge/apply-order.applescript` and
`bridge/undo.applescript`:

- apply build: duplicate the shuffle order S as-is; expect list == S.
- apply restore: duplicate the backup B as-is; expect list == B.
- undo build: duplicate the backup B as-is; expect list == B.
- undo pre-undo restore: duplicate the pre-undo snapshot (reverse(B))
  as-is; expect list == reverse(B).

Every one of those builds failed its own verify. That rules out a
large class of explanations at once:

- It is NOT a wrong mode argument: run.sh passes the probed mode in
  the correct argument position, and the scripts parse it before
  touching anything. A wrong mode would make some builds verify and
  others fail; here none verified.
- It is NOT a script-side reversal in forward mode: `buildForApply`
  returns the order unchanged, `expectedForApply` returns it
  unchanged, `buildForRestore`/`expectedForRestore` return the
  snapshot unchanged. There is no `reverseList` on the forward path.
- It is NOT a missing or unduplicable song: a missing song takes the
  build-failed path and names the song; the errors here are
  verification failures, and a single missing song cannot produce an
  exact reverse snapshot anyway.
- It is NOT an AppleScript timeout: the .5 builds run inside
  `with timeout of 3600 seconds` blocks, and the runs took ~107 s and
  ~99 s, far under it. The .4 runs took ~120 s and ~96 s with the
  same failure, also not a timeout signature.
- It is NOT a dump-vs-backup base mismatch: the dump and the backup
  both read `persistent ID of every track of playlist`, the shuffle
  order is a permutation of the dump set, and the backup is the
  playlist's own list-read snapshot. A base mismatch would change
  what "shuffled" means, not make a rebuild of B fail to verify
  against B.
- It is NOT the order file, the JSON/text cross-check, or the
  duplicate allowance: validation passed (806 IDs, mode shuffle),
  and the same failure hit the restore builds, which use no order
  file at all.

The remaining fact is stark: for the REAL playlist, a delete plus
duplicate-in-order rebuild does not land the list-read order on the
built order, in either direction tried (S, B, reverse(B) all failed),
while for a FRESH 3-song probe playlist the same operations land
exactly forward. The difference is therefore a property of the real
playlist object (or of its context in Music) that the fresh probe
playlist does not share. The probe measured the wrong playlist.

## 3. Why the probe did not predict the real playlist

The probe playlist differs from the real playlist in every dimension
that could control insertion/read order:

| Dimension | Probe playlist | Real playlist | How it could flip the result |
|---|---|---|---|
| Age / origin | Created seconds earlier by the probe itself, never synced, never edited by hand | Old, hand-built daily playlist, synced via iCloud Music Library, edited many times | A synced/old playlist carries UI sort, sync identity, and edit history a fresh playlist does not |
| UI sort | None (fresh playlist, manual order) | UNKNOWN, must be checked: a column sort (Date Added, Title, Artist, etc.) may be active | A sorted playlist inserts new tracks at their sorted position and reads tracks in sorted order, not manual order (see section 4) |
| Size | 3 tracks | 806 tracks | A size-dependent code path or sync batching cannot be ruled out from the probe alone, but size alone has no known mechanism that produces an EXACT reverse |
| Track kinds | First 3 library songs (all three IDs are also in the real playlist, so kind is not the whole story) | 806 mixed tracks: local, streaming, cloud/matched, purchased, uploaded | One odd track cannot reverse 806 entries; a kind difference would break a few builds, not reverse all of them |
| Selection / playback context | New playlist, never opened, nothing selected, not playing | The user's daily playlist, possibly open in Music, possibly with a selected track or the playing track | Insertion position in some Music versions follows the selected track; unproven, but a fresh playlist never has this context |
| Content | 3 arbitrary library songs | The exact 806-song set, in an order built up over time | The set itself is not the mechanism; the order it was built in may be (see the sort theory) |

The probe's three channels (list, index, positional) all travel
through the same Music scripting bridge, so they are not three
independent instruments. They agreed on the fresh playlist, which
proves the bridge behaves forward THERE. They say nothing about a
playlist with a different sort, sync state, or selection context.

## 4. Leading theory: a UI column sort on the real playlist

This is the only candidate found that predicts an EXACT reverse,
twice, for every rebuild, while leaving a fresh probe forward:

- Suppose the real playlist is sorted in Music's UI by a column
  whose value is set when a track is added TO THE PLAYLIST, in
  descending order. The prime suspect is Date Added (to the playlist)
  descending.
- At the start of a run, the list-read order B is that sorted order.
- The script deletes all songs and duplicates in build order. Each
  new entry gets a fresh add-time, increasing with the build order.
  Sorted descending, the resulting list-read order is the EXACT
  REVERSE of the build order: build S lands reverse(S), build B
  lands reverse(B). Every verify fails, exactly as observed.
- Undo snapshots reverse(B) (the state after apply's restore), then
  builds B (lands reverse(B), fails), then restores reverse(B)
  (lands B, fails against reverse(B)). The .4 run ending back at
  list-read order B is exactly what this trace predicts.

Weak link, stated plainly: this theory requires the sort key to be a
playlist-add time that resets on re-adding. If the Date Added column
in a playlist view instead shows the LIBRARY add date (which does
not change on re-adding), a sorted rebuild would land back on B and
the restore would verify, which contradicts the evidence. So the
theory stands or falls on two checks the user can do in one minute
(see section 6, steps 2 and 5c): is a column sort actually active on
the real playlist, and does a throwaway sorted by Date Added
descending reverse a known build order?

Other sort variants are ruled out by the exact-reverse constraint:
a Title/Artist/Album sort would land rebuilds in alphabetical order,
not in exact reverse(B), for 806 songs. A sort that produced a fixed
alphabetical order cannot explain the reverse snapshot. Only a
time-descending sort (or an equivalent insertion-order-inverting
sort) fits.

## 5. Other candidates, ruled in or out against the evidence

- iCloud Music Library sync reordering a large synced playlist
  during a 100+ second bulk rewrite: OUT as the primary mechanism.
  Sync is asynchronous and would scramble or partially apply, not
  produce an exact reverse twice in a row. It remains a possible
  contributor (a sorted playlist's sort may itself sync), but it
  cannot be the whole explanation.
- Streaming/cloud/matched track kinds duplicating differently: OUT
  as the primary mechanism. The probe's 3 tracks are themselves
  real-playlist tracks, and a kind difference would affect a few
  entries, not reverse all 806. A single unduplicable track is
  separately ruled out (section 2).
- Size alone (806 vs 3): UNRESOLVED, but no known mechanism. It is
  tested directly by step 5d below; if large throwaways pass and
  only the real playlist fails, size is out.
- Selection/playback context (a selected track, or the playing
  track, steering insertion position): UNRESOLVED, low prior. No
  documented AppleScript behaviour makes `duplicate ... to playlist`
  insertion-position depend on selection, and the effect would need
  to be exactly "insert before everything" on both runs. Tested
  cheaply by closing the playlist view / pausing playback before a
  throwaway test, and by comparing a throwaway built while the real
  playlist is selected versus not.
- A playlist-level property beyond sort (sync identity, origin on
  iPhone, folder membership): UNRESOLVED. Tested by step 5b: if a
  duplicate copy of the real playlist (made in Music) also reverses,
  the property travels with the copy; if the copy passes, the
  property is specific to the original playlist object (its sort or
  its UI state).
- Read-reversed on the real playlist only (the .5 code's second
  model): still logically possible, but it now has the same burden
  as write-reversed: it must explain why the READ reverses on the
  real playlist and not on the fresh probe. A UI sort explains both
  read and write through one property (sorted order governs both);
  a read-only reversal needs a second, separate mechanism. The
  diagnostic in step 6.1 (list vs positional vs displayed first
  song) is what separates read-reversed from write-reversed.

## 6. Next investigation: read-only first, throwaway-only writes

Do these in order. Nothing here modifies the real playlist. Stop at
the first step that proves a mechanism, and do not proceed to a
real-playlist build on an unproven theory.

### Step 1: read-only diagnostic on the real playlist (no changes)

Run the helper in this tree (it only reads):

```
osascript bridge/diagnose-playlist.applescript "My New Sandwich Recipe"
```

It prints COUNT_SONGS, COUNT_TRACKS, LIST_FIRST, LIST_LAST,
POS_FIRST, POS_LAST, and INDEX_OF_LIST_FIRST. Compare against the
known backup ends: backup first `B49A108A0E5553DB`, backup last
`54BC5E32EB0D0F8E`.

- LIST_FIRST == `B49A...` and LIST_LAST == `54BC...`: the current
  list-read state is the original order. (Expected after the .4 run;
  the .5 run's final state is unmeasured, so this is the first thing
  to establish.)
- LIST_FIRST == `54BC...` and LIST_LAST == `B49A...`: the current
  list-read state is the exact reverse of the original.
- Neither: the current state is shuffled or partial; report the
  printed lines verbatim and stop.
- POS_FIRST/POS_LAST disagreeing with LIST_FIRST/LIST_LAST proves
  the positional read and the list read diverge on the real
  playlist, which is itself a finding: it separates a read problem
  from a write problem.

Also, in Music itself, note the first song actually DISPLAYED at the
top of "My New Sandwich Recipe". For a name-to-ID map of the
current playlist order, run the dump script directly (read-only)
and inspect the first entries:

```
osascript bridge/dump-library.applescript /tmp/real-playlist-now.json "My New Sandwich Recipe"
```

If the displayed first song's name matches the dump's first track
name, list-read == display. If the displayed first song matches the
dump's LAST track, the list-read is reversed against the display.
Report both names.

### Step 2: UI sort check on the real playlist (no changes)

Open "My New Sandwich Recipe" in Music. Look at the column headers:
is any column showing a sort arrow, and if so which column and which
direction (up/down)? Also check the playlist's View menu sort setting
if one is shown. Report the column and direction exactly, or report
"no sort arrow, manual order". This single observation confirms or
kills the leading theory's precondition. While there, note whether
playback is currently coming from this playlist and whether a track
in it is selected.

### Step 3: probe-keep eyeball (throwaway only)

```
./run.sh probe-keep
```

Look at the probe playlist on screen in Music and confirm its
on-screen order matches the printed verdict, then delete it by hand.
This is the check the .5 procedure already required and was skipped.
If the on-screen order disagrees with the verdict, the probe itself
is untrustworthy and no probed build may ever run.

### Step 4: throwaway happy path, then stop if it passes

A 10-song throwaway including one duplicate entry, on manual sort,
playback paused. `./run.sh shuffle` on the throwaway, then
`./run.sh undo`. If this passes, fresh throwaways are confirmed
forward and the difference is specific to the real playlist (go to
step 5). If it fails the same way, the probe is wrong in general and
the whole direction model must be rebuilt from scratch.

### Step 5: throwaway tests that isolate the property (throwaway only)

Run each on its own throwaway, playback paused, and record
pass/fail plus the resulting list order:

- 5a. Copy-slice: in Music, select ~20 songs FROM the real playlist
  and drag/copy them into a new throwaway playlist, then shuffle
  the throwaway. Pass rules out track-origin/kind; fail implicates
  the copied (synced) entries themselves.
- 5b. Duplicate-playlist: in Music, duplicate "My New Sandwich
  Recipe" (right-click, Duplicate) to make a throwaway copy with
  the same tracks and order, then shuffle the copy. If the copy
  reverses like the original, the reversing property travels with
  the copy (sort, sync identity, or track set). If the copy passes,
  the property is specific to the original playlist object (its UI
  sort or UI state, which a duplicate may not preserve).
- 5c. Sorted throwaway (the decisive sort test): create a 20-song
  throwaway, sort it in Music's UI by Date Added descending, then
  shuffle it. If it lands in exact reverse of the built order, the
  sort theory is proven. Repeat with Date Added ascending (should
  pass) and with Title sort (should land alphabetical, not
  reversed) as controls. If the Date Added descending throwaway
  passes, the sort theory is dead.
- 5d. Size ladder: throwaways of ~100 and ~400 songs (copies from
  the real playlist or the library), shuffled. If small passes and
  large fails at some threshold, size is a real factor; if all
  pass, size is out.
- 5e. Selection context: build a throwaway while the real playlist
  is open in Music with its first track selected, versus with
  Music's playlist view closed. Any difference implicates UI
  selection; no difference rules it out.

### Step 6: only then, a corrected build design

No corrected build is designed in this note, deliberately. The fix
depends on which step above proves the mechanism:

- If sort is proven: the probe must measure the TARGET playlist's
  sort, not a fresh playlist. Practical designs are (i) probe on a
  throwaway copy that has the target's sort applied, then build
  with the measured direction; or (ii) build into a fresh unsorted
  playlist and swap contents only after verification (which still
  needs a sort-aware final step). Setting a playlist's sort from
  AppleScript is not known to be exposed, so do not assume it.
- If the duplicate-copy test proves the property travels with the
  copy: the probe must be run on a copy of the target, never on an
  unrelated fresh playlist.
- If no throwaway reproduces the failure: the real playlist must
  NOT be touched. The next step is a read-only deep inspection of
  the real playlist object itself (its properties via a read-only
  script: class, smart flag, sort-relevant properties if any are
  exposed, track kinds and cloud statuses of its entries), not
  another build attempt.

## 7. Gate for touching the real playlist again

ALL of these must be true before any build, apply, undo, or restore
touches "My New Sandwich Recipe" again:

1. A throwaway test in step 5 reproduces the exact-reverse failure
   (not just any failure), AND the mechanism behind it is named.
2. A corrected build, designed for that mechanism, passes the full
   throwaway suite (happy path, duplicate entry, negatives) on
   throwaways that carry the same property (sorted, copied, or
   large, as applicable).
3. The current list-read state of the real playlist is measured by
   step 1, and the backup it will be restored from is verified
   against that measurement.
4. The user explicitly approves the real-playlist run after seeing
   1-3, knowing the two prior runs both failed in the same loop.

Until then: the real playlist is read-only, the .5 shuffle/undo
must not be run on it again, and the retired one-off fix script
(`~/Downloads/seter-fix-playlist.applescript`) must not be run on
any playlist.
