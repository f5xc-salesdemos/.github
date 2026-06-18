# `clone-all-repos.sh` — design & reference

One script to clone, and keep fresh, a local copy of every repo in the
`f5xc-salesdemos` ecosystem.

## Purpose

1. **Clone everything once.** A developer runs it in an empty folder and gets a local
   checkout of every repo listed in the [downstream-repos manifest][manifest], plus
   `docs-control` and `.github`.
2. **Stay fresh, idempotently.** Re-running pulls the latest commits everyone has pushed.
   Running it ten times in a row is safe.
3. **Sanity-check the developer's working tree and act correctly.** The guiding rule: a
   repo with any local work is **never modified** — it is only reported, so unfinished
   work is impossible to lose.

## Usage

```bash
# From the folder that should contain the clones (repos are created as siblings):
/path/to/.github/clone-all-repos.sh
```

Requires `curl`, `jq`, and `git` on `PATH`. The repo list is read at runtime from the
manifest, so onboarding a new repo there is picked up automatically on the next run.

## Per-repo outcomes

After `git fetch --prune`, every existing repo is classified into exactly one outcome.
A **universal preflight** runs first: if the working tree is dirty or has unpushed
commits (or HEAD is detached), the repo is `attention` and is left exactly as found —
**before** any fast-forward or branch switch is considered. Only genuinely clean repos
proceed to be fast-forwarded or healed.

| Status | Condition | Action |
|---|---|---|
| `cloned` | directory absent | `git clone` |
| `refreshed` | clean; on the default branch **or** a live feature branch | fast-forward to its upstream (or already current) |
| `healed` | clean; parked on a branch that was merged & deleted upstream | delete the stale branch, switch to the default branch, fast-forward |
| `attention` | uncommitted changes and/or unpushed commits, or detached HEAD | **fetch only — never modified** |
| `error` | `fetch`/`clone` failed, or an unexpected non-fast-forward | reported as a hard failure |

Notes:
- A clean feature branch that still exists upstream is **fast-forwarded in place**; you
  stay checked out on it.
- "Unpushed commits" means commits on `HEAD` not present on the configured upstream
  (or, for a never-pushed/pruned branch, not contained in any remote branch).

## End-of-run summary

`Cloned` and `Refreshed` are always shown; the other sections appear only when non-empty:

```
===== Summary =====
Cloned:    0
Refreshed: 33
Healed:    1   (stale branch removed, switched to default)
  - docs-control: removed 'feat/require-translation-audit'

⚠️  Needs your attention (2)
  - console: 1 uncommitted file on 'main'
  - marketplace: 2 unpushed commits on 'chore/example-naming-convention'

❌ Errors (1)
  - xcsh: fetch failed
```

**Exit code** is non-zero only when there are `error` repos. `attention` is a normal
developer state, not a failure, so it does not fail the run — automation can still gate
on real errors.

## Tests

`clone-all-repos.test.sh` sources the script (its `main` is guarded by a `BASH_SOURCE`
check, so sourcing runs no network calls) and drives `refresh_repo` against local git
fixtures — a bare "remote" plus a working clone built in a temp dir per scenario. It
covers each outcome including the universal checks (dirty on `main`, unpushed commits on
a live feature branch). Run it directly:

```bash
./clone-all-repos.test.sh        # 28 assertions across 7 scenarios; exits non-zero on failure
shellcheck clone-all-repos.sh clone-all-repos.test.sh
```

[manifest]: https://raw.githubusercontent.com/f5xc-salesdemos/docs-control/refs/heads/main/.github/config/downstream-repos.json
