IFS=$'\n' # disable word splitting for most whitespace - this is required
set -uf   # error on unset variable references and turn off globbing - globbing off is required

# become tells the task to run under sudo as user $1
become() { BecomeUser=$1; }

# Def is the default implementation of def. The user calls the default implementation
# when they define the task using def. The default implementation accepts a task as
# arguments and redefines def to run that command, running it indirectly by then calling
# run, or loop if there is a variable argument in the task.
Def() {
  eval "def() { $1; }"
  [[ $1 == *'$1'* ]] && loop || run
}

# exist is a shortcut for ok that tests for existence.
exist() { ok "[[ -e $1 ]]"; }

# InitTaskEnv initializes all relevant settings for a new task.
InitTaskEnv() {
  # reset strict, shared variables and the def function
  strict on

  BecomeUser=''             # the user to sudo with
  Condition=''              # an expression to tell when the task is already satisfied
  Output=''                 # output from the task, including stderr
  ShowProgress=0            # flag for showing output as the task runs
  UnchangedText=''          # text to test for in the output to see task didn't change anything (i.e. is ok)

  def() { Def "$@"; }
}

# loop runs def indirectly by looping through stdin and
# feeding each line to `run` as an argument.
loop() {
  while IFS=$' \t' read -r line; do
    run $line
  done
}

# ok sets the ok condition for the current task.
ok() { Condition=$1; }

# prog tells the task to show output as it goes.
# We want to see task progression on long-running tasks.
prog() { [[ $1 == on ]] && ShowProgress=1 || ShowProgress=0; }

declare -A Ok=()            # tasks that were already satisfied
declare -A Changed=()       # tasks that succeeded

# run runs def after checking that it is not already satisfied and records the result.
# Task must be set externally already.
run() {
  local task=$Task${1:+ - }${1:-}
  set -- $(eval "echo $*")
  [[ $Condition != '' ]] && ( eval $Condition &>/dev/null ) && {
    Ok[$task]=1
    echo -e "[ok]\t\t$task"

    return
  }

  ! (( ShowProgress )) && (( $# == 0 )) && echo -e "[begin]\t\t$task"

  local rc
  RunCommand $* && rc=$? || rc=$?

  if [[ $UnchangedText != '' && $Output == *"$UnchangedText"* ]]; then
    Ok[$task]=1
    echo -e "[ok]\t\t$task"
  elif (( rc == 0 )) && ( eval $Condition &>/dev/null ); then
    Changed[$task]=1
    echo -e "[changed]\t$task"
  else
    echo -e "[failed]\t$task"
    ! (( ShowProgress )) && echo -e "[output]\t$task\n$Output\n"
    echo '[stopped due to failure]'
    (( rc == 0 )) && echo '[task reported success but condition not met]'

    exit $rc
  fi
}

# RunCommand runs def and captures the output, optionally showing progress.
# We cheat and refer to variables from the outer scope, so this can only be run by `run`.
RunCommand() {
  local command
  [[ $BecomeUser == '' ]] &&
    command=( def $* ) ||
    command=( sudo -u $BecomeUser bash -c "$(declare -f def); def $*" )

  ! (( ShowProgress )) && { Output=$("${command[@]}" 2>&1); return; }

  echo -e "[progress]\t$task"
  Output=$("${command[@]}" 2>&1 | tee /dev/tty)
}


# section announces the section name
section() { local IFS=' '; echo -e "\n[section $*]"; }

# strict toggles strict mode for word splitting, globbing, unset variables and error on exit.
# It is used to set expectations properly for third-party code you may need to source.
# "off" turns it off, anything else turns it on.
# It should not be used in the global scope, only when in a function like main or a section.
# We reset this on every task.
# While the script starts by setting strict mode, it leaves out exit on error,
# which *is* covered here.
strict() {
  case $1 in
    off )
      IFS=$' \t\n'
      set +euf
      ;;
    on )
      IFS=$'\n'
      set -euf
      ;;
    * ) false;;
  esac
}

# summarize is run by the user at the end to report the results.
summarize() {
cat <<END

[summary]
ok:      ${#Ok[*]}
changed: ${#Changed[*]}
END

(( ${#Changed[*]} == 0 )) && return

local Task
for Task in ${!Changed[*]}; do
  echo -e "\t$Task"
done
}

# task defines the current task and, if given other arguments, creates a task and runs it.
# Tasks can loop if they include a '$1' argument and get fed items via stdin.
# It resets def if it isn't given a command in arguments.
task() {
  Task=${1:-}

  InitTaskEnv
}

# unchg defines the text to look for in command output to see that nothing changed.
# Such tasks get marked ok.
unchg() { UnchangedText=$1; }

# predefined helper tasks

task.curl() {
  task   "curl $1 >$2"
  exist  $2
  def    "mkdir -p $(dirname $2); curl -fsSL $1 >$2"
}

task.git_checkout() {
  local branch=$1 dir=$2
  task  "git checkout $branch"
  ok    "[[ $(cd $dir; git rev-parse --abbrev-ref HEAD) == $branch ]]"
  def   "cd $dir; git checkout $branch"
}

task.git_clone() {
  task   "git clone $1 $2"
  exist  $2
  def    "GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=no' git clone $1 $2"
}

task.ln() {
  (( $# == 0 )) && {
    task "create symlink"
    ok   'eval "set -- $1"; [[ -L $2 ]]'
    def() {
      eval "set -- $1"
      mkdir -p $(dirname $2)
      [[ -L $2 ]] && rm $2
      ln -sf $*
    }
    loop

    return
  }

  task   "create symlink - $1 $2"
  ok     "[[ -L $2 ]]"
  eval "def() {
    mkdir -p $(dirname $2)
    [[ -L $2 ]] && rm $2
    ln -sf $1 $2
  }"
  run
}

task.mkdir() {
  task "mkdir -p $1"
  ok "[[ -d $1 ]]"
  def "mkdir -p $1"
}
