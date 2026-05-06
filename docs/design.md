# task.bash -- Design

How task.bash is built. For what task.bash does, see [use-cases.md](use-cases.md).

## Architecture

Single-file Bash library, sourced into the caller's shell. No subprocesses, no
dependencies beyond Bash 5. All state is global variables suffixed with `X` to
avoid namespace collisions (e.g. `DescriptionX`, `TryModeX`).

```
┌─────────────────────────────────────────┐
│  update-env (user script)               │
│                                         │
│  source task.bash                       │
│                                         │
│  myTask() {                             │
│    desc  'do something'                 │
│    ok    '[[ -e /thing ]]'              │
│    cmd   'make-thing'                   │
│  }                                      │
│  myTask                                 │
│  task.Summarize                         │
└─────────────────────────────────────────┘
         │ keywords set global state
         ▼
┌─────────────────────────────────────────┐
│  task.bash                              │
│                                         │
│  Keywords:  desc, ok, exist, check,     │
│             unchg, prog, runas, cmd     │
│                                         │
│  Helpers:   task.GitClone               │
│             task.GitUpdate              │
│             task.Install                │
│             task.Ln                     │
│             try                         │
│                                         │
│  Reporting: task.Summarize              │
│             task.t (color rendering)    │
│             section                     │
└─────────────────────────────────────────┘
```

### Style

Code follows the [Bash Style Guide]. The summary below covers task.bash-specific
applications; the guide is authoritative for anything not listed here.

[Bash Style Guide]: https://binaryphile.github.io/2026/02/27/bash-style-guide

**Naming conventions:**

| Kind | Convention | Example |
|------|-----------|---------|
| Public function | `task.PascalCase` | `task.GitUpdate` |
| Private function | `task.camelCase` | `task.gitUpdateSafe` |
| Keyword function | lowercase, <= 5 chars | `desc`, `cmd`, `ok` |
| Global variable | `PascalCaseX` | `TryModeX` |
| Local variable | `camelCase` | `localHead` |
| Nameref | `local -n UPPERCASE=$1` | borrows env namespace |

The `X` suffix on globals is the project-specific namespace letter per the style
guide's library convention. Library consumers should not read or write these
directly.

**IFS and noglob:** task.bash expects `IFS=$'\n'` and noglob from its callers
(library convention). Functions that need whitespace splitting set IFS locally
(e.g. `IFS=$' \t' read -r ahead behind`).

## Task lifecycle

Every task follows the same lifecycle through `cmd`:

```
desc "task description"          # resets task state via task.initTaskEnv
ok/exist/check/unchg/prog/runas  # configure task (order doesn't matter)
cmd 'command'                    # executes and reports
```

`cmd` is the terminal keyword -- it triggers evaluation and must be last.

### Status classification

Classification is separated from presentation. Two pure decision functions
determine outcomes; `cmd` handles rendering and state recording.

**`task.classify`** — pre-execution decision (should the command run?):

```
TryFailedX?        → skipping
condition met?     → ok
check fails?       → check_failed
ShortRun + slow?   → shortrun_skip
else               → run
```

**`task.classifyResult`** — post-execution decision (what happened?):

```
unchg text in output?      → ok
RC==0 and condition met?   → changed
else                       → failed
```

**`cmd`** — controller that calls both classifiers and handles rendering:
- Pre-execution: calls `task.classify`, renders status, returns early if not `run`
- Execution: runs command, captures output and exit code
- Post-execution: calls `task.classifyResult`, renders status, records in
  tracking arrays, dumps output on failure

This separation means classification logic is independently testable as domain
logic (Khorikov: unit test), while the controller is tested via output-matching
integration tests.

### Status meanings

| Status | Color | Meaning |
|--------|-------|---------|
| `[ok]` | green | Already satisfied, nothing to do |
| `[changed]` | green | Command ran and condition now met |
| `[tried]` | orange | Failed gracefully under `try` |
| `[skipping]` | orange | Skipped (prior try failure or short-run mode) |
| `[failed]` | red | Failed, script stops |
| `[begin]` | yellow | Task starting (shown before command runs) |
| `[progress]` | yellow | Task with live output starting |
| `[output]` | orange | Dumped output from failed command |

## Try scoping

`try` enables graceful failure. It saves and restores two globals:

```bash
try() {
  local prevTryMode=$TryModeX prevTryFailed=$TryFailedX
  TryModeX=1
  TryFailedX=0
  "$@"
  TryModeX=$prevTryMode
  TryFailedX=$prevTryFailed
}
```

Key semantics:
- **TryModeX=1** changes `cmd` behavior: failures become `[tried]` (rc=0) instead
  of `[failed]` (rc=1, script stops).
- **TryFailedX** cascades within a scope: once set, subsequent `cmd` calls in the
  same scope become `[skipping]`.
- **Save/restore** means nested `try` blocks are isolated. Inner failure does not
  poison the outer scope.
- `try` always returns 0 because `cmd` returns 0 in try mode.

## Git helpers

### task.GitClone

Clones a repo if the directory doesn't exist. Uses `exist` for idempotency.
ConnectTimeout=10 for SSH and HTTP.

### task.GitUpdate

Pulls latest changes via fetch + rebase. Three-phase process:

**Phase 1: Preflight (gitUpdateSafe)**

Blocks pull if the repo is in an unsafe state:
- Detached HEAD
- No upstream tracking branch
- Unpushed local commits (ahead > 0)

This runs as a `check` -- failure is silent and immediate.

**Phase 2: Fetch and conflict detection**

```
git fetch                              # update tracking refs
git diff --name-only HEAD upstream     # find incoming files
```

For each incoming file: if it is not tracked locally but exists in the working
tree (as a regular file or symlink), it will conflict with rebase. These files
are moved to temporary locations in `.git/`.

Why not `git ls-files --others --exclude-standard`? Because scaffold files are
typically in `.git/info/exclude` (e.g. `/bin`), which hides them from the
`--exclude-standard` listing. Instead, we walk incoming files and check the
working tree directly.

Why check `-e OR -L`? Scaffold files are often broken symlinks (e.g.
`bin/node -> nix-wrapper` where the target doesn't exist yet). `-e` follows
symlinks and returns false for broken ones; `-L` checks the link itself.

**Phase 3: Rebase and restore**

```
git rebase @{upstream}
# restore stashed files unconditionally
```

After restore, the stashed file overwrites whatever upstream placed at that
path. The file now appears as a tracked modification in `git status`. This is
intentional -- on subsequent pulls, `rebase.autoStash` handles tracked-file
modifications automatically. The first update converts an untracked conflict
into a tracked modification; all future updates are self-healing.

Restore happens even if rebase fails, ensuring scaffold artifacts are never
lost.

### Timeout policy

All git network operations use ConnectTimeout=10 (SSH) and
http.connectTimeout=10 (HTTP). This accommodates slow SSH handshakes (Codeberg
~5s, GitHub ~1s) while failing fast enough for truly unreachable hosts. SSH and
HTTP timeouts are coupled at the same value for simplicity.

## Color and translation

Status labels are rendered via `task.t`, which maps label names to ANSI color
codes via the `Translations` associative array. All callers of `task.t` must use
a key present in the array -- missing keys cause `unbound variable` errors under
`set -u`.

## Testing

Tests use the [tesht](https://github.com/binaryphile/tesht) framework.

### Khorikov quadrant mapping

| Code | Quadrant | Test strategy |
|------|----------|---------------|
| `task.classify` | Domain | Unit test (8 cases covering all branches) |
| `task.classifyResult` | Domain | Unit test (5 cases including priority rules) |
| `task.gitUpdateSafe` | Domain | Unit test (4 cases: safe, detached, ahead, no upstream) |
| `task.gitUpdate` | Controller | Integration test (4 cases with real git repos) |
| `cmd` | Controller | Integration test (3 cases via output matching) |
| `try` | Trivial (but contract matters) | Unit test (5 cases for scoping semantics) |
| `task.t`, keywords, `section` | Trivial | Not tested |

### Patterns

- **Table-driven subtests:** Define `local -A caseN=(...)` maps, iterate with
  `tesht.Run`. Each subtest gets a `subtest()` function that arranges, acts, and
  asserts.
- **Git test repos:** `createCloneRepo` creates a bare local repo for clone
  tests. GitUpdate tests create a remote + clone pair with upstream tracking.
- **Output matching:** `wants` arrays use glob matching via
  `$(IFS='*'; echo "*${wants[*]}*")` for flexible substring matching.
- **Temp directories:** `tesht.MktempDir` creates isolated temp dirs, cleaned up
  by tesht after each subtest.
