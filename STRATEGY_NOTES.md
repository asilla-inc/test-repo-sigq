# Branch Strategy Test Notes

Reproduced in this repo (see `git log --oneline --graph --decorate --all`):

```
* release: v5.1
*   merge: dev-5.1 into main for v5.1 release
|\
| * feat(dashboard): add widget count helper (commit C, final)
| * feat(dashboard): tweak greeting copy (commit B, pre-rebase)   <-- auto-rebased
| * feat(dashboard): add dummy dashboard stub (commit A, pre-rebase)
|/
* release: v5.0.1
*   merge: dev-5.0.1 hotfix into main for v5.0.1 release
|\
| * fix: guard against empty name in greet() (hotfix)
|/
* release: v5.0
*   merge: dev-5.0 into main for v5.0 release
|\
| * chore: bump dev version marker for 5.0 work
| * feat(auth): add dummy auth stub for v5.0
* | chore: add gitignore
|/
* chore: initial dummy app scaffold  (v4.6.3)
```

Sequence exercised:

1. `main` @ `v4.6.3` → `dev-5.0` cut, 2 commits, merged back → `main` tagged `v5.0`.
2. From `v5.0`, two branches cut in parallel: `dev-5.0.1` (hotfix) and `dev-5.1` (next feature release).
3. `dev-5.0.1` merged back first → `main` tagged `v5.0.1`.
4. `dev-5.1` (already had 2 commits) was **auto-rebased** onto `main` (now at `v5.0.1`) to pick up the hotfix.
5. A third commit was added to `dev-5.1`, then merged back → `main` tagged `v5.1`.

## What actually happened when the "Auto Rebase" step ran

Step 4 is the crux of this strategy, so it's worth being precise about what happened:

- `dev-5.1`'s second commit and the `v5.0.1` hotfix both touched `greet()` in
  `app/main.py`. The rebase **stopped with a real merge conflict** —
  `git rebase` is not magic; "auto" rebase only auto-applies non-overlapping
  patches. The moment two branches touch the same lines, a human (or a very
  well-informed bot) has to resolve it.
- After rebasing, `dev-5.1`'s commits got **new SHAs** (`f776205`, `30a2c49`
  instead of the originals `39eaac9`, `fe2a7a8`). Anyone who had already
  fetched/pulled `dev-5.1` before the auto-rebase now has a diverged, unrelated
  copy and will hit "diverged branches" the next time they pull, unless they
  know to `reset --hard` to the new tip.

## Strengths of this strategy

- **Clean, linear, fully-tagged trunk.** `main`'s history reads like a
  changelog — every tag is a real shippable state, easy to `git log --oneline
  --decorate` or `git describe` from any commit to know what's released.
- **Hotfixes don't block feature work.** `dev-5.0.1` and `dev-5.1` could be
  cut from the same point and progress independently; the hotfix shipped
  (`v5.0.1`) without waiting on the `v5.1` feature branch.
- **Auto-rebase keeps long-lived branches current** instead of letting them
  drift for weeks and accumulate a huge, unreviewable merge commit at the end.
  Small, frequent rebases surface conflicts (like the `greet()` one above)
  early, while the relevant author still remembers the change, rather than
  at final merge time when context is gone.
- **`--no-ff` merges preserve the branch's identity** in history, so you can
  always see "which release-branch produced this tag" via `git log --graph`.
- Because each `dev-X.Y` branch is disposable and scoped to one release, blast
  radius of a bad rebase/force-push is limited to that branch's active
  contributors, not the whole team on `main`.

## Gaps / risks to plan for

- **Rebase = rewritten history = force-push required.** Auto-rebasing a
  branch that any other collaborator has already pulled is unsafe unless
  everyone force-resets after every rebase. This strategy really only works
  safely if `dev-X.Y` branches have a single owner, or the automation also
  notifies/force-updates every checkout. Worth deciding explicitly: is
  "auto rebase" allowed on branches with >1 contributor?
- **Conflicts aren't actually automatable.** The diagram's red "Auto Rebase"
  arrows imply a mechanical/automatic step, but as soon as two branches edit
  the same lines (very likely once a hotfix and a feature branch both live
  long enough), a human has to step in. The automation needs a clear
  fallback: does it open a PR for manual conflict resolution, ping the
  branch owner, or just fail silently in CI? This needs to be specified, not
  left implicit.
- **No policy shown for *when* auto-rebase triggers.** Rebase on every
  `main` commit? Only on tags? Only on hotfix tags? Rebasing too often on an
  active branch causes constant SHA churn and repeated conflict resolution
  for the same lines across each rebase; too rarely and you lose the "catch
  conflicts early" benefit.
- **CI/tag semantics on rebased branches.** If CI or deployment tooling keys
  off commit SHA (e.g., "deploy the commit that passed CI"), a rebase
  invalidates prior green CI runs on those commits — they need to be
  re-tested, since rebase doesn't just move a pointer, it recreates commits.
- **Version-bump/VERSION-file commits on `main` are a recurring merge-conflict
  source.** In this test, `main` had its own commits (`chore: add
  gitignore`, `release: vX.Y` bumps) interleaved with each merge. Every
  `dev-X.Y` branch, when later merged or rebased, has to reconcile those
  `main`-only commits. A dedicated bump/release-commit convention (e.g. bump
  only right after tagging, never introduce unrelated `main`-only commits)
  reduces this friction — but nothing in the diagram enforces that
  discipline.
- **No branch-cleanup story.** The diagram doesn't show when `dev-5.0`,
  `dev-5.0.1` get deleted after merge. Without an explicit TTL/cleanup step,
  stale dev branches accumulate indefinitely.
- **Scaling to concurrent patch releases.** The diagram only shows one
  hotfix (`v5.0.1`) landing while one feature branch (`dev-5.1`) is in
  flight. If two or three hotfixes land in sequence while `dev-5.1` is still
  open, `dev-5.1` needs multiple auto-rebases, multiplying the conflict
  surface shown above. Worth stress-testing with 2+ concurrent hotfixes.

## Suggested follow-ups

1. Define ownership rules for `dev-X.Y` branches (single-owner recommended,
   given rebase is destructive to collaborators).
2. Specify the automation's conflict-handling path (auto-PR + notify vs.
   fail-and-alert) rather than assuming rebase "just works."
3. Decide the rebase trigger policy (on every `main` push vs. only on
   tag/hotfix pushes) and pick whichever minimizes churn while still
   catching conflicts early.
4. Add a branch-deletion/TTL step to the workflow once a `dev-X.Y` branch is
   merged and tagged.
5. Stress-test with 2+ concurrent hotfixes against one long-lived `dev-X.Y`
   branch to see how the conflict surface grows.
