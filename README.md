# task.bash - the ultimate shell-based DSL for local configuration management

task.bash transforms bash into a Domain-Specific Language for configuration
management of your local machine. Taking inspiration from Ansible, task.bash
lets you define and orchestrate complex system administration tasks for your
local machine, and does it with style, power and flexibility.

## Features

Not only does task.bash provide these features, it makes using them *easy*:

- Superlative readability - for experienced bash devs, definitely, but
  for others too
- Idempotent tasks - define task satisfaction criteria so tasks only run
  when needed
- Iterable tasks - run the same task multiple times with different
  inputs
- Script tasks - assign a full script as easily as a simple command
- Progress and change reporting - sensible ongoing task reporting and
  summarization
- Privilege escalation - run individual tasks as root or any other user
  (with permission)
- Error handling - stops when an error is encountered and shows relevant
  output

## Tutorial

### Hello, World!

Let’s look at the simplest task.bash script:

``` bash
#!/usr/bin/env bash

source ./task.bash

task: 'say hello' echo 'Hello, World!'

summarize
```

Taking each line in turn, the line `#!/usr/bin/env bash` tells us that this is a
bash script, so everything in it will have to be valid bash. task.bash doesn’t
change bash syntax at all, although you may learn a new trick or two when
learning it.

Next comes the line that makes task.bash’s functions available, `source ./task.bash`. This presumes that you have task.bash in the directory you are
running this script.

Third, the task itself. We’ll break down the parts. First is the odd-looking
`task:`.

Is that a command?  Yes.

Is the colon part of the command name? Yes.

Why?

task.bash scripts are meant to look like descriptions of tasks but to actually
*be* running code. We’ll see more of why that works best in a bit.

Next comes the name of the task, which is `'say hello'`. It needs to be a single
argument, so the quotes are necessary. I prefer single quotes where possible for
safety, but quote style is a matter for each programmer.

Finally comes the command itself, `echo 'Hello, World!'`, but interestingly, as
a set of arguments rather than a string in quotes. When `task:` sees arguments
after the task name, it makes those the definition of the task's command.

This example is a short but complete task definition.

When `task:` is called, it immediately executes the task. So at this point in
execution, we’d start seeing output that will end up like this:

``` bash
[begin]         say hello
[changed]       say hello

[summary]
ok:      0
changed: 1
```

The first two lines are task output. Each output from task.bash shows up in
brackets, typically followed by the task name, `say hello` in our case. We can
see the task's start with `begin`, and that it ended in the status `changed`. `changed`
generally means that the task did something to the system, but it is also the
default status for when task.bash cannot tell what the effect on the system was
supposed to be. We’ll come back to that in a second.

Notice that we did not see `Hello, World!`. Like Ansible, task.bash assumes that
things going well are less interesting than things not going well. Had the task
failed, we would see all of the command output as well.

Finally, the summary appears because we called `summarize`. This is a necessity
in every script if you want summary statistics, but isn’t strictly required.
Here we see that one task ended in `changed` status and none in `ok` status.

### Task Failure

This task fails:

``` bash
task: 'fail' false
```

Running it gives:

``` bash
[begin]         fail
[failed]        fail
[output:]


[stopped due to failure]
```

Whenever task.bash encounters a failed task, it stops. It doesn’t make
assumptions about the independence of future tasks and so doesn’t try to
performs tasks whose prerequisites may not have been met.

We always show the output of the failed task, but in this case, it had none.

### Iteration

Many tasks involve repetition. task.bash makes it easy to iterate through a list
of arguments.

Creating directories is a common task. Let’s make a set of them:

``` bash
task: 'create directories' 'mkdir -p -m 755 $1' <<'END'
  $HOME/tmp
  $HOME/scratch
END
```

Here we are making two temporary directories in our home directory. The form of
the task definition is the same as before with three differences:

- an argument list is supplied as a [here document], a string that can
  span multiple lines. Each line is given to the task in a separate
  invocation.
- the command definition contains a positional argument, `$1`. task.bash will
  substitute this token with the value of the current line of input from the heredoc.
- the command definition is in single quotes. This is necessary to
  keep the shell from evaluating `$1` immediately.

Here’s the output:

``` bash
[changed]       create directories - ~/tmp
[changed]       create directories - ~/scratch

[summary]
ok:      0
changed: 2
```

That looks good.

Notice that we’ve used the `-p` argument to `mkdir`, which skips making the
directory if the directory already exists. That makes the `mkdir` command
idempotent, so when the directory exists, it doesn’t fail and the end result is
the same as if it had run.

However, if you run this task again, task.bash will run `mkdir` even though the
directory exists. That’s because we haven’t told it when a task is already
satisfied. `-p` is a workaround for `mkdir` in this case, but even with that, we
will still be told that the task is `changed` when it wasn’t really.

task.bash can make any task idempotent if you tell it how to evaluate task
satisfaction.  With it, we don't have to use the `-p` workaround since task.bash won't run the command in the first place.  Let’s see how that works.

### Idempotence

A number of features such as idempotence require additional task configuration.
In that case, we don’t define the command in the `task:` line. Instead, we start
with the task name and provide details in additional lines. In these cases, the
command is defined with `def:`. For idempotence, we provide `ok:`, which takes an
expression that bash can evaluate as true or false. If the condition evaluates
true when the task is about to be run, the task is marked `ok` and not run.

``` bash
task: 'make a directory'
ok:   '[[ -e ~/tmp ]]'
def:  mkdir -m 755 ~/tmp
```

- there can only be one argument to `task:`, the task name
- `def:` takes over command definition, and runs the task as well.
- `ok:` specifies a valid bash expression that will be true when the
  task is satisfied

Because `def:` runs the task now, it is always the last line in the task definition.

`def:` allows the same command forms as `task:`.  In this case, that's the
command as multiple arguments without iteration.
  
The first time this is run, it will create the directory as expected.

``` bash
[begin]         make a directory
[changed]       make a directory

[summary]
ok:      0
changed: 1
```

The second time, with the directory already in existence, it will give this
output:

```bash
[ok]            make a directory

[summary]
ok:      1
changed: 0
```

Since the directory already existed, the expression was true and the command was not run.  The task is reported as `ok`.

Now we have a way to see when the commands are *actually* changing the system!

It's not always obvious what expression to use with `ok:`.  If the command has
an idempotent switch like `mkdir -p` and doesn't take long to run, it's usually
just as easy to not define `ok:`.   In this case, you can just remember that the
task will report `changed` even when it didn't really do anything and you can
simply go on with your life.

**But for long-running commands that do have a simple satisfaction criterion,
like directory existence, this feature is important**.  It's very useful to not
have to wait to download a package installer, for example, before knowing
whether you needed it or not.  `ok:` is the answer to that.

### Iteration with keyword variables - Key Tasks

Iteration is great, but sometimes the command requires multiple inputs.  For example, symlinking a file with `ln -s` requires a source location and a target path (or multiple target paths).

task.bash allows specifying multiple values per iteration line using keyword syntax.  It borrows bash's associative array syntax.  That is, a key is given in the form: `[key]=value`.  Values with spaces can be quoted: `[key]='a value'` or `[key]="value"`.

Use `keytask:` instead of task to begin the definition.  It's the same as `task:` other than letting us use keyword.  Here's a task to link multiple files:

```bash
keytask: 'link files'
ok:      '[[ -e $2 ]]'
def:     'ln -s $src $path' <<'END'
  [src]=/tmp     [path]=~/roottmp
  [src]=/var [path]=~/rootvar
END
```

Now, the task definition includes variables we haven't seen, `$src` and `$path`.  The task still iterates over each line, but task.bash creates the keys as variables with the values.  The output looks like this:

```bash
```

  [idempotent]: https://en.wikipedia.org/wiki/Idempotence#Computer_science_examples
  [here document]: https://en.wikipedia.org/wiki/Here_document
