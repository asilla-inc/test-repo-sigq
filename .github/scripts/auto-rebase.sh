#!/usr/bin/env bash
# Auto Rebase — Git Policy v1.2 §2f (the red arrows in Figure 1 / Figure 2).
#
# Keeps every OPEN dev/<version> branch rebased onto its parent:
#   parent = nearest lower-version open dev/<version>, else main.
# "Open" = tip not yet contained in main (merged dev branches are skipped).
# Branches are processed in version order, so a cascade (main -> dev/5.0 -> dev/5.1
# -> dev/5.2) completes in one run. On conflict the rebase is aborted, nothing is
# pushed for that branch, and the run exits 2.
#
# Env:
#   REMOTE  (origin)     remote to fetch from / push to
#   TRUNK   (main)       trunk branch
#   DRY_RUN (0)          1 = compute + report, never push
#   REPORT  (/dev/stdout) TSV report, one line per branch:
#     REBASED     <branch> <parent> <old-sha> <new-sha>
#     UPTODATE    <branch> <parent> <sha>
#     CONFLICT    <branch> <parent> <sha>     <space-separated files>
#     PUSH_FAILED <branch> <parent> <old-sha> <new-sha>
#     SKIP_MERGED <branch> <sha>
# Exit: 0 ok, 2 at least one CONFLICT / PUSH_FAILED.
set -euo pipefail

REMOTE="${REMOTE:-origin}"
TRUNK="${TRUNK:-main}"
DRY_RUN="${DRY_RUN:-0}"
REPORT="${REPORT:-/dev/stdout}"

: > "$REPORT" 2>/dev/null || true
report() { local IFS=$'\t'; echo "$*" >> "$REPORT"; }
log() { echo "[auto-rebase] $*" >&2; }

git fetch --quiet --prune "$REMOTE" "+refs/heads/*:refs/remotes/$REMOTE/*"
trunk_sha="$(git rev-parse "refs/remotes/$REMOTE/$TRUNK")"

# dev/<version> only (digits and dots); custom/*, feat/*, dev/foo are out of scope.
mapfile -t all_dev < <(
  git for-each-ref --format='%(refname:strip=3)' "refs/remotes/$REMOTE/dev/" \
    | grep -E '^dev/[0-9]+(\.[0-9]+)*$' \
    | sed 's#^dev/##' | sort -V | sed 's#^#dev/#'
)

declare -A old_tip new_tip
open=()
for b in "${all_dev[@]}"; do
  sha="$(git rev-parse "refs/remotes/$REMOTE/$b")"
  if git merge-base --is-ancestor "$sha" "$trunk_sha"; then
    report SKIP_MERGED "$b" "$sha"
    continue
  fi
  old_tip[$b]="$sha"; new_tip[$b]="$sha"; open+=("$b")
done

rc=0
parent="$TRUNK"
for b in "${open[@]}"; do
  if [ "$parent" = "$TRUNK" ]; then
    p_old="$trunk_sha"; p_new="$trunk_sha"
  else
    p_old="${old_tip[$parent]}"; p_new="${new_tip[$parent]}"
  fi
  c_old="${old_tip[$b]}"

  if git merge-base --is-ancestor "$p_new" "$c_old"; then
    report UPTODATE "$b" "$parent" "$c_old"
    parent="$b"; continue
  fi

  git checkout --quiet --detach "$c_old"
  # Parent was rewritten earlier in this run: replay only the child's own commits,
  # otherwise the parent's pre-rebase commits would be replayed a second time.
  if [ "$p_old" != "$p_new" ] && git merge-base --is-ancestor "$p_old" "$c_old"; then
    cmd=(git rebase --quiet --onto "$p_new" "$p_old")
  else
    cmd=(git rebase --quiet "$p_new")
  fi

  if "${cmd[@]}" >/dev/null 2>&1; then
    c_new="$(git rev-parse HEAD)"
    if [ "$DRY_RUN" = "1" ]; then
      report REBASED "$b" "$parent" "$c_old" "$c_new"; new_tip[$b]="$c_new"
    elif git push --quiet --force-with-lease="refs/heads/$b:$c_old" \
          "$REMOTE" "$c_new:refs/heads/$b" 2>/dev/null; then
      log "$b rebased onto $parent: ${c_old:0:7} -> ${c_new:0:7}"
      report REBASED "$b" "$parent" "$c_old" "$c_new"; new_tip[$b]="$c_new"
    else
      log "$b push rejected (branch moved or protected)"
      report PUSH_FAILED "$b" "$parent" "$c_old" "$c_new"; rc=2
    fi
  else
    files="$(git diff --name-only --diff-filter=U | tr '\n' ' ' | sed 's/ $//')"
    git rebase --abort >/dev/null 2>&1 || true
    log "$b CONFLICT onto $parent: $files"
    report CONFLICT "$b" "$parent" "$c_old" "$files"; rc=2
  fi
  parent="$b"
done

exit "$rc"
