# task.bash Use Cases

## System Scope

**System:** task.bash
**In scope:** Idempotent task execution, status reporting, graceful failure, git repository synchronization
**Out of scope:** Package management, configuration templating, remote execution, container orchestration

## System Invariants

- **Idempotent execution:** Running a task N times produces the same system state as running it once.
- **Status truthfulness:** A task reports `[ok]` only when its success condition is met. A task reports `[changed]` only when the command ran and the condition is now met.
- **Try isolation:** Failure within a `try` scope does not propagate beyond that scope. `TryFailedX` is saved and restored around each `try` call.
- **Output suppression by default:** Command output is captured, not displayed. Only `prog on` tasks show live output.
- **Single-file sourcing:** The library is one file with no dependencies beyond Bash 5.

## System-in-Use Story

> Alex maintains three machines: a work laptop, a home desktop, and a Chromebook. Each needs the same dotfiles, symlinks, packages, and git clones. Alex writes a single `update-env` script that sources `task.bash` and defines tasks for each piece of setup. Running `update-env` on any machine brings it to the desired state. Tasks that are already satisfied show `[ok]`; tasks that make changes show `[changed]`; tasks that fail gracefully (like VPN-dependent clones when offline) show `[tried]` and don't stop the rest of the script. At the end, a summary shows what happened.

> Later, Alex adds a new repository. The script clones it on the first run and shows `[changed]`. On subsequent runs it pulls the latest changes and shows `[ok]` when already up to date. When Alex has unpushed local commits, the update is safely skipped.

## Actor-Goal List

### Script Author

**Characterization:** Developer who writes configuration scripts using task.bash
**Goals:**
- [Blue] Define an idempotent task (high)
- [Blue] Run tasks with graceful failure (high)
- [Blue] Clone and update git repositories (high)
- [Blue] Display task progress and summary (med)

---

### UC-1: Define an Idempotent Task

- **Primary Actor:** Script Author
- **Goal:** Define a task that achieves a desired system state exactly once
- **Scope:** task.bash
- **Level:** User goal
- **Trigger:** Author writes a task function in their configuration script
- **Preconditions:** task.bash is sourced
- **Stakeholders:**
  - Script Author -- needs clear, minimal syntax for common patterns
  - End User (person running the script) -- needs accurate status reporting
- **Main Success Scenario:**
  1. Author defines a function containing `desc`, a condition keyword, and `cmd`.
  2. `desc` sets the task description for status output.
  3. Author specifies when the task is already satisfied via `ok`, `exist`, or `unchg`.
  4. `cmd` specifies the command to run.
  5. System evaluates the condition. Condition met: system reports `[ok]`, skips `cmd`.
  6. Condition not met: system runs `cmd`, re-evaluates condition, reports `[changed]`.
- **Extensions:**
  - 3a. Author uses `exist PATH` for file/directory existence:
    1. System expands to `ok '[[ -e PATH ]]'`.
  - 3b. Author uses `unchg TEXT` for commands that report their own no-op:
    1. System runs `cmd`, checks output for TEXT.
    2. TEXT found: system reports `[ok]`.
  - 5a. Author specifies `check EXPR` as a preflight gate:
    1. System evaluates EXPR before `cmd`.
    2. EXPR fails: system reports `[tried]` (under try) or `[failed]`, skips `cmd`.
  - 6a. `cmd` fails (nonzero exit):
    1. System reports `[failed]` and stops execution.
  - 6b. `cmd` succeeds but condition still not met:
    1. System reports `[failed]` with "task reported success but condition not met".
- **Success Guarantee:** System state matches the condition, or failure is reported with diagnostic output.
- **Minimal Guarantee:** No partial state changes are hidden -- every task outcome is reported.

---

### UC-2: Run Tasks with Graceful Failure

- **Primary Actor:** Script Author
- **Goal:** Allow non-critical tasks to fail without stopping the script
- **Scope:** task.bash
- **Level:** User goal
- **Trigger:** Author wraps a task call in `try`
- **Preconditions:** task.bash is sourced; at least one task is defined
- **Stakeholders:**
  - Script Author -- needs failure isolation for optional/network-dependent tasks
  - End User -- needs to see which tasks were skipped and why
- **Main Success Scenario:**
  1. Author wraps task call(s) in `try`.
  2. System saves current try state (TryModeX, TryFailedX).
  3. System executes the task with TryModeX=1.
  4. Task succeeds: system reports `[ok]` or `[changed]`.
  5. System restores prior try state.
- **Extensions:**
  - 4a. Task fails (cmd exits nonzero or condition not met):
    1. System reports `[tried]` instead of `[failed]`.
    2. System sets TryFailedX=1.
    3. System returns 0 (suppresses set -e termination).
  - 4b. Subsequent cmd calls in the same try scope after a failure:
    1. System reports `[skipping]` without running the command.
  - 3a. Nested try within a try:
    1. Inner try saves/restores its own TryFailedX.
    2. Inner failure does not propagate to outer scope.
- **Success Guarantee:** All tasks in the try scope are attempted or explicitly skipped; script continues.
- **Minimal Guarantee:** try always returns 0; prior try state is restored.

---

### UC-3: Clone and Update Git Repositories

- **Primary Actor:** Script Author
- **Goal:** Keep local repository clones current with their remotes
- **Scope:** task.bash
- **Level:** User goal
- **Trigger:** Author calls `task.GitClone` or `task.GitUpdate`
- **Preconditions:** git is available; network is reachable (or task is wrapped in `try`)
- **Stakeholders:**
  - Script Author -- needs reliable repo sync without manual intervention
  - End User -- needs local scaffold artifacts (symlinks, tool wrappers) preserved across updates
- **Main Success Scenario:**
  1. Author calls `task.GitClone REPO DIR BRANCH` to ensure a clone exists.
  2. System checks if DIR exists. Exists: reports `[ok]`.
  3. DIR missing: system clones REPO into DIR, reports `[changed]`.
  4. Author calls `task.GitUpdate DIR` to pull latest changes.
  5. System runs gitUpdateSafe preflight: checks branch, upstream, no unpushed commits.
  6. System fetches from remote.
  7. System detects incoming files that would collide with local untracked working-tree files.
  8. System temporarily stashes colliding files.
  9. System rebases onto upstream.
  10. System restores stashed files (overwriting upstream versions in working tree).
  11. Already up to date: system reports `[ok]`. Changes pulled: reports `[changed]`.
- **Extensions:**
  - 5a. Preflight fails (detached HEAD, no upstream, unpushed commits):
    1. System reports `[tried]` (under try) or `[failed]`, skips pull entirely.
  - 7a. No colliding files detected:
    1. System skips stash/restore, rebases directly.
  - 9a. Rebase fails (merge conflict):
    1. System restores stashed files before returning failure.
    2. System reports `[tried]` (under try) or `[failed]`.
  - 10a. Restored file is now a tracked modification (upstream version is in index):
    1. On subsequent pulls, autoStash handles it as a normal tracked-file modification.
    2. This is intentional self-healing behavior.
  - 6a. Network timeout (ConnectTimeout=10):
    1. System fails the fetch, reports `[tried]` (under try).
- **Success Guarantee:** Local clone is up to date with remote; scaffold artifacts are preserved.
- **Minimal Guarantee:** Stashed files are always restored, even on failure. Local commits are never rebased away.

---

### UC-4: Display Task Progress and Summary

- **Primary Actor:** Script Author (configuring); End User (observing)
- **Goal:** See concise, color-coded status for each task and an overall summary
- **Scope:** task.bash
- **Level:** Subfunction
- **Trigger:** Tasks execute; author calls `task.Summarize` at script end
- **Preconditions:** task.bash is sourced; tasks have been executed
- **Stakeholders:**
  - End User -- needs at-a-glance understanding of what changed vs what was already fine
- **Main Success Scenario:**
  1. Each task reports its outcome as a single color-coded line.
  2. `prog on` tasks show live output during execution.
  3. Author calls `task.Summarize` at the end.
  4. System prints counts: ok, changed, tried.
- **Extensions:**
  - 1a. Failed task under try:
    1. Output is dumped (up to 20 lines) with `[output]` prefix.
  - 1b. Task in short-run mode with progress or unchg:
    1. System reports `[skipping]` without running.
- **Technology & Data Variations:**
  - Status colors: green (ok, changed), orange (tried, skipping, output), red (failed), yellow (begin, progress)
- **Success Guarantee:** Every executed task has exactly one status line; summary counts are accurate.
- **Minimal Guarantee:** Status lines are always printed, even on failure.
