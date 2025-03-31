# task.bash -- harmonize your Unix work environments

![version](badges/version.svg) ![lines](badges/lines.svg) ![tests](badges/tests.svg) ![coverage](badges/coverage.svg)

Use task.bash to create a custom work environment configuration that follows you everywhere
and stays maintained because it is integrated into your daily workflow.

task.bash is a library of functions to make your configuration script easily able to run
commands idempotently. That means that your configuration script is capable of keeping your
existing environments in sync, as well as bringing new installations up to spec.

The model is to create a configuration script that contains the essential elements of your
configuration.  That script lives in a git repository cloned to each machine.  New machines
run the script by curl-piping it from GitHub (securely!).  As your desired config evolves,
the configuration script is the place you make changes.  Since it's "just Bash"(TM), it is
simple to make changes that, for example, integrate installation commands from a package's
website.  As you log into other machines, you pull your changes and run the script.  This
way, a single configuration is always actively maintained.  You are the synchronization
mechanism in tandem with git.

task.bash offers other useful features as well:

- command output suppression by default
- status reporting during the run
- summary statistics after the run
- supports user interaction, e.g. requesting password
- ad-hoc Bash commands and constructs

## Getting Started

**Requires Bash 5**

### Installation

Clone or copy `task.bash` where it can be sourced by your script.

Alternatively, vendor it into your configuration script by pasting it in place of the
`source` command.

### Overview

This is the surface area of the library:

Task definition keywords:

- `cmd` - the command to run to complete the task
- `desc DESCRIPTION`  - a descriptive task name
- `exist PATH` - task is satisfied if PATH exists
- `ok EXPRESSION` - task is satisfied if EXPRESSION evaluates true
- `prog ON|OFF` - show command output as progress
- `runas USER` - switch to USER and run the task
- `unchg TEXT` - look for TEXT in the command output to tell the task didn't change anything

Only one of `ok` or `exist` is required since `exist` calls `ok`.

Only `cmd` and `desc` are necessary to define a task.  The rest have sensible defaults.
By convention, `desc` is the first keyword to appear in a definition and by necessity, `cmd`
is the last, since it runs the task with the rest of the definition's settings.

Functions:

- `task.Summarize` - summarize the results of the run
- `task.SetShortRun ON|OFF` - skip tasks with progress or unchg defined if set to on

### Starting a Configuration Script

The basic outline of a configuration script has two parts: one for defining tasks and the
other for running them.

To start, create a script with some basics and placeholders.  We'll call it `update-env`:

```bash
#!/usr/bin/env bash

main() {
  # run tasks here
  task.Summarize
}

# define tasks here -- TBD

# boilerplate
source /path/to/task.bash
main
```

All we do here is source task.bash and run `main` and `task.Summarize`. `main` is your code
calling the tasks, and `task.Summarize` is a task.bash function that provides a summary of
the tasks that were run.

Putting our code in `main` allows us to move the boilerplate, such as sourcing task.bash,
out of the way to the bottom of the script.  That allows us to get to the meat of the script
quickly, and the boilerplate will get a bit more convoluted, so that's good.

All task.bash external function names are PascalCased and namespaced with the `task.`
prefix. Keyword functions for task definitions are the exception to that, which we will see
in a minute.

`chmod +x update-env` the file so we can run it in a bit.

### Defining Tasks

A task is a function that runs your command, with added features.  task.bash provides
several features, but not all of them apply to every task.  We'll look at a simple task
first and explain the rest later.

The actual form of a task is that of a Bash function.  By convention, function names for
custom tasks are suffixed with `Task`, e.g. `cloneDotFilesTask`.

Before we write a simple task, here's an outline of what it will look like:

```bash
tasknameTask() {
  desc  'description goes here'
  ok    'Bash code that returns true or false'
  cmd   'the Bash command to run'
}
```

This will run the specified command if the `ok` expression is false.  That is, if the task
isn't already satisfied, then task.bash runs the command to make it so.  Conversely if `ok`
is true, it means the task is already satisfied and does not need to be run.

In the output, the task will be displayed by its description.

We say this command is idempotent because it leaves the system configured properly whether
the system was configured already or not.

While the body of the function looks declarative, it actually runs the task.  `task.bash`
remembers your specifications from the other lines when it reaches the `cmd` line, that is,
when it comes time to run the command. So in the task body, the other lines don't have a
specific order, but `cmd` must come last.  There is also a convention to put `desc` first.

One of the first things you could do with a new machine would be to clone your dot files.
For example, you might run `git clone git@github.com/myuser/dotfiles`.

Cloning dotfiles is a network task that may take longer than expected.  We don't want to
bother with that if the repository is already cloned.  A simple heuristic for telling that
it has been cloned is whether the directory exists, since it will be created when cloned but
generally won't exist beforehand.  Our `ok` condition should be looking for that directory.

Here's the task definition for that:

```bash
cloneDotFilesTask() {
  desc  'clone dotfiles from github'
  ok    '[[ -e ~/dotfiles ]]'
  cmd   'git clone git@github.com:myuser/dotfiles ~/dotfiles'
}
```

Here, the `ok` condition is a Bash test that checks for the existence of `~/dotfiles`.  If
the directory doesn't exist, task.bash runs the clone command.  If it does exist, task.bash
knows the task is already satisfied and reports it that way.

On a side note, the existence test is so common that there is a special keyword for it:
`exist`.  We can substitute this for `ok` as: `exist ~/dotfiles`.  If you need a more
general expression than just an existence test, use `ok`.

``` bash
cloneDotFilesTask() {
  desc  'clone dotfiles from github'
  exist ~/dotfiles
  cmd   'git clone git@github.com:myuser/dotfiles ~/dotfiles'
}
```

The `cmd` line needs the quotes around the command definition. `cmd` takes a single
argument.  Since it is in quotes, the command may contain Bash constructs, like pipelines,
redirects or command lists.  task.bash makes them work, opening many useful doors.

Putting this in the script, we can run `cloneDotFilesTask` from `main`:

```bash
#!/usr/bin/env bash

main() {
  cloneDotFilesTask
  task.Summarize
}

# task definitions
cloneDotFilesTask() {
  desc  'clone dotfiles from github'
  exist ~/dotfiles
  cmd   'git clone git@github.com:myuser/dotfiles ~/dotfiles'
}

# boilerplate
source /path/to/task.bash
main
```

### Running Tasks

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
