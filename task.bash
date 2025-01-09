IFS=$'\n' # disable word splitting for most whitespace - this is required
set -uf   # error on unset variable references and turn off globbing - globbing off is required

# become tells the task to run under sudo as user $1
become:() { BecomeUser=$1; }

IsKeyTask=0  # whether the loop inputs are key, value pairs

# Def is the default implementation of `def:`.
# The user calls the default implementation when they define the task using `def:`. The default
# implementation accepts a task as arguments and redefines def to run that command, running
# it indirectly by then calling run, or loop if there is a '$1' argument in the task.
Def() {
  (( $# == 0 )) && { LoopCommands; return; } # if no arguments, the inputs are commands

  # if one argument, treat it as arbitrary quoted bash and handle keytask variables
  (( $# == 1 )) && {
    local prefix=''
    (( IsKeyTask )) && prefix='eval "$( GetVariables $* )"; '
    eval "def:() { $prefix$1; }"

    [[ $IsKeyTask == 1 || $1 == *'$1'* ]] && loop || run

    return
  }

  # otherwise compose a simple command from the arguments
  local command
  printf -v command '%q ' "$@"
  eval "def:() { $command; }"
  run
}

# GetVariables returns an eval-ready set of variables from the key, value input.
GetVariables() {
  local -A values="( $* )"  # trick to expand to associative array
  local name
  for name in ${!values[*]}; do
    printf 'local %s=%q\n' $name "${values[$name]}"
  done
}

# InitTaskEnv initializes all relevant settings for a new task.
InitTaskEnv() {
  # reset strict, shared variables and the def function
  strict on

  BecomeUser=''             # the user to sudo with
  Condition=''              # an expression to tell when the task is already satisfied
  Output=''                 # output from the task, including stderr
  ShowProgress=0            # flag for showing output as the task runs
  UnchangedText=''          # text to test for in the output to see task didn't change anything (i.e. is ok)

  def:() { Def "$@"; }
}

# keytask defines a task that loops with key, value pairs from stdin.
# values are made available to the task as variables of the key name.
# key, value pairs have bash associative array syntax minus the parentheses.
keytask:() { IsKeyTask=1; task: "$@"; IsKeyTask=0; }

# loop runs def indirectly by looping through stdin and
# feeding each line to `run` as an argument.
loop() {
  while IFS=$' \t' read -r line; do
    run $line
  done
}

# LoopCommands runs each line of input as its own task.
LoopCommands() {
  while IFS=$' \t' read -r line; do
    eval "def:() { $line; }"
    run $line
  done
}

# ok sets the ok condition for the current task.
ok:() { Condition=$1; }

# prog tells the task to show output as it goes.
# We want to see task progression on long-running tasks.
prog:() { [[ $1 == on ]] && ShowProgress=1 || ShowProgress=0; }

declare -A Ok=()            # tasks that were already satisfied
declare -A Changed=()       # tasks that succeeded

# run runs def after checking that it is not already satisfied and records the result.
# Task must be set externally already.
run() {
  local task=$Task${1:+ - }${1:-}
  [[ $Condition != '' ]] && ( eval $Condition ) && {
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
  elif (( rc == 0 )) && ( eval $Condition ); then
    Changed[$task]=1
    echo -e "[changed]\t$task"
  else
    echo -e "[failed]\t$task"
    ! (( ShowProgress )) && echo -e "[output:]\n$Output\n"
    echo '[stopped due to failure]'
    (( rc == 0 )) && echo '[task reported success but condition not met]'

    exit $rc
  fi
}

# RunCommand runs def and captures the output, optionally showing progress.
# We cheat and refer to the task from the outer scope, so this can only be run by `run`.
RunCommand() {
  local command
  [[ $BecomeUser == '' ]] &&
    command=( def: $* ) ||
    command=( sudo -u $BecomeUser bash -c "$( declare -f def: ); def: $*" )

  ! (( ShowProgress )) && { Output=$( "${command[@]}" 2>&1 ); return; }

  echo -e "[progress]\t$task"
  Output=$( "${command[@]}" 2>&1 | tee /dev/tty )
}


# section announces the section name and runs the named section function.
section() {
  echo -e "\n[section $1]"
  $1
}

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
  esac
}

# summarize is run by the user at the end to report the results.
summarize() {
cat <<END

[summary]
ok:      ${#Ok[*]}
changed: ${#Changed[*]}
END
}

# task defines the current task and, if given other arguments, creates a task and runs it.
# Tasks can loop if they include a '$1' argument and get fed items via stdin.
# It resets def if it isn't given a command in arguments.
task:() {
  Task=$1

  InitTaskEnv
  (( $# == 1 )) && return
  shift

  def: "$@"
}

# unchg defines the text to look for in command output to see that nothing changed.
# Such tasks get marked ok.
unchg:() { UnchangedText=$1; }
