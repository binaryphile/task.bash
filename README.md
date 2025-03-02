# task.bash -- one script to configure your work environment anywhere Bash is available

Requires Bash 
task.bash assists you in creating your work environment on any of your machines with a
single Bash script.

concerns:

- configure MacOS as well as Linux
- do anything cli can do:
  - update system packages
  - install and update new packages
  - clone repositories
  - create symlinks

- prioritize maintainence
  - odds are, if there's an example on the internet of what you want, it's already in bash
  - boil down task creation to its essence
  - consolidate setup and update into one process through idempotence (while preserving
    performance)
  - make it the tool you use every day, for every change

## Why use task.bash?

You work on more than one machine and need a uniform work environment.  Bash is available
everywhere you need it.

You tried shell scripts, but they aren't idempotent.  They were ok to set up an environment,
but not to maintain it.

You tried Make/Rakefiles but they were difficult to maintain and the scripts moldered. When
you needed them, they were out of date and not very useful.  They didn't provide support
tailored for working across platforms, either.

Ansible looked great, but it made you throw out everything you know for an entirely new
abstraction.  What started out declarative ended up looking like a procedural language in a
trench coat.  Playbooks were painful to factor and maintain.

Why is it so hard?  Each system has its own quirks: BSD vs GNU, homebrew vs apt vs rpm, SSH
configs, etc.  Many tasks rely on commands that have different designations for the same
option.  Something needs to select the right version of command line incantation

Your files are important -- dot-files, editor configurations and such.  But git repos are
pose their own challenge.  Something has to grab those files and put them where they need to
be.

New machines are important as well.  Installing the OS is the easy part.  Installing and
configuring your work environment is the hard part.  Something needs to be able to apply a
full configuration to a new machine while also keeping a maintained system up-to-date.

Keeping working environments in sync shouldn’t be a the product of fragile, unmaintained
scripting. **task.bash** helps you:

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
