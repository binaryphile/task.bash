# task.bash -- harmonize your Unix work environments

# Naming Policy:
#
# All function and variable names are camelCased.
#
# Private function names begin with lowercase letters.
# Public function names begin with uppercase letters.
# Function names are prefixed with "task." (always lowercase) so they are namespaced.
#
# Keyword function names are the exception.
# They are all lowercase letters and should be five letters or shorter.
#
# Local variable names begin with lowercase letters, e.g. localVariable.
#
# Global variable names begin with uppercase letters, e.g. GlobalVariable.
# Since this is a library, global variable names are also namespaced by suffixing them with
# the randomly-generated letter X, e.g. GlobalVariableX.
# Global variables are not public.  Library consumers should not be aware of them.
# If users need to interact with them, create accessor functions for the purpose.
#
# Variable declarations that are name references borrow the environment namespace, e.g.
# "local -n ARRAY=$1".

## task definition keywords

# cmd runs $cmd after checking that it is not already satisfied and records the result.
cmd() {
  local CMD=$1

  # if a previous cmd in a try block failed, skip subsequent cmds
  (( TryFailedX )) && {
    echo -e "[$(task.t skipping)]\t$DescriptionX"

    return
  }

  [[ $ConditionX != '' ]] && ( eval "$ConditionX" &>/dev/null ) && {
    OksX[$DescriptionX]=1
    echo -e "[$(task.t ok)]\t\t$DescriptionX"

    return
  }

  # check preflight condition before running cmd
  [[ $CheckX != '' ]] && ! ( eval "$CheckX" &>/dev/null ) && {
    (( TryModeX )) && {
      echo -e "[$(task.t tried)]\t\t$DescriptionX"
      TriedsX[$DescriptionX]=1
      TryFailedX=1

      return 0
    }
    echo -e "[$(task.t failed)]\t$DescriptionX"
    echo 'stopped due to failure (preflight check)'
    return 1
  }

  ! (( ShortRunX || ShowProgressX )) && echo -ne "[$(task.t begin)]\t\t$DescriptionX"

  [[ $RunAsUserX != '' ]] && CMD="sudo -u ${RunAsUserX@Q} bash -c ${CMD@Q}"

  (( ShortRunX )) && {
    (( ShowProgressX )) || [[ $UnchangedTextX != '' ]] && {
      echo -e "\r\033[K[$(task.t skipping)]\t$DescriptionX"

      return
    }
  }

  # if the argument looks like a bare function name, verify it exists before
  # eval. Placed after all early-return paths (TryFailed, ok, check, ShortRun)
  # so the guard only fires when the command will actually be executed.
  # Uses $1 (original argument) since RunAsUserX may have wrapped CMD.
  if [[ $1 =~ ^[a-zA-Z_][a-zA-Z0-9_.]*$ ]]; then
    case "$(type -t "$1" 2>/dev/null)" in
      function|builtin) ;;
      *) echo "fatal: cmd references undefined function: $1" >&2; return 1;;
    esac
  fi

  local RC=0
  if (( ShowProgressX )); then
    echo -e "[$(task.t progress)]\t$DescriptionX"
    OutputX=$(eval "$CMD" 2>&1 | tee /dev/tty) && RC=$? || RC=$?
  else
    OutputX=$(eval "$CMD" 2>&1) && RC=$? || RC=$?
  fi

  if [[ $UnchangedTextX != '' && $OutputX == *"$UnchangedTextX"* ]]; then
    OksX[$DescriptionX]=1
    echo -e "\r\033[K[$(task.t ok)]\t\t$DescriptionX"
  elif (( RC == 0 )) && ( eval "$ConditionX" &>/dev/null ); then
    ChangedsX[$DescriptionX]=1
    echo -e "\r\033[K[$(task.t changed)]\t$DescriptionX"
  else
    (( TryModeX )) && {
      echo -e "\r\033[K[$(task.t tried)]\t\t$DescriptionX"
      if ! (( ShowProgressX )); then
        while IFS= read -r line; do echo -e "[$(task.t output)]\t$line"; done <<<"$OutputX"
        echo
      fi
      TriedsX[$DescriptionX]=1
      TryFailedX=1

      return 0
    }
    echo -e "\r\033[K[$(task.t failed)]\t$DescriptionX"
    if ! (( ShowProgressX )); then
      while IFS= read -r line; do echo -e "[$(task.t output)]\t$line"; done <<<"$OutputX"
      echo
    fi
    echo 'stopped due to failure'
    (( RC == 0 )) && echo 'task reported success but condition not met'
  fi

  return $RC
}

# desc sets DescriptionX, the task description.
# Beginning a new task this way also demands reinitialization of the task environment.
desc() {
  task.initTaskEnv
  DescriptionX=${1:-}
}

# check sets a preflight condition that must pass before cmd runs.
# Unlike ok, check is not a success condition -- it gates execution.
# If check fails, the task is marked tried (in try mode) or failed without running cmd.
check() { CheckX=$1; }

# exist is a shortcut for ok that tests for path existence.
exist() { ok "[[ -e $1 ]]"; }

# ok sets the ok ConditionX for the current task.
ok() { ConditionX=$1; }

# prog tells the task to show output as it goes.
# We want to see task progression on long-running tasks.
prog() { [[ $1 == on ]] && ShowProgressX=1 || ShowProgressX=0; }

declare -A OksX=()        # tasks that were already satisfied
declare -A ChangedsX=()   # tasks that succeeded
declare -A TriedsX=()     # tasks that failed gracefully under try

# runas tells the task to run under sudo as user $1
runas() { RunAsUserX=$1; }

# unchg defines the text to look for in command OutputX to see that nothing changed.
# Such tasks get marked ok.
unchg() { UnchangedTextX=$1; }

## library functions

# task.initTaskEnv initializes all relevant settings for a new task.
task.initTaskEnv() {
  CheckX=''                  # a preflight expression that must pass before cmd runs
  ConditionX=''              # an expression to tell when the task is already satisfied
  DescriptionX=''
  OutputX=''                 # OutputX from the task, including stderr
  RunAsUserX=''              # the user to sudo with
  ShowProgressX=0            # flag for showing OutputX as the task runs
  UnchangedTextX=''          # text to test for in the OutputX to see task didn't change anything (i.e. is ok)
}

# initialize environment
task.initTaskEnv
ShortRunX=0     # doesn't reset from task to task
TryModeX=0      # doesn't reset from task to task
TryFailedX=0    # doesn't reset from task to task

# try runs a command, allowing it to fail gracefully.
# Failed tasks are marked [tried] and tracked separately.
# Subsequent cmds in the same try block are skipped after a failure.
# cmd returns 0 in try mode, so set -e does not trigger.
# Saves and restores state so try blocks can nest.
try() {
  local prevTryMode=$TryModeX prevTryFailed=$TryFailedX
  TryModeX=1
  TryFailedX=0
  "$@"
  TryModeX=$prevTryMode
  TryFailedX=$prevTryFailed
}

task.Platform() {
  [[ $OSTYPE != darwin* ]] || { echo macos; return; }
  echo linux
}

# task.SetShortRun says not to run tasks with progress.
task.SetShortRun() { [[ $1 == on ]] && ShortRunX=1 || ShortRunX=0; }

# task.Summarize is run by the user at the end to report the results.
task.Summarize() {
  cat <<END

[summary]
ok:      ${#OksX[*]}
changed: ${#ChangedsX[*]}
tried:   ${#TriedsX[*]}
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
  [output]=$OrangeX
  [tried]=$OrangeX
)

# task.t translates text for presentation.
task.t() {
  local text=$1
  echo "${Translations[$text]}$text$ResetX"
}

# section announces a section heading.
section() { echo $'\n'"[section $*]"; }

## helper tasks

task.GitClone() {
  local repo=$1 dir=$2 branch=$3
  desc   "clone repo ${1#git@} to $dir"
  exist  "'$dir'"

  task.gitClone() {
    GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=no' git clone --branch "$branch" "$repo" "$dir"
  }
  cmd task.gitClone
}

# task.GitUpdate pulls the latest changes for a repo.
# Uses unchg so it is skipped in short-run mode.
# Skips repos with unpushed or diverged commits to avoid rebasing over local work.
# Skips detached HEAD (ambiguous state).
task.GitUpdate() {
  local dir=$1
  desc   "update $dir"
  unchg  'Already up to date'
  check  "task.gitUpdateSafe '$dir'"

  cmd "GIT_SSH_COMMAND='ssh -o ConnectTimeout=2' git -c http.connectTimeout=2 -C '$dir' pull --rebase"
}

# task.gitUpdateSafe checks whether pull --rebase is safe for a repo.
# Returns 0 (safe) only when the repo is on a branch, behind-only or even.
# Blocks on: ahead, diverged, detached HEAD, missing upstream.
task.gitUpdateSafe() {
  local dir=$1
  # must be on a branch
  local branch
  branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null) || return 1
  [[ $branch != HEAD ]] || return 1
  # must have an upstream
  git -C "$dir" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1 || return 1
  # must not be ahead or diverged
  local counts
  counts=$(git -C "$dir" rev-list --left-right --count HEAD...'@{upstream}' 2>/dev/null) || return 1
  local ahead behind
  read -r ahead behind <<<"$counts"
  (( ahead == 0 ))
}

task.Install() {
  local mode=$1 src=$2 dst=$3
  desc  "copy $src to $dst with mode $mode"
  exist "'$dst'"

  task.install() {
    [[ $mode == 600 ]] && local dirMode=700
    mkdir -p${dirMode:+m $dirMode} -- "$(dirname "$dst")"
    install -m "$mode" -- "$src" "$dst"
  }
  cmd task.install
}

task.Ln() {
  local targetname=$1 linkname=$2
  desc  "symlink $linkname to $targetname"

  task.linknameIsLink() { [[ -L $linkname ]]; }
  ok task.linknameIsLink

  task.ln() {
    mkdir -p "$(dirname "$linkname")"
    [[ -L $linkname ]] && rm "$linkname"
    ln -sf "$targetname" "$linkname"
  }
  cmd task.ln
}
