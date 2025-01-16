# task.bash - the ultimate shell-based DSL for local configuration management

task.bash transforms bash into a Domain-Specific Language for configuration management of
your local machine. Taking inspiration from Ansible, task.bash lets you define and
orchestrate complex system administration tasks for your local machine, and does it with
style, power and flexibility.

Use it to:

- easily define [idempotent](https://www.bmc.com/blogs/idempotence/) tasks from basic Bash
- upgrade system packages to latest
- install required software
- set up software configurations, dot files and plugins
- bootstrap an environment that runs further automation like Ansible
- manage multiple machines and platforms (e.g. MacOS and flavors of Linux)

## Features

Not only does task.bash provide these features, it makes using them *easy*:

- Superlative readability - for experienced bash devs, definitely, but for others too
- Idempotent tasks - define task satisfaction criteria so tasks only run when needed
- Iterable tasks - run the same task multiple times with different inputs
- Advanced Bash - supports Bash features like redirection and pipelines
- Scripting - manipulate state over multiple steps, such as changing directory or setting
  variables
- Privilege escalation - run tasks as another user via sudo authorization
- Progress and change reporting - sensible ongoing task reporting and summarization
- Error handling - stop when an error is encountered and show relevant output
- No jail, no abstraction - “It’s just Bash”(TM). It’s your world. Go nuts.

## Tutorial

task.bash employs a hybrid declarative/imperative model.  The recommended usage is to
separate your runner script into two sections.  The first section is the imperative script
itself, which runs the tasks in order.  The second section is the declarative task
definitions, which informs task.bash on how to run each task

### Hello, World!

Let’s look at a simple example of a runner script:

``` bash
#!/usr/bin/env bash

main() {
  # run the defined tasks
  task.echo_Hello_World
}

# define the tasks

task.echo_Hello_World() {
  task 'say hello'
  def  'echo "Hello, World!"'
}

source ./task.bash

main
summarize
```

Taking each line in turn, the line `#!/usr/bin/env bash` tells us that this is a bash
script, so everything in it will have to be valid bash.

Next comes the line that makes task.bash’s functions available, `source ./task.bash`. This
requires task.bash to reside in script's directory.

Third is the definition of a `main` function.  `main` runs the tasks.  By defining `main`,
we can move the rest of the boilerplate later in the script, keeping the focus what the
script is doing to the system.  Our `main` here simply runs our Hello World task.

By convention, functions that are task definitions have names prefixed with `task.` to
distinguish them from regular commands.  You can mix tasks and arbitrary code in main, so
being able to easily identify tasks versus garden-variety commands is useful.

Also notice that in this case, our task function is named for the command it is running,
including the argument, but simplified.  `_` is used for space, leading to a function name
that closely resembles having written the actual command.  For simple tasks, this provides
a semblance of what you would write if they were commands, not tasks, which makes
a familiar-looking script.

Next, the task itself. We’ll break down the parts. First is `task`. `task` is a command
that sets the description message you’ll see when it runs. The description needs to be a
single argument, so the quotes are necessary. Our habit is to default to single quotes for
safety, but double quotes could have been used.

On the next line is `def`, the command definition, `echo 'Hello, World!'`. This must also be
a single argument, i.e. quoted.

The task is executed with `def` is executed, which is when the task function is called. So
at this point in `main`, we’d start seeing output that will end up like this:

``` bash
[begin]         say hello
[changed]       say hello

[summary]
ok:      0
changed: 1
```

The first two lines are task output. Each output from task.bash shows up in brackets,
followed by the task name, `say hello` in our case. We can see when the task starts with
`begin`, and how it end in the `changed` status. `changed` generally means that the task did
something to the system, but it is also the default status for when task.bash cannot tell
what the effect on the system was supposed to be. We’ll cover that when we talk about
idempotence.

Notice that we did not see `Hello, World!`. Like Ansible, task.bash assumes that things
going well are less interesting than things not going well, and suppresses the output of
successful commands, unless you ask for output with `prog`.

Finally, the summary appears because we called `summarize`. This is a manual step, needing
you to explicitly call it, but if you’re not interested in stats you don’t have to use it.
Here we see that one task ended in `changed` status and none in `ok` status.

### Task Failure

This task fails:

``` bash
task 'this fails'
def  'false'
```

Running it gives:

``` bash
[begin]         this fails
[failed]        this fails
[output]        this fails


[stopped due to failure]
```

Whenever task.bash encounters a failed task, it stops. It doesn’t make assumptions about the
independence of future tasks and so doesn’t try to performs tasks whose prerequisites may
not have been met.

task.bash shows the stdout and stderr output of the failed task (after `[output]`), but in
this case, the command had none.

### Iteration

Many tasks involve repetition. task.bash makes it easy to iterate through a list of
arguments.

Creating directories is a common task. Let’s make a set of them:

``` bash
task 'create directories'
def  'mkdir -p $1' <<'END'
  ~/tmp
  ~/scratch
END
```

Here we are making two temporary directories in our home directory. The form of the task
definition is the same as before with some differences:

- an argument list is supplied as a [here
  document](https://www.gnu.org/software/bash/manual/bash.html#Here-Documents), a string
  that can span multiple lines. Each line is given to the task in a separate invocation.
- the command definition contains a positional argument, `$1`. task.bash will substitute
  this token with the value of the current line of input from the heredoc. the shell from
  evaluating `$1` immediately.

Here’s the output (minus summary):

``` bash
[changed]       create directories - ~/tmp
[changed]       create directories - ~/scratch
```

That looks good.

Notice that we’ve used the `-p` argument to `mkdir`, which skips making the directory if the
directory already exists. That makes the `mkdir` command idempotent, so when the directory
exists, it doesn’t fail and the end result is the same as if it had run.

However, if you run this task again, task.bash will run `mkdir` even though the directory
exists. That’s because we haven’t told it when a task is already satisfied. `-p` is a
workaround for `mkdir` in this case, but even with that, we will still be told that the task
is `changed` when it wasn’t really.

task.bash can make any task idempotent if you tell it how to evaluate task satisfaction.
With it, we don’t have to use the `-p` workaround since task.bash won’t run the command in
the first place. Let’s see how that works.

### Idempotence

A number of task.bash features, beginning here with idempotence, require additional task
configuration.

In that case, we don’t define the command in the `task` line. Instead, we call `task` with
just the task name and provide details in additional lines. The command is defined instead
with `def`.

For idempotence, we provide `ok`, which takes an expression that bash can evaluate as true
or false. If the condition evaluates true when the task is about to be run, the task is
marked `ok` and not run.

``` bash
task 'make a directory'
ok   '[[ -e ~/tmp ]]'
def  'mkdir ~/tmp'
```

- there can only be one argument to `task`, the task name as a string
- `def` takes over command definition, and runs the task as well
- `ok` specifies a valid bash expression that will be true when the task is satisfied

Because `def` runs the task now, it is always the last line in the task definition.

The first time this is run, it will create the directory as expected.

``` bash
[begin]         make a directory
[changed]       make a directory
```

The second time, with the directory already in existence, it will give this output:

``` bash
[ok]            make a directory
```

Since the directory already existed, the expression was true and the command was not run.
The task is reported as `ok`. We can see that the command was not run because there is no
`[begin]` message for it.

Now we have a way to see when the commands are *actually* changing the system!

It’s not always obvious what expression to use with `ok`. If the command has an idempotent
switch like `mkdir -p` and doesn’t take long to run, it’s usually just as easy to skip
idempotence and not define `ok`. In that case, you can just remember that the task will
report `changed` even when it didn’t really do anything and you can simply go on with your
life.

**But for long-running commands that do have a simple satisfaction criterion, like directory
existence, this feature is important**. It’s very useful to not have to wait to download a
package installer, for example, before knowing whether you needed it or not. `ok` is the
answer to that.

## Exist

In practice, many if not most system tasks create a new file or directory that can be used
to tell if the command has been run.  Since this is such a common case, there is a shortcut
for `ok` that tests for file/directory existence, called `exist`.

We can redefine our last task using `exist`:

```bash
task    'make a directory'
exist   ~/tmp
def     'mkdir ~/tmp'
```

`exist` simply calls `ok` after putting the argument into a bash `[[ -e ]]` test.

Don't forget that you have the full power of an expression with `ok` if you need it.

### Idempotent Iteration

When you use iteration and idempotency together, usually the `ok` condition depends on the
iteration input. Never fear, task.bash has you covered there as well. Here is the idempotent
version of the last iteration example:

``` bash
task    'create directories'
exist   '$1'
def     'mkdir -m 755 $1' <<'END'
  $HOME/tmp
  $HOME/scratch
END
```

task.bash makes sure that the input line is available to the `ok` expression as `$1` (remember
`exist` is the `ok` expression).

### Advanced Bash

Features like with pipes and redirection work in command definitions. Here we download an
installer script with `curl`:

``` bash
task  'download lix installer'
def   'curl -fsSL https://install.lix.systems/lix >lix_installer'
```

Semicolon is another such special character, meaning you can do simple scripting (we don’t
need `&&` because task.bash always employs exit on error, see strict mode below):

``` bash
task  'download and install lix'
def    'curl -fsSL https://install.lix.systems/lix >lix_installer; chmod +x lix_installer; ./lix_installer install --no-confirm'
```

These can get verbose quickly, so task.bash has full scripting for longer commands,
discussed below.

### Showing progress

Some commands can take a lot of time and give the impression that the script may have hung.
Running an installer as we just showed is a good example. For these cases, it’s better to
have ongoing confirmation that things are still happening, in which case you can direct the
task to show progress with `prog on`, which allows command output to the terminal:

``` bash
task  'install lix'
exist /nix/var/nix/profiles/default/bin
prog  on
def   './lix_installer install --no-confirm'
```

`prog on` works best with idempotent tasks (i.e. using `ok`) so you don’t have to see
progress when the task doesn’t need to run.

### Privilege escalation

This familiar-looking task runs as root:

``` bash
task   'upgrade system'
become root
def    'apt upgrade -y'
```

`become` enables sudo for the task. Usually you will supply the user `root`, but any other
user for whom you have authorization will work.

### Examining command output for ok status

Some commands are not easily made idempotent (no simple `ok` condition), such as
`apt upgrade`. With commands like that, you generally either have to dig deep in
documentation for a good `ok` condition or, more likely, run the command and see whether it
makes any changes. apt tells you whether it changed the system after it runs. If it ran and
didn’t install anything (thankfully, this doesn’t take long), we’d like the task output to
say `[ok]`, not `[changed]`.

Use `unchg` to specify some output text indicating no change was made:

``` bash
task    'upgrade system'
become  root
unchg   '0 upgraded, 0 newly installed'
def     'apt upgrade -y'
```

### Scripting

Task lists and raw bash commands have their place, but sometimes you need the full power of
scripting. In particular, if you need to change directories or make conditional logic with
variables, you have to maintain state from line to line. Commands in strings are also opaque
to the editor, whereas working with actual scripts allows syntax highlighting.

For example, I clone my dotfiles from github during system configuration. However, I do this
before I’ve been able to set up SSH credentials, since that’s an interactive process. I can
still clone a public repository without credentials, but I also change the origin remote’s
URL so it will take advantage of SSH credentials as soon as I use git. In order to do this,
I change directory to the working copy and issue a `git remote` command:

``` bash
task  'clone dotfiles'
exist $HOME/dotfiles
def() {
  git clone https://github.com/binaryphile/dotfiles $HOME/dotfiles
  cd $HOME/dotfiles
  git remote set-url origin git@github.com:binaryphile/dotfiles
}
run
```

What is that? That’s a function definition for `def`. Yes, we are replacing the `def`
command, but only temporarily, it resets to its original implementation when this task is
done.

This is a standard function with all the scripting functionality of Bash, and it will be run
as the task. Since the original `def` was responsible for running the task and we are no
longer calling it, we now have to do that ourselves by calling `run` after the task
definition.

You may also use looping input with a script. To do that, call `loop` instead of `run` and
give it a heredoc with inputs. The input lines will show up to the script as `$1`.

## A curl-pipe-friendly runner script template with tracing and repl

Here’s a template that allows you to curl-pipe from github to run it:

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

If instead you download the runner and invoke it with `-x`, you’ll see execution with bash
tracing turned on, for debugging purposes.

Also, you can get an interactive repl (i.e. the usual bash terminal with task.bash and your
runner functions loaded) to play with or debug tasks. It is recommended to do this by
starting a new bash session with `bash --norc` first.

``` bash
$ source runner
$ task.mine     # runs just this task which you defined
```

You can define a task in a function other than `main` if you want to run it by itself in
repl mode.

## Other considerations

### Strict mode and quoting

You may be familiar with the Bash community’s mantra, “quote everything for safety” and
maybe even rolling some eyeballs at the naivete of not quoting anything, like I haven’t been
doing in commands. That’s how you get word-splitting issues with spaces. Do you want
word-splitting issues with spaces?

Of course not. That’s why we turn off word-splitting on spaces and tabs. What exactly is
word-splitting? It’s the part of command execution where bash examines expanded variables,
looking for the characters in IFS and separating the string into separate words when it
finds one. For example, if you call `cd $HOME` and your home directory path has a space like
`/home dirs/user`, then without quoting `"$HOME"`, the variable will be split on space and
you will run `cd /home dirs/user` (no quotes), which is really just `cd /home`.

The other troublesome feature that encourages excess quoting is file globbing. Any variable
expansion gets checked for glob characters such as `*`, in which case they are automatically
substituted with the result of the local directory, for example. This is usually bad for our
purposes.

task.bash requires a form of [unofficial strict
mode](http://redsymbol.net/articles/unofficial-bash-strict-mode/), and sets it for you. Our
strict mode:

- disables splitting on spaces and tabs, keeping it only for newlines (`IFS=$'\n'`)
- disables file globbing (`set -f`)
- forces the script to stop whenever an error is encountered (`set -e`)
- disallows references to unset variables (`set -u`)

Within your runner script, your code will be held to strict mode. This is usually the
right thing. Failing tasks should stop execution. Unset variable errors usually mean typos
in variable names. Specifying bash commands as strings is already fraught with quotation and
requiring more quotes significantly impairs readability. You may get a curveball or two from
strict mode, but the alternative is worse.

In general, you are free of quoting variable expansions however, and that is worth it.

Occasionally, you will want to source a third-party script, such as when you need some
environment variable initialization for a package. These aren’t made for strict mode and
won’t work with it, but you still need them. For such occasions, `strict on|off` is a
command to disable or enable strict mode, letting the third-party code run:

``` bash
strict off  # next task re-enables strict
source $HOME/.nix-profile/etc/profile.d/hm-session-vars.sh # required env vars
strict on   # be a good citizen
```

You can use this in a `def` command definition or in-between task definitions. When a new
task is begun with `task`, `task` re-enables strict mode automatically.

### Pre-defined tasks

task.bash offers a handful of pre-defined tasks.  Each is an idempotent version of a regular
command:

- `task.ln` - symlink with `ln -sf`.  Replaces an existing target file/link.
- `task.curl` - download a file with for `curl -fsSL`
- `task.git_clone` - clone a repository with `git clone`

See `task.bash` for documentation.  In general, these are non-interactive versions of the
commands.

### Providing organization with section

task.bash provides friendly output with the `section` command, which separates output with a
section heading before calling the named function. This is good for breaking main into
related parts.

Here we have used section commands, along with moving task definitions into their own
functions. As a convention, we preface the function names with `task.` to denote they are
not just any kind of function:

    main() {
      section system
      task.apt_upgrade

      section neovim
      task.curlpipe_vim-plug
    }

    task.apt_upgrade() {
      task 'apt upgrade'
      prog on
      def  'apt upgrade -y'
    }

    task.curlpipe_vim-plug() {
      task  'install junegunn/vim-plug'
      exist ~/.local/share/nvim/site/autoload/plug.vim
      def   'curl -fsSL https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim >~/.local/share/nvim/site/autoload/plug.vim'
    }

Output:

``` bash
[section system]
<system task output shows here>

[section vim]
<vim task output shows here>
```
