# task.bash - the ultimate shell-based DSL for local configuration management

task.bash transforms bash into a Domain-Specific Language for configuration management of your local machine.  Taking inspiration from Ansible, task.bash lets you define and orchestrate complex system administration tasks for your local machine, and does it with style, power and flexibility.

## Features

Not only does task.bash provide these features, it makes using them *easy*:

- Superlative readability - for experienced bash devs, definitely, but for others too
- Idempotent task execution - define task satisfaction criteria so tasks only run when needed
- Task iterability - run the same task multiple times with different inputs
- Simple or complex commands - assign the task a full script as easily as a simple command
- Progress and change reporting - sensible ongoing task reporting and summarization
- Privilege escalation - run individual tasks as root or any other user (with permission)
- Comprehensive error handling - stops when an error is encountered and shows relevant output

## Tutorial

### Hello, World!

Let's look at the simplest task.bash script:

```bash
#!/usr/bin/env bash

source ./task.bash

task: 'say hello' echo "Hello, World!"

summarize
```

Taking each line in turn, the line `#!/usr/bin/env bash` tells us that this is a bash script, so everything in it will have to be valid bash.  task.bash doesn't change bash syntax at all, although you may learn a new trick or two when learning it.

Next comes the line that makes task.bash's functions available, `source ./task.bash`.  This presumes that you have task.bash in the directory you are running this script.  You could also paste the contents of task.bash into the script here, but don't do that quite yet.

Third, the task itself.  We'll break down the parts.  First is the odd-looking `task:`.  Is that a command?  Yes.  Is the colon part of the command name?  Yes.  Why?  task.bash scripts are meant to look like descriptions of tasks but to actually *be* running code.  We'll see more of how and why that works best in a bit.

Next comes the name of the task, which is `'say hello'`.  It needs to be a single argument, so the quotes are necessary.  I prefer single quotes where possible for safety, but quote style is a matter for each programmer.

Finally comes the command itself, but interestingly, as a set of arguments rather than a string in quotes.  When `task:` sees arguments after the task name, it makes those the definition of the task.  This example is a short but complete task definition.

When `task:` is called, it immediately executes the task.  So at this point in execution, we'd start seeing some output for the task:

```bash
[begin]         say hello
[changed]       say hello

[summary]
ok:      0
changed: 1
```

The first two lines are task output.   Each output from task.bash shows up in brackets, typically followed by the task name, `say hello` in our case.  We can see that the task began, and that it ended in the status `changed`.  `changed` generally means that the task did something to the system, but it is also the default status for when task.bash cannot tell what the effect on the system was supposed to be.  We'll come back to that in a second.

Notice that we did not see `Hello, World!`.  Like Ansible, task.bash assumes that things going ok are less interesting than things not going ok.  Had the task failed, we would see all of the command output as well.  For now, we don't need to see it.

Finally, the summary appears because we called `summarize`.  This is a necessity in every script if you want summary statistics, but isn't strictly required.  Here we see that one task ended in `changed` status and none in `ok` status.

`ok` tells us one of two things: either the task was already satisfied and so was not run, or the task ran and was completed without an error *and* the condition for satisfaction was also met when it was done.  This second alternative is how *[idempotent]* tasks operate, and idempotency is generally a good thing.  We'll come back to that as well.

[idempotent]: https://en.wikipedia.org/wiki/Idempotence#Computer_science_examples

### Task Failure

This task fails:

```bash
task: 'fail' false
```

Running it gives:

```bash
[begin]         fail
[failed]        fail
[output:]


[stopped due to failure]
```

The command gave no output, so none showed up when we try to show you what happened in this case.  Normally there would be useful information here.

Whenever task.bash encounters a failed task, it stops immediately.  It doesn't make assumptions about the independence of future tasks and so doesn't try to performs tasks whose prerequisites may not have been met.

### Iteration

Many tasks involve repetition.  task.bash makes it easy to iterate through a list of arguments.

Creating directories is a common task.  Let's make a set of them:

```bash
task: 'create directories' 'mkdir -p -m 700 $1' <<'END'
  ~/tmp
  ~/scratch
END
```