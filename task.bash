IFS=$'\n' # disable word splitting for most whitespace - this is required
set -uf   # error on unset variable references and turn off globbing - globbing off is required

# become tells the task to run under sudo as user $1
become() { BecomeUser=$1; }

# Def is the default implementation of def. The user calls the default implementation
# when they define the task using def. The default implementation accepts a command as
# arguments and redefines def to run that command then runs it by calling run,
# which is hardcoded to call def.
Def() {
  eval "def() { $1; }"
  run
}

# endhost resets the scope of the following tasks.
endhost() { Hosts=(); NoHosts=(); }

# endnohost resets the scope of the following tasks.
endnohost() { endhost; }

# endnosystem resets the scope of the following tasks.
endnosystem() { endsystem; }

# endsystem resets the scope of the following tasks.
endsystem() { Systems=(); NoSystems=(); }

# exist is a shortcut for ok that tests for existence.
exist() { ok "[[ -e $1 ]]"; }

Hosts=()

# host limits the scope of following commands to a set of hosts.
host() { Hosts=( ${*,,} ); }

# In returns whether item is in the named array.
In() {
  local -n array=$1
  local item=$2
  [[ "$IFS${array[*]}$IFS" == *"$IFS$item$IFS"* ]]
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

  def() { Def "$@"; }
}

Iterating=0

# iter runs func with the arguments of each line from stdin.
iter() {
  local func=$1 line

  Iterating=1

  while IFS=$' \t' read -r line; do
    eval "set -- $line"
    $func $*
  done

  Iterating=0
}

NoHosts=()

# nohost limits the scope of following tasks to not include the given hosts.
nohost() { NoHosts=( ${*,,} ); }

NoSystems=()

# nosystem limits the scope of following tasks to not include the given operating systems.
nosystem() { NoSystems=( ${*,,} ); }

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

  ShouldSkip && return

  [[ $Condition != '' ]] && ( eval $Condition &>/dev/null ) && {
    Ok[$task]=1
    echo -e "[ok]\t\t$task"

    return
  }

  ! (( ShowProgress )) && ! (( Iterating )) && echo -e "[begin]\t\t$task"

  local command
  if [[ $BecomeUser == '' ]]; then
    command=( def )
  else
    command=(
      sudo -u $BecomeUser bash -c "
        $(declare -f def)
        def
      "
    )
  fi

  ! (( ShowProgress )) && { Output=$("${command[@]}" 2>&1); return; }

  echo -e "[progress]\t$task"
  Output=$("${command[@]}" 2>&1 | tee /dev/tty) && rc=$? || rc=$?

  if [[ $UnchangedText != '' && $Output == *"$UnchangedText"* ]]; then
    Ok[$task]=1
    echo -e "[ok]\t\t$task"
  elif (( rc == 0 )) && ( eval $Condition &>/dev/null ); then
    Changed[$task]=1
    echo -e "[changed]\t$task"
  else
    echo -e "[failed]\t$task"
    ! (( ShowProgress )) && echo -e "[output]\t$task\n$Output\n"
    echo 'stopped due to failure'
    (( rc == 0 )) && echo 'task reported success but condition not met'

    exit $rc
  fi
}


# section announces the section name
section() {
  ShouldSkip && return
  local IFS=' '
  echo -e "\n[section $*]"
}

# ShouldSkip returns whether the task should be skipped.
ShouldSkip() {
  local hostname=${HOSTNAME,,}
  In NoHosts $hostname && return
  (( ${#Hosts[*]} > 0 )) && ! In Hosts $hostname && return

  [[ $OSTYPE == darwin* ]] && local system=macos || local system=linux
  In NoSystems $system && return
  (( ${#Systems[*]} )) && ! In Systems $system
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

Systems=()

# system limits the scope of the following tasks to the given operating system(s).
system() { Systems=( ${*,,} ); }

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

# unstrictly disables strict mode while running a command.
unstrictly() {
  strict off
  $*
  strict on
}

# predefined helper tasks

task.curl() {
  local url=$1 file=$2
  task   "download ${url##*/} from ${url%%/*} as $(basename file)"
  exist  $file
  def    "mkdir -p $(dirname $file); curl -fsSL $url >$file"
}

task.git_checkout() {
  local branch=$1 dir=$2
  task  "checkout branch $branch in repo $(basename $dir)"
  ok    "[[ $(cd $dir; git rev-parse --abbrev-ref HEAD) == $branch ]]"
  def   "cd $dir; git checkout $branch"
}

task.git_clone() {
  local repo=$1 dir=$2
  task   "clone repo ${1#git@} to $(basename $dir)"
  exist  $dir
  def    "GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=no' git clone $repo $dir"
}

task.ln() {
  local target=$1 link=$2
  task   "symlink $link to $target"
  ok     "[[ -L $link ]]"
  eval "
    def() {
      mkdir -p $(dirname $link)
      [[ -L $link ]] && rm $link
      ln -sf $target $link
    }
  "
  run
}

task.mkdir() {
  local dir=$1
  task "make directory $(basename dir)"
  ok "[[ -d $dir ]]"
  def "mkdir -p $dir"
}
