# task.bash -- Harmonize Your Unix Work Environments with Idempotent Tasks

![version](assets/version.svg) ![lines](assets/lines.svg) ![tests](assets/tests.svg) ![coverage](assets/coverage.svg)

Create a configuration script that follows you across machines. Use shell-native tasks that
keep your systems consistent, idempotent, and version-controlled -- all in plain Bash.

**Requires Bash 5**

![update-env](assets/update-env.gif)

*The output of a task.bash configuration script as it runs. Section headings group tasks
together while tasks run with output suppressed, except for `apt upgrade`, which has been
configured to show progress.  A summary at the end shows how many tasks required changes to
the system.*

--------------------------------------------------------------------------------------------

## Why task.bash?

System configuration tools like Make, Ansible, or shell scripts often fall short when your
needs include:

- Working directly in Bash (no YAML, no extra tooling)
- Following installation processes that `source` their own scripts, or modify `PATH`
- Ensuring every task is **idempotent** (run it once or 100 times -- same result)
- Curl-piping from GitHub to bootstrap new machines
- Employing a single script as the **source of truth** for all systems

Use it to:

- Install software
- Clone git repositories
- Make symlinks
- Change directory ownership
- any of Bash's other greatest hits

Other features:

- Output suppression and concise status lines
- Progress display for long-running commands
- Summarized reports at the end of the run
- Simple user prompting (e.g., for passwords)
- Ad-hoc scripting support

--------------------------------------------------------------------------------------------

## Installation

Clone or copy `task.bash` to a location where your configuration script can source it:

`update-env`:

``` bash
source /path/to/task.bash
```

You may also **vendor it inline** by pasting the contents of `task.bash` into your config
script in place of the `source` line.

--------------------------------------------------------------------------------------------

## Getting Started

`task.bash` introduces the concept of a **task** -- a Bash function designed to be
**idempotent**.

**Idempotent** means the system ends up in the same desired state whether the task is run
once or many times. Since raw shell commands aren’t naturally idempotent, task.bash gives
you tools to make them so.

--------------------------------------------------------------------------------------------

## Anatomy of a Task

Here’s the minimal structure of a task:

``` bash
cloneDotfilesTask() {
  desc  'clone my dotfiles'
  ok    '[[ -e ~/dotfiles ]]'
  cmd   'git clone git@github.com:your/dotfiles ~/dotfiles'
}
```

This task will:

- Clone the user’s dotfiles into `~/dotfiles` **if** that directory doesn’t already exist
- Report `[changed]` if run
- Report `[ok]` if skipped due to the `ok` condition

### Keyword Breakdown

| Keyword | Role                                                         |
|---------|--------------------------------------------------------------|
| `desc`  | Human-readable description for status output                 |
| `ok`    | Bash condition to skip running the task if already satisfied |
| `cmd`   | Command to run if `ok` fails; must be last in the function   |

The `cmd` line triggers the actual execution and finalizes the task definition. All keywords
must appear **before** it.

> ⚠️ `cmd` and `ok` both evaluate strings. Be cautious with user input. Do **not** populate
> user-supplied values into these fields.

--------------------------------------------------------------------------------------------

## Additional Task Keywords

Other optional keywords you can use in a task:

| Keyword        | Purpose                                                                    |
|----------------|----------------------------------------------------------------------------|
| `exist PATH`   | Shortcut for `ok` with `[[ -e PATH ]]`                                     |
| `prog on\|off` | Show live command output                                                   |
| `runas USER`   | Run command with `sudo -u USER`                                            |
| `unchg TEXT`   | Look for `TEXT` in output; if found, mark as `[ok]` instead of `[changed]` |

We’ll explore each of these in examples below.

--------------------------------------------------------------------------------------------

## task.bash Functions

The keywords (`desc`, `ok`, `cmd`, etc.) are Bash functions used within task definitions.
Additional helper functions are provided under the `task.` namespace:

| Function                   | Purpose                                        |
|----------------------------|------------------------------------------------|
| `task.Platform`            | Return `macos` or `linux`                      |
| `task.Summarize`           | Display summary of task outcomes               |
| `task.SetShortRun on\|off` | Skip long-running tasks with `prog` or `unchg` |

These use **PascalCase** with a `task.` prefix to avoid namespace conflicts in your shell
environment.

--------------------------------------------------------------------------------------------

## Configuration Script Outline

A typical script using task.bash has two parts: defining tasks and running them.

Here’s a minimal example (`update-env`):

``` bash
#!/usr/bin/env bash

main() {
  # stop execution if a command fails or a variable reference is unset
  set -euo pipefail

  cloneDotfilesTask
  task.Summarize
}

cloneDotfilesTask() {
  desc  'clone my dotfiles'
  exist ~/dotfiles
  cmd   'git clone git@github.com:user/dotfiles ~/dotfiles'
}

source ./task.bash
main
```

Run it:

``` bash
chmod +x update-env
./update-env
```

### What You’ll See

``` bash
[changed]       clone my dotfiles

[summary]
ok:      0
changed: 1
```

- Output is color-coded (green for `[ok]`/`[changed]`, red for `[failed]`)
- Command output is hidden unless `prog on` is used

Run the script again and it will skip the task:

``` bash
[ok]           clone my dotfiles
```

If a command fails or its `ok` condition still fails afterward, the task is marked
`[failed]`, and the script stops, so long as strict mode is enabled (`set -euo pipefail`).

--------------------------------------------------------------------------------------------

## Defining Other Task Types

### Speculative Commands (e.g., package upgrades)

These don’t know in advance if they’ll make a change -- they depend on mutable external
state, such as the versions of software in a package repository.

``` bash
aptUpgradeTask() {
  desc  'upgrade system packages'
  prog  on                                  # apt takes a long time, show progress
  runas root                                # apt needs root permissions
  unchg '0 upgraded, 0 newly installed'     # apt tells us whether anything changed
  cmd   'apt update -qq && apt upgrade -y'
}
```

Explanation:

- `prog on` -- enables live output
- `runas root` -- executes via `sudo`
- `unchg` -- checks for output suggesting no changes, and maps it to `[ok]`

--------------------------------------------------------------------------------------------

### Advanced Bash (e.g. pipelines, redirection, command lists)

``` bash
curlTask() {
  desc   'download coolscript from github'
  exist  ~/.local/bin/coolscript
  cmd    '
    mkdir -p ~/.local/bin
    curl -fsSL https://github.com/user/coolscript >~/.local/bin/coolscript
  '
}
```

- `cmd` supports arbitrary Bash strings, including operators and command lists
- When quoting commands as strings becomes unwieldy, see the *fauxsure* approach below
- When testing for file or directory existence, prefer `exist` to `ok` for readability

--------------------------------------------------------------------------------------------

### Parameterized Tasks

``` bash
mkdirTask() {
  local dir=$1
  desc "make directory $dir"

  mkdirP() { mkdir -p "$dir"; }
  cmd mkdirP
}
```

This approach avoids quoting pitfalls and enables reuse.

Define a function like `mkdirP` inside the task.  It is defined in the function namespace as
usual, so avoid naming conflicts with other commands/functions.

It looks like a closure, but is not because Bash does not have closures.  Instead, since
`cmd` executes `mkdirP`, `$dir` is still in an outer scope when `mkdirP` is run, giving
`mkdirP` access to it via Bash's dynamic scoping.  Since it looks like a closure but isn't,
I call it a **fauxsure**.

Now when calling the task, you can supply a directory name as an argument:

```bash
mkdirTask ~/.config/myapp
```

--------------------------------------------------------------------------------------------

## Example: update-env

See the `update-env` script in this repo for a real-world example.

It:

- Manages dotfiles, packages, and symlinks
- Uses `task.bash` to stay declarative and idempotent
- Bootstraps clean machines via curl-pipe from GitHub

``` bash
curl -fsSL https://raw.githubusercontent.com/your/repo/main/update-env | bash
```

task.bash complements tools like **Nix** and **home-manager**, augmenting a declarative
packaging system with idempotent imperative tasks in Bash.

--------------------------------------------------------------------------------------------

## Summary

`task.bash` is ideal when:

- You want to control system config via shell, not YAML
- You care about managing multiple personal systems and platforms
- You want idempotency and progress visibility in Bash
- You don’t want to adopt heavyweight tools with less flexibility

--------------------------------------------------------------------------------------------

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
