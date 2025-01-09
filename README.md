## task.bash - the ultimate shell-based DSL for local configuration management

task.bash transforms bash into a Domain-Specific Language for configuration management of your local machine.  Taking inspiration from Ansible, task.bash lets you define and orchestrate complex system administration tasks for your local machine, and does it with style, power and flexibility.

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

Finally comes the command itself, but interestingly, as a set of arguments rather than a string in quotes.  When `task:` sees arguments after the task name, it makes those the definition of the task.  This is a short, but complete task definition.

When the task is defined, it is immediately run.  So at this point, we'd start seeing some output for the task.  Since there are no further tasks, the final command in the script is `summarize`.  That function prints out the final summary of the run.  Our complete output looks like this:

