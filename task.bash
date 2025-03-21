# task.bash -- harmonize your Unix work environments

# Naming Policy:
#
# All function and variable names are camelCased, but they may begin with uppercase letters.
#
# Function names are prefixed with "task." (always lowercase) so they are namespaced.
# Keyword function names are the exception to this.
# They are all lowercase letters and attempt to be five letters or shorter.
#
# Local variable names begin with lowercase letters.
# Global variable names begin with uppercase letters.
# Global variable names are namespaced by suffixing them with the randomly-generated letter X.
#
# Private function names begin with lowercase letters.
# Public function names begin with uppercase letters.

## task definition keywords

# desc sets DescriptionX, the task description.
# Beginning a new task this way also demands reinitialization of the task environment.
desc() {
  DescriptionX=${1:-}
  task.initTaskEnv
}

# exist is a shortcut for ok that tests for existence.
exist() { ok "[[ -e '$1' ]]"; }

# ok sets the ok ConditionX for the current task.
ok() { ConditionX=$1; }

# prog tells the task to show output as it goes.
# We want to see task progression on long-running tasks.
prog() { [[ $1 == on ]] && ShowProgressX=1 || ShowProgressX=0; }

declare -A OksX=()        # tasks that were already satisfied
declare -A ChangedsX=()   # tasks that succeeded

# run runs cmd after checking that it is not already satisfied and records the result.
# DescriptionX must be set externally already.
run() {
  [[ $ConditionX != '' ]] && ( eval "$ConditionX" &>/dev/null ) && {
    OksX[$DescriptionX]=1
    echo -e "[$(task.t ok)]\t\t$DescriptionX"

    return
  }

  ! (( ShortRunX || ShowProgressX )) && echo -ne "[$(task.t begin)]\t\t$DescriptionX"

  local command
  if [[ $RunAsUserX == '' ]]; then
    command=( cmd )
  else
    local remoteCommandString="
      $(declare -f cmd)
      cmd
    "
    command=( sudo -u "$RunAsUserX" bash -c "$remoteCommandString" )
  fi

  (( ShortRunX )) && {
    (( ShowProgressX )) || [[ $UnchangedTextX != '' ]] && {
      echo -e "\r[$(task.t skipping)]\t$DescriptionX"

      return
    }
  }

  local rc=0
  if (( ShowProgressX )); then
    echo -e "[$(task.t progress)]\t$DescriptionX"
    OutputX=$("${command[@]}" 2>&1 | tee /dev/tty) && rc=$? || rc=$?
  else
    OutputX=$("${command[@]}" 2>&1) && rc=$? || rc=$?
  fi

  if [[ $UnchangedTextX != '' && $OutputX == *"$UnchangedTextX"* ]]; then
    OksX[$DescriptionX]=1
    echo -e "\r[$(task.t ok)]\t\t$DescriptionX"
  elif (( rc == 0 )) && ( eval "$ConditionX" &>/dev/null ); then
    ChangedsX[$DescriptionX]=1
    echo -e "\r[$(task.t changed)]\t$DescriptionX"
  else
    echo -e "\r[$(task.t failed)]\t$DescriptionX"
    ! (( ShowProgressX )) && echo -e "[output]\t$DescriptionX\n$OutputX\n"
    echo 'stopped due to failure'
    (( rc == 0 )) && echo 'task reported success but condition not met'
  fi

  return $rc
}

# runas tells the task to run under sudo as user $1
runas() { RunAsUserX=$1; }

# unchg defines the text to look for in command OutputX to see that nothing changed.
# Such tasks get marked ok.
unchg() { UnchangedTextX=$1; }

## library functions

# task.cmd is the default implementation of cmd. The user calls the default implementation
# when they define the task using the cmd keyword. The default implementation accepts a
# command as an argument and redefines cmd to run it.  That then gets invoked by the run
# keyword.
task.cmd() {
  # don't try to make a one-liner with semicolons
  eval "cmd() {
    $1
  }"
  run
}

# task.initTaskEnv initializes all relevant settings for a new task.
task.initTaskEnv() {
  ConditionX=''              # an expression to tell when the task is already satisfied
  OutputX=''                 # OutputX from the task, including stderr
  RunAsUserX=''              # the user to sudo with
  ShowProgressX=0            # flag for showing OutputX as the task runs
  UnchangedTextX=''          # text to test for in the OutputX to see task didn't change anything (i.e. is ok)

  cmd() { task.cmd "$@"; }
}

ShortRunX=0

# task.SetShortRun says not to run tasks with progress.
task.SetShortRun() {
  case $1 in
    on  ) ShortRunX=1;;
    *   ) ShortRunX=0;;
  esac
}

# task.Summarize is run by the user at the end to report the results.
task.Summarize() {
  cat <<END

[summary]
ok:      ${#OksX[*]}
changed: ${#ChangedsX[*]}
END
}

GreenX=$'\033[38;5;82m'
OrangeX=$'\033[38;5;208m'
RedX=$'\033[38;5;196m'
YellowX=$'\033[38;5;220m'

ResetX=$'\033[0m'

declare -A Translations=(
  [begin]=$YellowX
  [changed]=$GreenX
  [failed]=$RedX
  [ok]=$GreenX
  [progress]=$YellowX
  [skipping]=$OrangeX
)

# task.t translates text for presentation.
task.t() {
  local text=$1
  echo "${Translations[$text]}$text$ResetX"
}

## helper tasks

task.GitClone() {
  local repo=$1 dir=$2 branch=$3
  desc   "clone repo ${1#git@} to $(basename $dir)"
  exist  "$dir"
  cmd    "GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=no' git clone --branch $branch $repo $dir"
}

task.Install() {
  local mode=$1 src=$2 dst=$3

  # for paths with spaces
  printf -v src %q "$src"
  printf -v dst %q "$dst"

  desc  "copy $src to $dst with mode $mode"
  exist "$dst"
  [[ $mode == 600 ]] && local dirMode=700
  cmd   "mkdir -p${dirMode:+m $dirMode} -- $(dirname $dst); install -m $mode -- $src $dst"
}

task.Ln() {
  local targetname=$1 linkname=$2

  # for paths with spaces
  printf -v targetname %q "$targetname"
  printf -v linkname %q "$linkname"

  desc  "symlink $linkname to $targetname"
  ok    "[[ -L $linkname ]]"
  eval  "
    mkdir -p \$(dirname $linkname)
    [[ -L $linkname ]] && rm $linkname
    ln -sf $targetname $linkname
  "
  run
}
