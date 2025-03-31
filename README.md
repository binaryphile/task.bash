# task.bash -- harmonize your Unix work environments

![version](assets/version.svg) ![lines](assets/lines.svg) ![tests](assets/tests.svg) ![coverage](assets/coverage.svg)

Create your work environment that follows you everywhere. Keep up to date via integration
with your workflow.

**Requires Bash 5**

![update-env](assets/update-env.gif)

With task.bash, you capture your configuration in a shell script.  Writing a script that
installs some software is easy.  Writing one that both configures a fresh system, then
updates it later is more difficult.  Once accomplished though, you have a single environment
that follows you everywhere, to any machine.

Task.bash assists by making it easy to:

- transform shell commands into idempotent tasks

- drive configuration changes through your script, maintaining it as the source of truth

- work with components that require shell setup, such as needing to source a provided
    script or modify PATH

- work with components that are too new or difficult for less flexible configuration
    solutions

That means you can easily synchronize your environments across machines. Create a
configuration script that lives in a git repository.  New machines run the script by
curl-piping it from GitHub.  The repo is then cloned to the machine and gets updates from
git.  *You* are the synchronization mechanism, in tandem with git.  Your system changes when
you tell it to, much like when you run package upgrades.  Run your script when you would
have upgraded via the package manager in the past, or more often.

Other features:

- command output suppression
- human-friendly ongoing status reporting
- post-run summarization
- user interaction, e.g. the ability to prompt for a password
- ad-hoc scripting

## Installation

Clone or copy `task.bash` where it can be sourced by your script.

Alternatively, vendor it into your configuration script by pasting it in place of the
`source` command.

## Getting Started

Task.bash relies on the concept of tasks, where a task is a Bash function that is
idempotent.

Idempotence simply means that the task results in the same outcome if it is run once or a
hundred times.  Bash commands aren't necessarily idempotent by default, so task.bash helps
you make them so.

## Anatomy of a task

```bash
cloneDotfilesTask() {           # <== task name, ends with Task by convention
  desc  'clone my dotfiles'     # <== what shows up in the output for this task
  ok    '[[ -e ~/dotfiles ]]'   # <== don't run the command if "ok" evals true -- idempotency!

  cmd   'git clone git@github.com:user/dotfiles ~/dotfiles'
}
```

When this task is run, it clones user's dotfiles from GitHub into `~/dotfiles` and reports
the task as `[changed]`.  If `~/dotfiles` already exists, however, it is reported as `[ok]`
and is not run.

Each keyword (`desc`, `ok`, `cmd`) is a function that configures the task.  `cmd` does
double-duty, defining the task's command as well as running it. Because it needs the rest of
the task definition, `cmd` *must* be the last line of the definition.

By convention, `desc` is the first line, serving as a comment to describe the task.  All
other task.bash keywords can come between `desc` and `cmd` in any order.

The `ok` keyword tells task.bash how to tell if the command is satisfied.  `ok` can take a
simple `test` expression, or arbitrary code.  It is evaluated before the command.  If the
code evaluates to true (return code 0), the task is already satisfied and does not continue.
Otherwise, the command is run.  If it is run, the condition is checked afterward and this
time, if it does not pass, the task is marked `[failed]` and the script stops.

Notice that each keyword takes one argument.  `ok` and `cmd` both contain code, and
task.bash `eval`s that code, so expansions like `~/dotfiles` are taken care of.  *For
security, do not populate user input into these fields.*

## Additional Task Keywords

The rest of task.bash's features lie in the remaining keywords.  Each of these can appear in
a task definition:

- `exist PATH` -- ok if PATH exists, alternative to `ok`
- `prog on|off` -- show command output as it runs
- `runas USER` -- run the command as the user USER, using sudo
- `unchg TEXT` -- look for TEXT in command output and if present, mark the task `[ok]`

We'll revisit these as we define examples.

## Task.bash Functions

While the keywords already described are technically functions, we call them keywords to
distinguish them from the naming used for other task.bash functions.

Most Bash code you will see uses snake_case for functions and variables.  That's fine, but
when using libraries, namespacing matters.  A naming scheme like Go's integrates better with
a namespace already inhabited by environment variables and third-party code.

By convention, task.bash uses function names like `task.SetShortRun`, where the function
name is PascalCased.  The name is also prefixed with `task` so task.bash's functions won't
conflict with your function names.

There are a handful of functions in addition to the task keywords we've seen already:

- `task.Summarize` - summarize the results of the run
- `task.SetShortRun on|off` - skip long tasks (tasks with `prog` or `unchg`)

`task.Summarize` should be part of any script, run after all of the tasks to report what
happened.

`task.SetShortRun` allows your script to take an option that tells task.bash to skip
long-running tasks.  Any task marked with `prog` or `unchg` is considered long-running
automatically.

### Configuration Script Outline

A configuration script has two parts: one that defines tasks and the other that runs them.

We call this script `update-env`:

```bash
#!/usr/bin/env bash

main() {    # <== using main lets us put it here up top, where it belongs
  # do tasks
  cloneDotfilesTask

  # summarize the results in output
  task.Summarize
}

cloneDotfilesTask() {
  ...
}

# boilerplate
source /path/to/task.bash
main
```

`chmod +x update-env` the file so we can run it in a bit.

## Defining Tasks

The goal of most tasks is to make a command idempotent.  However, what that means can vary
from command to command.  We'll take a look at how you might want to approach different
kinds of commands.

### Speculative commands

Some commands are designed to update the system based on external input, such as the package
manager.  If a package has a new version, the package manager installs it, otherwise it does
nothing.

Commands such as this are speculative; they have to check elsewhere before determining what
to do, if anything.  When running the upgrade, we don't know if we should be expecting a new
package version or not...the package manager has to tell us. That means:

- there is no way to specify an `ok` expression for them a priori
- task.bash must look at the command output to tell what status to report, `ok` or `changed`

Here is a task for `apt upgrade`:

```bash
aptUpgradeTask() {
  desc  'upgrade system packages'
  prog  on
  runas root
  unchg '0 upgraded, 0 newly installed'

  cmd   'apt update -qq && apt upgrade -y'
}
```

We're seeing new keywords here, `prog`, `runas` and `unchg`:

#### `prog on` enables command output

`apt` can take some time.  If there is no output, your script can seem frozen. `prog on`
enables command output to tell you when the command is making progress.  Such output starts
with `[progress]`.

#### `runas USER` runs the command as USER

`apt` needs root permissions to modify the system.  `runas root` tells task.bash to use
`sudo` to run the command as root user.

#### `unchg TEXT` tells task.bash whether the command made changes

`apt` conveniently reports whether packages were installed or updated. `unchg` looks for
that message and marks the task `[ok]` if we see it, otherwise `[changed]`.

### Tasks with complex commands

```bash
curlTask() {
  desc   'download coolscript from github'
  exist  ~/.local/bin/coolscript

  cmd    "
    mkdir -p ~/.local/bin
    curl -fsSL git@github.com:user/coolscript >~/.local/bin/coolscript
  "
}
```

We saw that `cmd` can take commands like `apt update -qq && apt upgrade -y` but you can use
`cmd` with arbitrary Bash, including multi-line scripts, pipelines, you name it.

Multiline quotes are convenient in this case, but should the code be more than a few lines,
you'll probably want to put it in its own function and call that with `cmd` instead.

We also see here the `exist` keyword:

#### `exist PATH` sets ok with the Bash -e path existence test

`exist` sets `ok` with a path existence test, meaning you only need to specify one of `ok`
or `exist`.  It is a frequently-useful test, so task definitions benefit from the more
readable `exist`.

### Tasks with complex satisfaction criteria

...

### Nearly-idempotent commands and generalized tasks

Some commands are already known for idempotence, like `touch` to create a file or `mkdir -p`
to make directories.  You may still want to make a task of one for task.bash's reporting
feature.  Here's a generalized task for making directories:

```bash
mkdirTask() {
  local dir=$1

  desc  "make directory $dir"
  cmd   "mkdir -p '$dir'"
}
```

Notice the quotes have been changed to allow variable expansion.

This task will show up in the output like other tasks.  Since there's no `ok`, it will run
and always report as changed, but that's usually fine.  If you were to add and `exist` line
for the directory, it would then be idempotent on its own and you could drop `-p`.

`touch`, on the other hand, may be idempotent for creating a file, but it's not completely
idempotent.  It updates the modified time of the file, which is a different outcome each
time it's run. The `exist` keyword can make it completely idempotent, since `touch` won't
run if the file exists:

```bash
touchTask() {
  local file=$1

  desc  "create file $file"
  exist "'$file'"
  cmd   "touch '$file'"
}
```

Task.bash comes with a handful of generalized tasks, such as `task.GitClone`.

## Running Tasks

Before we run the script, however, we need to add one more thing, to enable Bash strict
mode.  Bash strict mode allows the script to stop when errors occur and to flag unset
variable references, both of which are suited to scripting.  By convention, we set it at the
beginning of `main`:

```bash
main() {
  set -euo pipefail
  cloneDotFilesTask
  task.Summarize
}
```

We strongly advise you to employ strict mode.  Otherwise error conditions may cause further
errors, and when dealing with system-level configuration, that's especially bad.  task.bash
was written on the assumption that strict mode is enabled, and is not tested without it.

Now, here's the output from running the script:

```bash
[changed]       clone dotfiles from github

[summary]
ok:      0
changed: 1
```

The responses are actually color-coded, green for `[ok]` and `[changed]` and red for
`[failed]`.

Notice first that the output of the command is suppressed.  This is so you can account for
many tasks easily without clutter in the output, since it consists of one line per task with
a status and human-friendly message.

However, sometimes a command may take a visible moment or two, or perhaps more than you
thought at first.  For this reason, before the command is run, there is a line of output
showing the `[begin]` status for the task, but that line is overwritten by the result once
it is available.  The `[begin]` status line does not show up in the output above.

If you run the script when the directory exists already, the output will report the `[ok]`
status instead of `[changed]` and nothing will be run.

When a command fails, execution stops and it is reported.  You are shown stdout and stderr
combined for debugging purposes.  If the command reports success, but the
`ok` condition fails anyway, the task is reported as failed.

### Task Types and Other Keywords

There are tasks that require running as another user.  Anything you would use `sudo` for.
For these, there is `runas`:

- `runas` -- run as the named user, typically `root`

Some tasks may take quite a bit of time.  As you wait for the command, task.bash's output
suppression can make things appear to be frozen.  For long-running commands that give
progressive output, such as a package manager upgrade, it is useful to have output display
on screen.  This is the `prog` keyword:

- `prog` -- show progress in the form of command output

Some tasks cannot be made idempotent because they are not idempotent by nature.  System
Updates are one such type of task; it can't be determined beforehand whether or not there is
an update, because the process of checking whether it is needed is part of the operation
itself.

In such cases, you can't tell whether anything was changed in the update process until after
the task has run.  If you're lucky, the update process will indicate whether anything was
changed either by a) a message in the output or b) the absence of a message in the output.
