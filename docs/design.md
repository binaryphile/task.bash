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
| `[progress]` | yellow | Task with live output starting (live-tee mode only — `prog on` AND a writable controlling TTY; otherwise `[begin]` is emitted per UC-4 Extension 2a) |
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

## Install and Ln helpers

### task.Install

Copies `src` to `dst` with a declared permission `mode`. Idempotency check
(see UC-5) is content+mode, not bare existence:

```bash
ok "[[ -e '$dst' ]] && cmp -s -- '$src' '$dst' && [[ -n \$(find -- '$dst' -perm '$mode' -print -quit 2>/dev/null) ]]"
```

Three conjuncts, all must hold for `[ok]`:

- **Existence** (`-e '$dst'`) -- a missing destination is always a fresh install.
- **Content** (`cmp -s`) -- byte-for-byte comparison; any drift (source edited
  since the last install) fails this and triggers a re-copy.
- **Mode** (`find -perm`, not `stat`) -- `stat`'s output-format flags differ
  between GNU coreutils (`-c %a`) and BSD/macOS (`-f %A` or similar), and
  `task.Platform()` shows this library explicitly supports both platforms.
  `find`'s `-perm` predicate with a numeric mode is portable across GNU
  findutils and BSD find, so it's used instead of parsing a stat format
  string. `-print -quit` short-circuits after the first match instead of
  walking further (there's only one path to check).

The `\$(...)` inside the double-quoted `ok` string is deliberate, not a
typo: `$src`/`$dst`/`$mode` are substituted immediately when `task.Install`
is called (matching the pre-existing `exist "'$dst'"` pattern), but the
`find` invocation itself must stay as literal text in `ConditionX` until
`task.classify` later `eval`s it -- otherwise it would run once at
declaration time and never reflect the destination's state at the moment
each subsequent run actually checks it.

Before this check existed, `task.Install` was idempotent purely by
destination existence: once `dst` existed, editing `src` and re-running
was a silent no-op. This surfaced in practice via `update-env`, which uses
`task.Install` to deploy canonical dotfiles-managed files (systemd units,
etc.) -- a destination that already existed on a machine never picked up
source edits without manual intervention.

**Known limitation, widened by this change (icarus /grade #29586 F4):**
`ConditionX` is built by substituting `$src`/`$dst` inside single quotes,
so a literal `'` in either path breaks the generated `[[ ]]`/`eval`
expression. The pre-existing `exist "'$dst'"` check already had this for
`dst`; this change extends it to `src` too, since `src` is now
interpolated into the condition for the first time. This is unchanged
"same shape" technical debt, not a new class of bug, but it is a strictly
larger surface than before -- worth knowing if callers ever pass paths
containing single quotes (outside this library's assumed contract).

**Postcondition scope:** "content and mode always match after a run" (see
UC-5) assumes `dst` is (or becomes) an ordinary file. The predicate itself
only classifies `dst`'s *current* state; it does not verify that
`task.install`'s `install -m` actually achieved the postcondition, and
neither the check nor `task.install` special-cases `dst` being a symlink
or a directory -- behavior there is unspecified, not tested.

### task.Ln

Symlinks `linkname` -> `targetname`. Idempotency is literal `readlink`
equality, not content comparison -- a symlink always resolves to its
current target's live content, so there's no analog of task.Install's
propagation gap here. No re-run is ever needed for the target's content to
"propagate": reading through the symlink already sees it.

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

**Phase 4: Post-condition (HEAD == upstream verification)**

```
behind=$(git rev-list --count HEAD..@{upstream})
[[ $behind != 0 ]] && echo "post-rebase divergence: $dir still $behind commit(s) behind @{upstream}"
```

After a successful rebase (rc=0), `task.gitUpdate` verifies HEAD is at or
strictly ahead of upstream. Catches the silent-no-op failure class where
`git rebase` returns 0 but HEAD did not advance to upstream (corrupted
tracking refs, race conditions where rebase replays onto stale upstream
state, etc.) — failures that would otherwise leave the repo behind while
the framework reports `[tried]` with no diagnostic.

On `rev-list` itself failing (corrupted refs), `behind` is the sentinel
string `rev-list-failed`, which compares non-zero and surfaces visibly
rather than passing silently.

Skipped when rebase already returned non-zero — real rebase failures
already surface; don't double-report. On post-condition trip, emits
`post-rebase divergence: ...` and returns non-zero, which the task
framework reports as `[failed]` (or `[tried]` under `try`-wrapped
invocation) with the `[output]` line carrying the literal divergence
message.

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
| `cmd` | Controller | Integration test (6 cases via output matching; `task.hasTty` mocked for no-TTY cases, `tee` mocked for runtime-failure case — see UC-4 Extensions 2a, 2b) |
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
