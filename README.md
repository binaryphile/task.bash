# task.bash - the ultimate shell-based DSL for local configuration management

task.bash transforms bash into a Domain-Specific Language for
configuration management of your local machine. Taking inspiration from
Ansible, task.bash lets you define and orchestrate complex system
administration tasks for your local machine, and does it with style,
power and flexibility.

## Features

Not only does task.bash provide these features, it makes using them
*easy*:

- Superlative readability - for experienced bash devs, definitely, but
  for others too
- [Idempotent] tasks - define task satisfaction criteria so tasks only
  run when needed
- Iterable tasks - run the same task multiple times with different
  inputs
- Advanced Bash - supports Bash features like redirection and pipelines
- Scripting - manipulate state over multiple steps, such as changing
  directory or setting variables
- Privilege escalation - run tasks as another user via sudo
  authorization
- Progress and change reporting - sensible ongoing task reporting and summarization
- Error handling - stop when an error is encountered and show relevant
  output
- No jail, no abstraction - “It’s just Bash”(TM). It’s your world. Go
  nuts.

## Tutorial

### Hello, World!

Let’s look at the simplest task.bash script:

``` bash
#!/usr/bin/env bash

source ./task.bash

task: 'say hello' echo 'Hello, World!'

summarize
```

Taking each line in turn, the line `#!/usr/bin/env bash` tells us that
this is a bash script, so everything in it will have to be valid bash.
task.bash doesn’t change bash syntax at all, although you may learn a
new trick or two when learning it.

Next comes the line that makes task.bash’s functions available,
`source ./task.bash`. This presumes that you have task.bash in the
directory you are running this script.

Third, the task itself. We’ll break down the parts. First is the
odd-looking `task:`.

*Is that a command?* Yes.

*Is the colon really part of the command name?* Yes.

*Why?* task.bash scripts are meant to look like descriptions of tasks
but to actually *be* running code. As you see the finished product, we
hope you’ll come to appreciate its visual clarity.

Next comes the name of the task, which is `'say hello'`. It needs to be
a single argument, so the quotes are necessary. Our habit is to default
to single quotes for safety, but double quotes could have been used.

Finally comes the command itself, `echo 'Hello, World!'`, but
interestingly, as a set of arguments rather than an entire command in a
string. It works for simple commands, that is, an individual command
without redirection or other special Bash features. Simple commands make
it easier to read and work with the command.

When `task:` sees arguments after the task name, it makes those the
definition of the task’s command. Therefore this example is a short but
complete task definition.

When `task:` is called, it immediately executes the task. So at this
point in execution, we’d start seeing output that will end up like this:

``` bash
[begin]         say hello
[changed]       say hello

[summary]
ok:      0
changed: 1
```

The first two lines are task output. Each output from task.bash shows up
in brackets, followed by the task name, `say hello` in our case. We can
see when the task starts with `begin`, and how it end in the `changed`
status. `changed` generally means that the task did something to the
system, but it is also the default status for when task.bash cannot tell
what the effect on the system was supposed to be. We’ll cover that when
we talk about idempotence.

Notice that we did not see `Hello, World!`. Like Ansible, task.bash
assumes that things going well are less interesting than things not
going well, and suppresses the output of successful commands, unless you
ask for output with `prog:`.

Finally, the summary appears because we called `summarize`. This is a
manual step, needing you to explicitly call it, but if you’re not
interested in stats you don’t have to use it. Here we see that one task
ended in `changed` status and none in `ok` status.

### Task Failure

This task fails:

``` bash
task: 'this fails' false
```

Running it gives:

``` bash
[begin]         this fails
[failed]        this fails
[output]        this fails


[stopped due to failure]
```

Whenever task.bash encounters a failed task, it stops. It doesn’t make
assumptions about the independence of future tasks and so doesn’t try to
performs tasks whose prerequisites may not have been met.

task.bash shows the stdout and stderr output of the failed task (after
`[output]`), but in this case, the command had none.

### Iteration

Many tasks involve repetition. task.bash makes it easy to iterate
through a list of arguments.

Creating directories is a common task. Let’s make a set of them:

``` bash
task: 'create directories' 'mkdir -p -m 755 $1' <<'END'
  $HOME/tmp
  $HOME/scratch
END
```

Here we are making two temporary directories in our home directory. The
form of the task definition is the same as before with three
differences:

- an argument list is supplied as a [here document], a string that can
  span multiple lines. Each line is given to the task in a separate
  invocation.
- the command definition contains a positional argument, `$1`. task.bash
  will substitute this token with the value of the current line of input
  from the heredoc.
- the command definition is in single quotes. This is necessary to keep
  the shell from evaluating `$1` immediately.

Here’s the output (minus summary):

``` bash
[changed]       create directories - $HOME/tmp
[changed]       create directories - $HOME/scratch
```

That looks good.

Notice that we’ve used the `-p` argument to `mkdir`, which skips making
the directory if the directory already exists. That makes the `mkdir`
command idempotent, so when the directory exists, it doesn’t fail and
the end result is the same as if it had run.

However, if you run this task again, task.bash will run `mkdir` even
though the directory exists. That’s because we haven’t told it when a
task is already satisfied. `-p` is a workaround for `mkdir` in this
case, but even with that, we will still be told that the task is
`changed` when it wasn’t really.

task.bash can make any task idempotent if you tell it how to evaluate
task satisfaction. With it, we don’t have to use the `-p` workaround
since task.bash won’t run the command in the first place. Let’s see how
that works.

### Idempotence

A number of task.bash features, beginning here with idempotence, require
additional task configuration.

In that case, we don’t define the command in the `task:` line. Instead,
we call `task:` with just the task name and provide details in
additional lines. The command is defined instead with `def:`.

For idempotence, we provide `ok:`, which takes an expression that bash
can evaluate as true or false. If the condition evaluates true when the
task is about to be run, the task is marked `ok` and not run.

``` bash
task: 'make a directory'
ok:   '[[ -e $HOME/tmp ]]'
def:  mkdir -m 755 $HOME/tmp
```

- there can only be one argument to `task:`, the task name as a string
- `def:` takes over command definition, and runs the task as well
- `ok:` specifies a valid bash expression that will be true when the
  task is satisfied

Because `def:` runs the task now, it is always the last line in the task
definition.

The first time this is run, it will create the directory as expected.

``` bash
[begin]         make a directory
[changed]       make a directory
```

The second time, with the directory already in existence, it will give
this output:

``` bash
[ok]            make a directory
```

Since the directory already existed, the expression was true and the
command was not run. The task is reported as `ok`. We can see that the
command was not run because there is no `[begin]` message for it.

Now we have a way to see when the commands are *actually* changing the
system!

It’s not always obvious what expression to use with `ok:`. If the
command has an idempotent switch like `mkdir -p` and doesn’t take long
to run, it’s usually just as easy to skip idempotence and not define
`ok:`. In that case, you can just remember that the task will report
`changed` even when it didn’t really do anything and you can simply go
on with your life.

**But for long-running commands that do have a simple satisfaction
criterion, like directory existence, this feature is important**. It’s
very useful to not have to wait to download a package installer, for
example, before knowing whether you needed it or not. `ok:` is the
answer to that.

### Iteration with keyword variables

Iteration is great, but sometimes the command requires multiple inputs.
For example, symlinking a file with `ln -s` requires a source location
and a target path.

task.bash allows specifying multiple values per iteration line using
keyword syntax. It borrows bash’s associative array syntax. That is, a
key is given in the form: `[key]=value`. Values with spaces can be
quoted, i.e. `[key]='a value'` .

Here’s a task to link multiple files:

``` bash
task: 'link files' 'ln -sfT $src $path' <<'END'
  [src]=/tmp [path]=$HOME/roottmp
  [src]=/var [path]=$HOME/rootvar
END
```

**Note:** we intentionally use the environment variable `$HOME` rather
than using tilde (`~`) to expand to the home directory. With a keyword
arguments task.bash cannot expand tilde properly. You may consider
simply using `$HOME` throughout your scripts so as not to have to
remember when tilde shouldn’t be used.

The command definition includes variables we haven’t seen, `$src` and
`$path`. The task still iterates over each line, but task.bash uses them
to create the keys as variables with the corresponding values, so `$src`
and `$path` exist when the command is run. The output looks like this:

``` bash
[changed]       link files - [src]=/tmp [path]=$HOME/roottmp
[changed]       link files - [src]=/var [path]=$HOME/rootvar
```

Notice also that even though we ran the commands, we don’t see the usual
`[begin]` on these iterated tasks. Iterated tasks can be verbose, so the
`[begin]` message is suppressed when iterating. If you need to see when
a task is beginning, make a singular task for it rather than including
it in an iterated task.

### Idempotent Iteration

When you use iteration and idempotency together, usually the `ok:`
condition depends on the iteration input. Never fear, task.bash has you
covered there as well. Here are idempotent versions of the last two
iteration examples:

``` bash
task: 'create directories'
ok:   '[[ -e $1 ]]'
def:   'mkdir -m 755 $1' <<'END'
  $HOME/tmp
  $HOME/scratch
END

task: 'link files'
ok:      '[[ -e $path ]]'
def:     'ln -s $src $path' <<'END'
  [src]=/tmp [path]=$HOME/roottmp
  [src]=/var [path]=$HOME/rootvar
END
```

task.bash makes sure that the iteration variables are available to the
`ok:` expression. For singular tasks, each input line is available as
`$1`. For keyword arguments, the key variables of each line are
available by name.

### Advanced Bash - raw commands

When we were looking at iteration, we put the task’s command definition
in a string to protect `$1` from being expanded prematurely. If `def:`
(and by extension, `task:`) receive a single argument like that for the
command specification, they treat it as raw bash. That means you can
include characters that you wouldn’t be able to otherwise, so long as it
is in a string.

This is useful with pipes and redirection. Here we download an installer
script with `curl`:

``` bash
task: 'download lix installer' 'curl -fsSL https://install.lix.systems/lix >install_lix'
```

Semicolon and double-ampersand are other such special characters,
meaning you can do scripting in a string:

``` bash
task: 'download and install lix' 'curl -fsSL https://install.lix.systems/lix >install_lix && chmod 700 install_lix && ./install_lix --no-confirm'
```

These can get verbose quickly, so task.bash has better options for
longer commands. We’ll discuss them when talking about task lists and
scripting.

### Showing progress

Some commands can take a lot of time and give the impression that the
script may have hung. Running an installer as we just showed is a good
example. For these cases, it’s better to have ongoing confirmation that
things are still happening, in which case you can direct the task to
show progress with `prog: on`:

``` bash
task:  'install lix'
ok:    '[[ -e /nix/var/nix/profiles/default/bin ]]'
prog:  on
def:   ./install_lix --no-confirm
```

`prog: on` works best with idempotent tasks (i.e. using `ok:`) so you
don’t have to see progress when the task doesn’t need to run.

### Privilege escalation

This familiar-looking task runs as root:

``` bash
task:   'upgrade system'
become: root
def:    apt upgrade -y
```

`become:` enables sudo for the task. Usually you will supply the user
`root`, but any other user for whom you have authorization will work.

### Examining command output for ok status

Some commands are not easily made idempotent (no simple `ok:`
condition), such as `apt upgrade`. With commands like that, you
generally either have to dig deep in documentation for a good `ok:`
condition or, more likely, run the command and see whether it makes any
changes. apt tells you whether it changed the system after it runs. If
it ran and didn’t install anything (thankfully, this doesn’t take long),
we’d like the task output to say `[ok]`, not `[changed]`.

Use `unchg:` to specify some output text indicating no change was made:

``` bash
task:    'upgrade system'
become:  root
unchg:   '0 upgraded, 0 newly installed'
def:     apt upgrade -y
```

### Task lists

When you have tasks that share the same task settings and purpose, task
lists can be useful.

Here we update the last example to run two subtasks:

``` bash
task:   'apt'
become: root
def:    <<'END'
  apt update
  apt upgrade -y
END
```

If `def:` receives no arguments, it takes input lines as subtasks.
Subtasks are executed separately and have their own reporting, so they
are run independently. Task lists are not scripts and don’t maintain
state (like working directory or variables) from line to line.

They are useful when you want to share settings between related tasks.
The task report shows the overall task name appended with the individual
command for each task.

``` bash
[changed]       apt - apt update
[changed]       apt - apt upgrade -y
```

### Scripting

Task lists and raw bash commands have their place, but sometimes you
need the full power of scripting. In particular, if you need to change
directories or make conditional logic with variables, you have to
maintain state from line to line. Commands in strings are also opaque to
the editor, whereas working with actual scripts allows syntax
highlighting.

For example, I clone my dotfiles from github during system
configuration. However, I do this before I’ve been able to set up SSH
credentials, since that’s an interactive process. I can still clone a
public repository without credentials, but I also change the origin
remote’s URL so it will take advantage of SSH credentials as soon as I
use git. In order to do this, I change directory to the working copy and
issue a `git remote` command:

``` bash
task:  'clone dotfiles'
ok:    '[[ -e $HOME/dotfiles ]]'
def:() {
  git clone https://github.com/binaryphile/dotfiles $HOME/dotfiles
  cd $HOME/dotfiles
  git remote set-url origin git@github.com:binaryphile/dotfiles
}
run
```

What is that? That’s a function definition for `def:`. Yes, we are
replacing the `def:` command, but only temporarily, it resets to its
original implementation when this task is done.

This is a standard function with all the scripting functionality of
Bash, and it will be run as the task. Since the original `def:` was
responsible for running the task and we are no longer calling it, we now
have to do that ourselves by calling `run` after the task definition.

You may also use looping input with a script. To do that, call `loop`
instead of `run` and give it a heredoc with inputs. The input lines will
show up to the script as `$1`.

## A working example

We’ve seen most of the features of task.bash, now you’re ready for a
simple real-world configuration:

``` bash
#!/usr/bin/env bash

# main lets us move the boilerplate to the bottom, like sourcing task.bash.
# It also helps with debugging, see the end of the script.
main() {
  # a simple command definition
  task: 'create ssh directory' mkdir -p -m 700 $HOME/.ssh

  # A scalar (not keyword) looping task.
  # Note that the heredoc terminator, "END" in this case, can be quoted
  # with spaces in front to allow matching indentation at the end.
  task: 'create required directories' 'mkdir -p -m 755 $HOME/$1' <<'  END'
    .config/nixpkgs
    .config/ranger
  END

  # We use a task list for related tasks here.
  # `become: root` gives privilege escalation to root.
  # `prog: on` makes apt show output.
  task:   'apt'
  become: root
  prog:   on
  def:    <<'  END'
    apt update -qq
    apt upgrade -y
  END

  # this is a script, which needs to have `run` called at the end
  # `ok:` makes it idempotent, so it is not run when ~/dotfiles exists.
  task: 'clone dotfiles'
  ok:   '[[ -e $HOME/dotfiles ]]'
  def:() {
    git clone https://github.com/binaryphile/dotfiles $HOME/dotfiles
    cd $HOME/dotfiles
    git remote set-url origin git@github.com:binaryphile/dotfiles
  }
  run

  # a keyword looping task
  task: 'create dotfile symlinks' 'ln -sf $HOME/dotfiles/$src $HOME/$path' <<'  END'
    [src]=gitconfig                    [path]=.gitconfig
    [src]=ssh/config                   [path]=.ssh/config
    [src]=ranger/rc.conf               [path]=.config/ranger/rc.conf
  END
}

# boilerplate

source ./task.bash
main
summarize
```

## A curl-pipe-friendly script template with tracing and repl

Here’s a template that allows you to curl-pipe the script from github to
run it:

``` bash
#!/usr/bin/env bash

main() {
  # task definitions go here
}

# source task.bash, or download it
if [[ -e task.bash ]]; then
  source ./task.bash
else
  lib=$(curl -fsSL https://raw.githubusercontent.com/username/reponame/branchname/task.bash) || exit
  eval "$lib"
  unset -v lib
fi

# stop here if sourcing for repl access
return 2>/dev/null
set -e # otherwise turn on exit on error

# enable tracing if given a -x argument
[[ ${1:-} == -x ]] && { shift; set -x; }

main
summarize
```

To run it with curl:

``` bash
curl -fsSL https://raw.githubusercontent.com/username/reponame/branchname/runner | bash
```

If instead you download the runner and invoke it with `-x`, you’ll see
execution with bash tracing turned on, for debugging purposes.

Also, you can get an interactive repl (i.e. the usual bash terminal with
the library loaded) to play with or debug tasks. It is recommended to do
this by starting a new bash session with `bash --norc` first.

``` bash
$ source runner
$ main # runs the main tasks but now without "exit on error"
```

You can define a task in a function other than `main` if you want to run
it by itself in repl mode. \## Other considerations

### Strict mode and quoting

You may be familiar with the Bash community’s mantra, “quote everything
for safety” and maybe even rolling some eyeballs at the naivete of not
quoting anything, like I haven’t been doing in commands. That’s how you
get word-splitting issues with spaces. Do you want word-splitting issues
with spaces?

Of course not. That’s why we turn off word-splitting. What exactly is
word-splitting? It’s the part of command execution where bash examines
expanded variables, looking for the characters in IFS and separating the
string into separate words when it finds one. For example, if you call
`cd $HOME` and your home directory path has a space like
`/home dirs/user`, then without quoting `"$HOME"`, the variable will be
split on space and you will run `cd /home dirs/user` (no quotes), which
is really just `cd /home`.

The other troublesome feature that encourages excess quoting is file
globbing. Any variable expansion gets checked for glob characters such
as `*`, in which case they are automatically substituted with the result
of the local directory, for example. This is usually bad for our
purposes.

task.bash requires a form of [unofficial strict mode], and sets it for
you. Our strict mode:

- disables splitting on spaces and tabs, keeping it only for newlines
  (`IFS=$'\n'`)
- disables file globbing (`set -f`)
- forces the script to stop whenever an error is encountered (`set -e`)
- disallows references to unset variables (`set -u`)

Within your task runner, you will be held to strict mode with your code.
This is usually the right thing. Failing tasks should stop execution.
Unset variable errors usually mean typos in variable names. Specifying
bash commands as strings is already fraught with quotation and requiring
more quotes significantly impairs readability. You may get a curveball
or two from strict mode, but the alternative is worse.

In general, you are free of quoting variable expansions however, and
that is worth it.

Occasionally, you will want to source a third-party script, such as when
you need some environment variable initialization for a package. These
aren’t made for strict mode and won’t work with it, but you still need
them. For such occasions, `strict on|off` is a command to disable or
enable strict mode, letting the third-party code run:

``` bash
strict off  # next task re-enables strict
source $HOME/.nix-profile/etc/profile.d/hm-session-vars.sh # required env vars
```

You can use this in command definitions or in-between task definitions.
When a new task is defined, it re-enables strict mode automatically.

### Structuring your task code

While we have already seen a good way of organizing your code by
starting with a `main` function, as scripts become more complex, they
can get to the point where a layer of hierarchy aids organization.

Starting with `main` is a good first step. Since this is just Bash code,
`main` can call other functions. A next step is to separate related
tasks into their own functions and call those from `main`. Name the
function for the common thread in the tasks, such as `system` for
updating apt and sundry.

task.bash provides friendly output with the `section` command, which
separates output with a section heading before calling the named
function:

    main() {
      section system
      section vim
    }

    system() {
      # some system tasks
    }

    vim() {
      # some vim tasks
    }

Output:

``` bash
[section system]
<system task output shows here>

[section vim]
<vim task output shows here>
```

  [Idempotent]: https://www.bmc.com/blogs/idempotence/
  [here document]: https://www.gnu.org/software/bash/manual/bash.html#Here-Documents
  [unofficial strict mode]: http://redsymbol.net/articles/unofficial-bash-strict-mode/
