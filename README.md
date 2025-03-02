# task.bash - Lightweight Configuration Management in Bash

As computing craftspeople, our working environment should be among our most prized
possessions.  We fawn over our systems, crafting aliases and installing tools in an endless
cycle.  We take steps to preserve our creations -- repositories for synchronizing dot files,
backups, etc. -- yet, when it comes time to set up a new system or use a new command-line
tool on another machine, there is still manual work involved.  If we are careful, we have
scripts or Makefiles to help out, but not a tool to walk us from system zero to
fully-configured in a short time, preferably without interaction.

Use task.bash to:

- manage disparate systems (Mac, Linux, other) with a single, maintainable script
- safely and easily propagate changes between systems
- make configuration changes in a documented manner, suitable for version control
- confine tasks to particular hostnames or system types, e.g. only try to upgrade homebrew on Mac
- configure a new system from scratch with a single, [curlpipe]-able command

task.bash runners are scripts that you write, employing task.bash. A runner runs locally on
your machine to perform configuration.  If your script is available online (securely!), you
can even curlpipe it to a new machine, making setup a breeze.

[curlpipe]: https://www.baeldung.com/linux/execute-bash-script-from-url

## Why Use task.bash?

Automating system configuration...I've tried it.  A bunch of ways -- shell scripts, Ansible,
Makefiles -- but the same problem crops up: scripts don’t stay updated. Each tweak to the
setup gets done manually first, instead of updating the automation.  Sometimes the
automation never happens because it's too difficult, or just difficult enough to take time.
Over time, once-polished scripts decay into museum pieces.

The problem isn’t the tools, it’s friction. Every change needs to be translated into a
tool-friendly format, which is enough hassle that it becomes second priority. The right tool
doesn't just need to be easy, it needs to be so easy that it is done first, rather than as
an afterthought.

Most tools fail here. Raw shell scripts lack structure. `make` and its copycats impose
significant constraints. Ansible and similar tools demand committing to their abstractions.

task.bash solves this by making it simple to translate command line actions into automation.
*I just want to paste an installation command from a web site into my configuration tool and
have it work.* task.bash is designed to get as close to that as possible.

## Getting Started

Begin by creating a runner script that imports task.bash:

```bash
#!/usr/bin/env bash

source ./task.bash
```

Create a task.  Let's begin with one that clones a dotfiles repository from github:

```bash
task.git_clone_dotfiles() {
  task  'git clone dotfiles to ~/dotfiles'
  ok    '[[ -e ~/dotfiles ]]'
  def   'git clone https://github.com/myuser/dotfiles ~/dotfiles'
}
```

This task has three parts, designated by their keywords:

- task -- the task description
- ok -- an expression that indicates when the task is already satisfied
- def -- the command itself, along with its arguments


By convention, task.bash runners (scripts) have two parts.  One part defines tasks as
specially-named functions.  The other part runs those functions a lot like your typical
script.

Imagine that we've defined the following tasks (note that dots are legal in Bash function
names):

- `task.apt_upgrade` -- upgrade any out-of-date packages, using apt
- `task.brew_upgrade` -- same for homebrew
- `task.git_clone` -- clone a repository using git
- `task.ln` -- create a symbolic link

### Script Part

The following runner ensures dotfiles are cloned, system packages are updated, and
environment-specific symlinks are created:

``` bash
#!/usr/bin/env bash

main() {
  section system        # show the user a message with the name of this section
  system linux          # run the tasks following this statement only on linux systems
    task.apt_upgrade    # run the upgrade task (indentation is purely for show)
  system macos          # replace the linux filter with macos now
    task.brew_upgrade
  endsystem             # stop filtering on system

  section dotfiles
  task.git_clone https://github.com/github_account/dotfiles ~/dotfiles

  section ssh
  task.ln ~/dotfiles/ssh/config ~/.ssh/config
}

source ./task.bash  # make task.bash functions available
main                # run the tasks
summarize           # summarize what happened
```

### Task Definition Part

task.bash relies on function-based task definitions with a declarative structure:

``` bash
task.apt_upgrade() {
  task  'upgrade system packages'       # show this description when reporting the task
  become root                           # run the task as root
  unchg '0 upgraded, 0 newly installed' # report the task as satisfied if we see this in the command output
  def   'apt update && apt upgrade -y'  # the command run by the task (this also invokes the task)
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

or system type:

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

## Getting Started

Clone task.bash and source it in your scripts:

``` bash
curl -fsSL https://raw.githubusercontent.com/binaryphile/task.bash/main/task.bash -o task.bash
source ./task.bash
```

Define your tasks and call `main` followed by `summarize` to execute.

## Summary

task.bash is a simple yet powerful tool for managing system configurations in a declarative,
Bash-native way. Whether you need to maintain consistency across multiple machines, automate
system setup, or manage dotfiles, task.bash provides a structured approach without
unnecessary complexity.
