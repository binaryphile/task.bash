# task.bash -- Unified Mac and Linux System Configuration Scripting

A Bash library for automating system configuration for multiple machines in an idempotent
manner.  Manage all of your systems from a single script without duplication.  Inspired by
Ansible.

## Why use task.bash?

You work across multiple Unix-like machines -- Mac, Linux, Windows Subsystem for Linux,
Crostini on Chromebook...anything that runs Bash for a shell.

Each has its own quirks: BSD vs GNU, homebrew vs apt vs rpm, SSH configs, etc.  You've
created repositories for the important files -- notes, dot-files and editor configurations
-- but synchronizing git repos only goes so far.  Something has to grab those files then put
them where they need to be to function.

New machines are important as well.  A fresh installation of an operating system should be
most of the work to get you up and running, but there are miles of configuration to go.  A
tool to automate this portion of the setup with the details of your working environment is
necessary.

BUT, the rest of the setup is highly personal and custom.  It's your packages, your
projects, your directory structure, your druthers.  Such a tool could either recreate the
wheel to tell you how control all of those things, or could instead allow you to compose
your configuration in a robust and simple manner in a language you already know.  task.bash
chooses the latter.

Keeping working environments in sync shouldn’t be a manual process of fragile scripting.
**task.bash** helps you:

- **Automate system setup** -- Bring a new machine up to your configuration from scratch.

- **Create robust configuration** -- Create validation conditions for each task that ensure
    their intended effect.

- **Be performant** -- Skip tasks when they are already verifiably complete.

- **Maintain a single source of truth** -- Keep your environment configuration in one place,
    with minimal platform-specific branching.

- **Ensure idempotency** -- Run the same setup script repeatedly without unintended side
    effects.

- **Perform tasks for particular hosts and platforms** -- tasks are easily filtered to run
    on only the platform and/or hostname of your choice.  You can override the platform
    detection logic to provide recognition of arbitrary platforms.

- **Use the full power of the language** -- Bash is the *lingua franca* of system
    administration for Unix systems.  Use that to your advantage.  Easily adapt commands
    from website examples.  Do scripting stuff.  For example, after installing a package
    that your script will depend on further down, sometimes it is necessary to source an
    environment variable script before you can use it.  Other tools make this difficult or
    impossible.  With task.bash, just source it and move on.

## Getting Started

### Installation

``` bash
# Clone the repository
git clone https://github.com/yourusername/task.bash.git ~/task.bash
source ~/task.bash/task.bash
```

### Defining Tasks

Create a task. Let’s begin with one that clones a dotfiles repository from GitHub:

``` bash
task.git_clone_dotfiles() {
  task  'git clone dotfiles to ~/dotfiles'
  ok    '[[ -e ~/dotfiles ]]'
  def   'git clone https://github.com/myuser/dotfiles ~/dotfiles'
}
```

This task has three parts, designated by their keywords:

- **task** — The task description
- **ok** — An expression that indicates when the task is already satisfied
- **def** — The command itself, along with its arguments

### Running Tasks

By convention, task.bash runners (scripts) have two parts. One part defines tasks as
specially-named functions. The other part runs those functions much like a typical script.

Imagine that we’ve defined the following tasks:

- `task.apt_upgrade` — Upgrade any out-of-date packages, using apt
- `task.brew_upgrade` — Same for Homebrew
- `task.git_clone` — Clone a repository using Git
- `task.ln` — Create a symbolic link

### Script Part

The following runner ensures dotfiles are cloned, system packages are updated, and
environment-specific symlinks are created:

``` bash
#!/usr/bin/env bash

main() {
  section system        # Show the user a message with the name of this section
  system linux          # Run the tasks following this statement only on Linux systems
    task.apt_upgrade    # Run the upgrade task (indentation is purely for show)
  system macos          # Replace the Linux filter with macOS now
    task.brew_upgrade
  endsystem             # Stop filtering on system

  section dotfiles
  task.git_clone https://github.com/github_account/dotfiles ~/dotfiles

  section ssh
  task.ln ~/dotfiles/ssh/config ~/.ssh/config
}

source ./task.bash  # Make task.bash functions available
main                # Run the tasks
summarize           # Summarize what happened
```

### Task Definition Part

task.bash relies on function-based task definitions with a declarative structure:

``` bash
task.apt_upgrade() {
  task  'upgrade system packages'       # Show this description when reporting the task
  become root                           # Run the task as root
  unchg '0 upgraded, 0 newly installed' # Report the task as satisfied if we see this in the command output
  def   'apt update && apt upgrade -y'  # The command run by the task (this also invokes the task)
}
```

## Core Features

### Idempotency

Prevent unnecessary task execution by defining success conditions:

``` bash
task.mkdir_config
task  'make ~/projects directory'
ok    '[[ -d ~/projects ]]'
def   'mkdir -p ~/projects'
```

### Iteration

Apply a task across multiple inputs:

``` bash
task 'make directories'
def  'mkdir -p $1' <<'END'
  ~/projects
  ~/backups
END
```

### Conditional Execution

Run tasks based on host:

``` bash
host
  task "install brew"
  exist /usr/local/bin/brew
  def "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
endhost
```

Or system type:

``` bash
system macos
  task "install brew"
  exist /usr/local/bin/brew
  def "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
endsystem
```

### Privilege Escalation

Run tasks as another user:

``` bash
task  "update system"
become root
def   "apt update && apt upgrade -y"
```

## Summary

task.bash is a simple yet powerful tool for managing system configurations in a declarative,
Bash-native way. Whether you need to maintain consistency across multiple machines, automate
system setup, or manage dotfiles, task.bash provides a structured approach without
unnecessary complexity.
