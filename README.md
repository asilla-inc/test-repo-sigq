# test-repo-sigq

Dummy sandbox repo used to test-drive a release-branch + auto-rebase strategy.

**All content in this repo is fake/dummy data** created solely to exercise git
merge/rebase mechanics. No real SigQ code or data lives here.

## Branching model under test

```
main:      v4.6.3 ──► v5.0 ──► v5.0.1 ──► v5.1
              │          ▲        │          ▲
              ▼          │        │          │
           dev-5.0 ──────┘        │          │
                                  ▼          │
                             dev-5.0.1 ───────┘
                                  │
              (auto-rebase)       ▼
           dev-5.1 ──► dev-5.1 ──► dev-5.1 ──► (merge → v5.1)
```

- `main` is the trunk. Every release (major/minor/patch) is tagged directly on it.
- `dev-X.Y` branches are cut from `main` at a tag, used to stage work for that
  release, then merged back into `main` to produce the next tag.
- `dev-5.1` is long-running (spans across the `v5.0.1` hotfix) and is
  **auto-rebased** onto `main` every time `main` moves, instead of merging
  `main` back into it.

See `DEMONSTRATION.md` for the full, reproducible, command-by-command
walkthrough of this exact flow (green branches → orange branch auto-rebase →
final integration), and `STRATEGY_NOTES.md` for the strengths/gaps analysis
discovered while exercising it.
