IFS=$'\n' # disable word splitting for most whitespace - this is required
set -uf   # error on unset variable references and turn off globbing - globbing off is required

# become tells the task to run under sudo as user $1
become() { BecomeUser=$1; }

# Def is the default implementation of def. The user calls the default implementation
# when they define the task using def. The default implementation accepts a command as
# arguments and redefines def to run that command then runs it by calling run,
# which is hardcoded to call def.
Def() {
  eval "def() {
    $1
  }"
  run
}

Iterating=0

# endhost resets the scope of the following tasks.
endhost() { YesHosts=(); NotHosts=(); }

# endsystem resets the scope of the following tasks.
endsystem() { YesSystems=(); NotSystems=(); }

# exist is a shortcut for ok that tests for existence.
exist() { ok "[[ -e $1 ]]"; }

# ForMe returns whether this system meets the filters.
ForMe() {
  local hostname=$($HostnameFunc)
  ! In NotHosts $hostname || return
  (( ${#YesHosts[*]} == 0 )) || In YesHosts $hostname || return

  local systems=( $($SystemTypeFunc) ) system
  for system in ${systems[*]}; do
    ! In NotSystems $system || return
  done

  (( ${#YesSystems[*]} == 0 )) && return

  for system in ${systems[*]}; do
    In YesSystems $system && return
  done

  return 1
}

# glob expands $1 with globbing on.
glob() {
  Globbing on
  set -- $1
  local out
  printf -v out '%q\n' $*
  [[ $out != $'\'\'\n' ]] && echo "${out%$'\n'}"
  Globbing off
}

# Globbing toggles globbing.
Globbing() {
  case $1 in
    off ) shopt -u nullglob; set -o noglob;;
    on  ) shopt -s nullglob; set +o noglob;;
  esac
}

YesHosts=()

# host limits the scope of following commands to a set of hosts.
host() { YesHosts=( ${*,,} ); }

# Hostname is the default implementation of the function that identifies the host.
Hostname() { echo ${HOSTNAME,,}; }

# In returns whether item is in the named array.
In() {
  local -n array=$1
  [[ "$IFS${array[*]}$IFS" == *"$IFS$2$IFS"* ]]
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

NotHosts=()

# nothost limits the scope of following tasks to not include the given hosts.
nothost() { NotHosts=( ${*,,} ); }

NotSystems=()

# notsystem limits the scope of following tasks to not include the given operating systems.
notsystem() { NotSystems=( ${*,,} ); }

# ok sets the ok condition for the current task.
ok() { Condition=$1; }

# prog tells the task to show output as it goes.
# We want to see task progression on long-running tasks.
prog() { [[ $1 == on ]] && ShowProgress=1 || ShowProgress=0; }

HostnameFunc=Hostname       # the name of the function that determines hostname
SystemTypeFunc=SystemType   # the name of the function that determines system type

# register registers either hostname or system functions.
register() {
  local functionType=$1 implementation=$2

  case $functionType in
    hostnameFunc    ) HostnameFunc=$implementation;;
    systemTypeFunc  ) SystemTypeFunc=$implementation;;
  esac
}

declare -A OKs=()           # tasks that were already satisfied
declare -A Changeds=()      # tasks that succeeded

# run runs def after checking that it is not already satisfied and records the result.
# Task must be set externally already.
run() {
  ! ForMe && return

  [[ $Condition != '' ]] && ( eval $Condition &>/dev/null ) && {
    OKs[$Task]=1
    echo -e "[$(T ok)]\t\t$Task"

    return
  }

  ! (( ShortRun )) && ! (( ShowProgress )) && ! (( Iterating )) && echo -e "[$(T begin)]\t\t$Task"

  local command
  if [[ $BecomeUser == '' ]]; then
    command=( def )
  else
    remoteCommandString="
      $(declare -f def)
      def
    "
    command=( sudo -u $BecomeUser bash -c "$remoteCommandString" )
  fi

  (( ShortRun )) && {
    (( ShowProgress )) || [[ $UnchangedText != '' ]] && {
      echo -e "[skipping]\t$Task"

      return
    }
  }

  local rc=0
  if (( ShowProgress )); then
    echo -e "[$(T progress)]\t$Task"
    Output=$("${command[@]}" 2>&1 | tee /dev/tty) && rc=$? || rc=$?
  else
    Output=$("${command[@]}" 2>&1) && rc=$? || rc=$?
  fi

  if [[ $UnchangedText != '' && $Output == *"$UnchangedText"* ]]; then
    OKs[$Task]=1
    echo -e "[$(T ok)]\t\t$Task"
  elif (( rc == 0 )) && ( eval $Condition &>/dev/null ); then
    Changeds[$Task]=1
    echo -e "[$(T changed)]\t$Task"
  else
    echo -e "[$(T failed)]\t$Task"
    ! (( ShowProgress )) && echo -e "[output]\t$Task\n$Output\n"
    echo 'stopped due to failure'
    (( rc == 0 )) && echo 'task reported success but condition not met'
  fi

  return $rc
}

# section announces the section name
section() {
  ! ForMe && return
  local IFS=' '
  echo -e "\n[section $*]"
}

ShortRun=0

# shortRun says not to run tasks with progress.
shortRun() { ShortRun=1; }

# strict toggles strict mode for word splitting, globbing, unset variables and error on exit.
# It is used to set expectations properly for third-party code you may need to source.
# "off" turns it off, anything else turns it on.
# It should not be used in the global scope, only when in a function like main or a section.
# We reset this on every task.
# While the script starts by setting strict mode, it leaves out exit on error,
# which *is* covered here.
strict() {
  case $1 in
    off ) IFS=$' \t\n'; set +euf;;
    on  ) IFS=$'\n'; set -euf;;
    *   ) false;;
  esac
}

# summarize is run by the user at the end to report the results.
summarize() {
cat <<END

[summary]
ok:      ${#OKs[*]}
changed: ${#Changeds[*]}
END

(( ${#Changeds[*]} == 0 )) && return

local Task
for Task in ${!Changeds[*]}; do
  echo -e "\t$Task"
done
}

YesSystems=()

# system limits the scope of the following tasks to the given operating system(s).
system() { YesSystems=( ${*,,} ); }

# SystemType is the default function for determining the system type.
SystemType() { [[ $OSTYPE == darwin* ]] && echo macos || echo linux; }

Blue='\033[38;5;33m'
Green='\033[38;5;82m'
Orange='\033[38;5;208m'
Purple='\033[38;5;201m'
Red='\033[38;5;196m'
Yellow='\033[38;5;220m'

Reset='\033[0m'

declare -A Translations=(
  [begin]=$Yellow
  [changed]=$Orange
  [failed]=$Red
  [ok]=$Green
  [progress]=$Yellow
)

# T translates text for presentation.
T() {
  echo ${Translations[$1]}$1$Reset
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

# unstrictly disables strict mode while running a command.
unstrictly() {
  strict off
  "$@"
  strict on
}

## fp

# each applies command to each argument from stdin.
# Works with commands containing newlines.
each() {
  local command=$1 arg

  Iterating=1
  while IFS=$'' read -r arg; do
    eval "$command $arg"
  done
  Iterating=0
  return 0  # so we don't accidentally return false
}

# keepIf filters lines from stdin using command.
# Works with commands containing newlines.
keepIf() {
  local command=$1 arg
  while IFS='' read -r arg; do
    eval "$command $arg" && echo $arg
  done
  return 0  # so we don't accidentally return false
}


# map returns expression evaluated with the value of stdin as $varname.
map() {
  local varname=$1 expression=$2
  local $varname
  while IFS=$'' read -r $varname; do
    eval "echo \"$expression\""
  done
}

## helper tasks

task.curl() {
  local url=$1 filename=$2
  task   "download ${url##*/} from ${url%/*} as $(basename $filename)"
  exist  $filename
  def    "mkdir -p $(dirname $filename); curl -fsSL $url >$filename"
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
  local targetname=$1 linkname=$2
  printf -v targetname %q $targetname
  printf -v linkname %q $linkname

  task  "symlink $linkname to $targetname"
  ok    "[[ -L $linkname ]]"
  eval  "
    def() {
      mkdir -p $(dirname $linkname)
      [[ -L $linkname ]] && rm $linkname
      ln -sf $targetname $linkname
    }
  "
  run
}

task.mkdir() {
  local dir=$(printf %q $1)
  task "make directory $(basename $dir)"
  ok "[[ -d $dir ]]"
  def "mkdir -p $dir"
}
