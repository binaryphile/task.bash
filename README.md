# task.bash -- harmonize your Unix work environments with idempotent tasks

![version](assets/version.svg) ![lines](assets/lines.svg) ![tests](assets/tests.svg) ![coverage](assets/coverage.svg)

Create your work environment that follows you everywhere. Keep up to date via integration
with your workflow.  Idempotency allows one script to keep multiple machines in sync.

**Requires Bash 5**

![update-env](assets/update-env.gif)

With task.bash, you capture your configuration in a shell script.  We all know that writing
a script to install some software packages is easy.  Writing one that both configures a
fresh system, then updates it later is more difficult.  Once accomplished though, you have a
single environment that follows you everywhere, to any machine.

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

Use it to:

- install software
- clone git repositories
- make symlinks
- change directory ownership
- any of Bash's other greatest hits

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
hundred times.  In this case, it means that no matter the state of your system, it will be
brought to the same, current specification when the script is run.  Bash commands aren't
necessarily idempotent by default, so task.bash helps you make them so.

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

There are a couple of functions in addition to the task keywords we've seen already:

- `task.Platform` - returns `macos` on mac, otherwise `linux`
- `task.Summarize` - summarize the results of the run
- `task.SetShortRun on|off` - skip long tasks (tasks with `prog` or `unchg`)

`task.Platform` is intended to be used to conditionally perform tasks based on the current
platform.

`task.Summarize` should be part of any script, run after all of the tasks to report what
happened.

`task.SetShortRun` allows your script to take an option that tells task.bash to skip
long-running tasks.  Any task marked with `prog` or `unchg` is considered long-running
automatically.

### Configuration Script Outline

A configuration script has two parts: one that defines tasks and the other that runs them.

We'll call this script `update-env`:

```bash
#!/usr/bin/env bash

main() {    # <== using main lets us put it here up top, where it belongs
  # do tasks
  cloneDotfilesTask

  # summarize the results in output
  task.Summarize
}

cloneDotfilesTask() { ... }

# boilerplate
source /path/to/task.bash
main
```

`chmod +x update-env` the file so we can run it in a bit.

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

We strongly advise you to employ strict mode.  Otherwise error conditions may allow
execution of unintended codepaths or further errors to occur.  When dealing with
system-level configuration, that's risky.

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

## Defining Tasks

The goal of most tasks is to make a command idempotent.  What that means can vary from
command to command.  We'll take a look at how you might want to approach different kinds of
tasks.

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

### Complex commands

```bash
curlTask() {
  desc   'download coolscript from github'
  exist  ~/.local/bin/coolscript

  cmd    '
    mkdir -p ~/.local/bin
    curl -fsSL git@github.com:user/coolscript >~/.local/bin/coolscript
  '
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

### Parameterized tasks

So far, no task has taken parameters, which makes them hard-coded to things like filenames.
Many tasks are generic enough to be reusable, if they only could take parameters.  Parameter
handling with tasks is a bit tricky though, since controlling the timing of evaluation is
important.

Task.bash comes with a handful of parameterized tasks, such as `task.GitClone` and
`task.Ln`.

Here's a simple example of how to write one:

```bash
mkdirTask() {
  local dir=$1
  desc  "make directory $dir"
  cmd   "mkdir -p $dir"
}
```

First, notice that we're taking the first argument as `dir` and using it in the task
definition.  In order to expand it, we've used double-quotes instead of single.

This works for simple cases but becomes difficult with complexity and edge cases.  For
example, this will not handle directories with spaces as it stands, since expansion will
happen here, and then evaluation by `cmd` will not have the command properly quoted.

We could try to fix it by single-quoting `dir` within the double-quotes, but then it becomes
sensitive to single-quotes in `dir`'s value.  `printf %q` is another option to make the
value eval-safe, but rather than try to quote our way out of it, there's a more readable
option. Let's define a new function within the task and call that.

```bash
mkdirTask() {
  local dir=$1
  desc "make directory $dir"

  mkdirP() { mkdir -p "$dir"; }
  cmd mkdirP
}
```

This is an interesting construction.  It closely resembles a *closure function*, that is, a
function which is aware of the variables in its enclosing scope.

That's not what's going on here, although it does in fact behave like a closure because of
our limited use case.  So long as the call to `mkdirP` is made from within `mkdirTask`, as
it is here, Bash's dynamic scoping will allow `mkdirP` will see the `dir` belonging to
`mkdirTask`.  `mkdirP` could even be defined elsewhere, but it is usually more readable to
define it where it is consumed like this.

The concern this resolves is that, within `mkdirP`, quoting is handled normally.  We aren't
embedding a command in a string, so it's only evaluated once as you'd expect.

This is generally the best pattern for parameterized tasks and handles additional complexity
nicely, since function syntax is friendlier than evaluated string syntax.  For example,
syntax highlighting editors don't generally highlight within strings.

## Example

See `update-env` as an example of what can be accopmlished with a configuration script.  It
is the script I use on my own machines.  Relying on nix and home-manager allows it to
specify packages in a dotfiles repository, which saves from having to track them in the
script.

In particular, see the boilerplate at the end for an example of how to make it curl-pipeable
from GitHub.
