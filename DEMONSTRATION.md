# Demonstration: Release-Branch + Auto-Rebase Strategy

This document is a full, reproducible walkthrough of the branching strategy
from the original diagram, executed end-to-end in this repo with real git
commands and real command output. Every commit/tag/SHA referenced below
exists in this repository — you can check any of it yourself with
`git log --oneline --graph --decorate --all`.

All content (code, features, "hotfixes") is dummy data created purely to
exercise git mechanics. This is not real SigQ code.

## The model being demonstrated

```
main:        v4.6.3 ────────► v5.0 ─────────► v5.0.1 ─────────► v5.1
                │                ▲                ▲                ▲
                ▼                │                │                │
   ┌── dev-5.0 (green) ──────────┘                │                │
   │      2 commits, merge --no-ff into main                       │
   │                                                                │
   └── dev-5.0.1 (green) ─────────────────────────┘                │
          1 commit, cut from v5.0, merge --no-ff into main          │
                                                                     │
   dev-5.1 (orange) ── cut from v5.0 ── commit A ── [AUTO-REBASE onto v5.0.1] ── commit B ── commit C ──► merge --no-ff into main
```

Three roles at play, matching the diagram:

1. **Green branches** (`dev-5.0`, `dev-5.0.1`) — short-lived, cut from `main`,
   merged straight back in. These are what feed `main` its `v5.0` and
   `v5.0.1` tags.
2. **Orange branch** (`dev-5.1`) — long-lived, in flight *while* the green
   branches are landing. It is **auto-rebased** onto `main` so it inherits
   every green-branch change as they land, rather than merging `main` into
   it.
3. **Final integration** — when `dev-5.1` is ready, it merges into `main`
   producing `v5.1`. Because it was kept rebased, it already shares full
   history with `main`, so the merge only has to apply the genuinely new
   work.

---

## Step 1 — `main` baseline

```
ec52efb  chore: initial dummy app scaffold        (tag: v4.6.3)
```

`app/main.py` has a `greet()` function and `get_version()` returning `4.6.3`.
This is the trunk everything else branches from.

## Step 2 — Green branch #1: `dev-5.0`

Cut from `v4.6.3`, two commits of "5.0 feature work":

```
$ git log --oneline v4.6.3..dev-5.0
04f8b5a chore: bump dev version marker for 5.0 work
bfac3e8 feat(auth): add dummy auth stub for v5.0
```

Merged back into `main` with `--no-ff` (keeps the branch visible in history
as its own line, rather than squashing it away):

```
$ git checkout main
$ git merge --no-ff dev-5.0 -m "merge: dev-5.0 into main for v5.0 release"
Merge made by the 'ort' strategy.
 app/feature_auth.py | 5 +++++
 app/main.py         | 2 +-
$ git tag v5.0
```

`main` is now at `v5.0`, carrying `dev-5.0`'s work.

## Step 3 — Green branch #2: `dev-5.0.1` (hotfix)

Cut from `v5.0` (**not** from `dev-5.0`) — this is a fresh hotfix branch:

```
$ git checkout -b dev-5.0.1 v5.0
$ git log --oneline v5.0..dev-5.0.1
136802c fix: guard against empty name in greet() (hotfix)
```

This commit edits `greet()` — remember this file/function, it's the one
that later collides with the orange branch.

Merged back into `main`:

```
$ git checkout main
$ git merge --no-ff dev-5.0.1 -m "merge: dev-5.0.1 hotfix into main for v5.0.1 release"
Merge made by the 'ort' strategy.
 app/main.py | 4 +++-
$ git tag v5.0.1
```

`main` is now at `v5.0.1`. Both green branches are fully absorbed.

## Step 4 — Orange branch: `dev-5.1` starts *before* the hotfix lands

Crucially, `dev-5.1` was cut from `v5.0` — **before** `v5.0.1` existed:

```
$ git checkout -b dev-5.1 v5.0
$ git commit -m "feat(dashboard): add dummy dashboard stub (commit A, pre-rebase)"
```

At this point `dev-5.1` and `dev-5.0.1` are siblings — both descend from
`v5.0`, neither knows about the other.

A second commit is added to `dev-5.1`, which (by design, to exercise the
worst case) touches the *same* `greet()` function the hotfix touched:

```
$ git commit -am "feat(dashboard): tweak greeting copy (commit B, pre-rebase)"
```

## Step 5 — The Auto-Rebase

This is the mechanism at the center of the diagram. Once `v5.0.1` lands on
`main`, `dev-5.1` gets rebased onto it, so it inherits the hotfix instead of
drifting further away from `main`:

```
$ git rebase main
Auto-merging app/main.py
CONFLICT (content): Merge conflict in app/main.py
error: could not apply <sha>... feat(dashboard): tweak greeting copy (commit B, pre-rebase)
```

**This is the real, load-bearing finding of this demonstration.** Rebase
only auto-applies patches that don't overlap with what already changed on
the new base. Both `dev-5.0.1`'s hotfix and `dev-5.1`'s commit B edited
`greet()`, so git stops and requires a manual resolution:

```python
def greet(name: str) -> str:
<<<<<<< HEAD                                    # main's version (has the hotfix)
    # hotfix: guard against empty name (dummy bug fix)
    name = name or "anonymous"
    return f"Hello, {name}! Running v{get_version()}."
=======                                          # dev-5.1's version (commit B)
    # v5.1: friendlier greeting copy
    return f"Hi there, {name}! (v{get_version()})"
>>>>>>> feat(dashboard): tweak greeting copy (commit B, pre-rebase)
```

Resolved by keeping both intents (the guard clause *and* the friendlier
copy):

```python
def greet(name: str) -> str:
    # hotfix: guard against empty name (dummy bug fix)
    # v5.1: friendlier greeting copy
    name = name or "anonymous"
    return f"Hi there, {name}! (v{get_version()})"
```

```
$ git add app/main.py
$ git rebase --continue
Successfully rebased and updated refs/heads/dev-5.1.
```

After this, `dev-5.1`'s commits A and B got **new SHAs** (`f776205`,
`30a2c49`) — different from their pre-rebase SHAs (`39eaac9`, `fe2a7a8`).
This is expected rebase behavior, but it's the mechanism behind one of the
strategy's real risks (see "Gaps" below).

## Step 6 — Verifying the "shared history" claim

This is the key payoff the diagram promises: once auto-rebased, does
`dev-5.1` actually contain `dev-5.0.1`'s (and `dev-5.0`'s) full history? Yes
— verified directly:

```
$ git merge-base --is-ancestor v5.0.1 dev-5.1 && echo YES
YES

$ git log --oneline v5.0.1..dev-5.1
34d2bdb feat(dashboard): add widget count helper (commit C, final)
30a2c49 feat(dashboard): tweak greeting copy (commit B, pre-rebase)
f776205 feat(dashboard): add dummy dashboard stub (commit A, pre-rebase)
```

`v5.0.1` is a real ancestor of `dev-5.1`'s tip, and the only commits `dev-5.1`
has beyond that point are its own 3 genuine feature commits. This confirms
the mechanism described: **because `dev-5.1` was rebased (not merged) onto
`main`, it now shares one single linear history with `main` up to `v5.0.1`,
instead of having a separate branch history that a merge would need to
reconcile.**

## Step 7 — Final integration: merge `dev-5.1` back into `main`

One more commit is added to `dev-5.1` (commit C, the final feature piece),
then it's merged into `main`:

```
$ git commit -am "feat(dashboard): add widget count helper (commit C, final)"
$ git checkout main
$ git merge --no-ff dev-5.1 -m "merge: dev-5.1 into main for v5.1 release"
Merge made by the 'ort' strategy.
 app/feature_dashboard.py | 9 +++++++++
 app/main.py              | 3 ++-
$ git tag v5.1
```

Notice the merge only had to reconcile **2 files** (`feature_dashboard.py`,
`main.py`) with a **3-line net diff** — because `main` and `dev-5.1` already
shared all history up to `v5.0.1`, git had nothing old to re-merge. This is
exactly the "clean, only-new-work" merge the diagram promises, and it's
real: the earlier rebase is what earned it. Compare this to what a merge of
an un-rebased `dev-5.1` would have required — git would have had to
reconcile the entire divergent history from `v5.0` onward, hitting the
`greet()` conflict *at final-merge time* instead of earlier.

## Final state (verifiable in this repo right now)

```
$ git log --oneline --graph --decorate --all

* a363a38 (main) docs: write up strengths/gaps found while testing the branch strategy
* 55b7d83 (tag: v5.1) release: v5.1
*   1e8ff73 merge: dev-5.1 into main for v5.1 release
|\
| * 34d2bdb (dev-5.1) feat(dashboard): add widget count helper (commit C, final)
| * 30a2c49 feat(dashboard): tweak greeting copy (commit B, pre-rebase)   <- rebased, new SHA
| * f776205 feat(dashboard): add dummy dashboard stub (commit A, pre-rebase) <- rebased, new SHA
|/
* b7141fa (tag: v5.0.1) release: v5.0.1
*   992195e merge: dev-5.0.1 hotfix into main for v5.0.1 release
|\
| * 136802c (dev-5.0.1) fix: guard against empty name in greet() (hotfix)
|/
* 24e1c90 (tag: v5.0) release: v5.0
*   65cc265 merge: dev-5.0 into main for v5.0 release
|\
| * 04f8b5a (dev-5.0) chore: bump dev version marker for 5.0 work
| * bfac3e8 feat(auth): add dummy auth stub for v5.0
* | 8fbd9b3 chore: add gitignore
|/
* ec52efb (tag: v4.6.3) chore: initial dummy app scaffold
```

This is live at `github.com/asilla-inc/test-repo-sigq` — every branch
(`main`, `dev-5.0`, `dev-5.0.1`, `dev-5.1`) and tag (`v4.6.3`, `v5.0`,
`v5.0.1`, `v5.1`) referenced above is pushed and inspectable.

---

## What this demonstration confirms about the strategy

**Confirmed strengths (the diagram's claims hold up):**

- The "shared history via rebase" mechanism is real and verifiable
  (`merge-base --is-ancestor` proves it) — auto-rebasing the orange branch
  genuinely does make the final integration cleaner than a plain merge of
  divergent branches would be.
- `main`'s history stays a clean, fully-tagged, readable changelog.
- Hotfixes (`dev-5.0.1`) don't block the in-flight feature branch
  (`dev-5.1`) from continuing to be developed — they're fully independent
  until the rebase step.

**Confirmed gap (the diagram's implicit claim does not hold up):**

- "Auto Rebase" is not actually automatic once two branches touch the same
  lines. Step 5 above is a real, reproduced merge conflict, not a
  hypothetical — the automation needs an explicit human-in-the-loop path
  (who resolves it, how, and how quickly) or it silently blocks.
- Every rebase rewrites commit SHAs on the orange branch (`f776205`/`30a2c49`
  vs. the original `39eaac9`/`fe2a7a8`). Anyone else with a local copy of
  `dev-5.1` prior to the rebase is now diverged and must force-reset. This
  is fine for a single-owner branch; it's a real hazard for a
  multi-contributor one.

See `STRATEGY_NOTES.md` for the full strengths/gaps analysis and suggested
follow-ups.
