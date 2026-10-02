#!/usr/bin/env bash
# Turns the auto-rebase.sh TSV report into GitHub feedback:
#   - job summary ($GITHUB_STEP_SUMMARY)
#   - REBASED            -> one comment per run on the open "Auto Rebase log" issue,
#                           with the commands developers need after the force-push
#   - CONFLICT / PUSH_FAILED -> one open issue per branch+parent (reused, not duplicated)
# Env: REPORT (required), GH_TOKEN, GITHUB_REPOSITORY, GITHUB_SERVER_URL, GITHUB_RUN_ID
set -euo pipefail

REPORT="${REPORT:?REPORT not set}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
LABEL="auto-rebase"
LOG_TITLE="Auto Rebase log"
RUN_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-}"

[ -s "$REPORT" ] || { echo "No dev/<version> branches to process." >> "$SUMMARY"; exit 0; }

{
  echo "## Auto Rebase"
  echo
  echo "| Status | Branch | Parent | Detail |"
  echo "|---|---|---|---|"
  while IFS=$'\t' read -r st b p x y; do
    case "$st" in
      REBASED|PUSH_FAILED) echo "| $st | \`$b\` | \`$p\` | \`${x:0:7}\` → \`${y:0:7}\` |" ;;
      CONFLICT)            echo "| $st | \`$b\` | \`$p\` | $y |" ;;
      UPTODATE)            echo "| $st | \`$b\` | \`$p\` | \`${x:0:7}\` |" ;;
      SKIP_MERGED)         echo "| $st | \`$b\` | — | already in main |" ;;
    esac
  done < "$REPORT"
} >> "$SUMMARY"

gh label create "$LABEL" --color D93F0B --description "Opened by the Auto Rebase workflow" \
  --force >/dev/null 2>&1 || true

# find_issue <title> -> number of the open issue with exactly that title, or empty
find_issue() {
  gh issue list --state open --label "$LABEL" --limit 100 --json number,title \
    --jq ".[] | select(.title == \"$1\") | .number" | head -n1
}
# upsert_issue <title> <body>
upsert_issue() {
  local n; n="$(find_issue "$1")"
  if [ -n "$n" ]; then gh issue comment "$n" --body "$2" >/dev/null
  else gh issue create --title "$1" --label "$LABEL" --body "$2" >/dev/null; fi
}

rebased_body=""
while IFS=$'\t' read -r st b p x y; do
  case "$st" in
    REBASED)
      rebased_body+="### \`$b\` rebased onto \`$p\` (\`${x:0:7}\` → \`${y:0:7}\`)

History of \`$b\` was rewritten. If you have it checked out (no local-only commits):
\`\`\`bash
git fetch origin && git checkout $b && git reset --hard origin/$b
\`\`\`
If you have a work branch cut from the old \`$b\`:
\`\`\`bash
git fetch origin && git rebase --onto origin/$b $x <your-branch>
\`\`\`
"
      ;;
    CONFLICT)
      upsert_issue "Auto Rebase conflict: $b onto $p" "Auto Rebase could not rebase \`$b\` (\`${x:0:7}\`) onto \`$p\`. Nothing was pushed.

Conflicting files: \`$y\`

Resolve manually, then push (a branch owner with force-push rights):
\`\`\`bash
git fetch origin
git checkout $b && git reset --hard origin/$b
git rebase origin/$p        # resolve, git add, git rebase --continue
git push --force-with-lease origin $b
\`\`\`
Close this issue when done. Run: $RUN_URL"
      ;;
    PUSH_FAILED)
      upsert_issue "Auto Rebase push rejected: $b" "Rebase of \`$b\` onto \`$p\` succeeded locally but the push was rejected (branch moved during the run, or a ruleset blocks force-push for the workflow token). Nothing changed on \`$b\`. The next push to \`$p\` retries automatically. Run: $RUN_URL"
      ;;
  esac
done < "$REPORT"

if [ -n "$rebased_body" ]; then
  upsert_issue "$LOG_TITLE" "Run: $RUN_URL

$rebased_body"
fi
