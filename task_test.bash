source ./task.bash

NL=$'\n'

## functions

# test_cmd tests the function that runs tasks.
# Subtests are run with tesht.Run.
test_cmd() {
  local -A case1=(
    [name]='not run when ok'

    [cmd]='echo hello'
    [ok]=true
    [want]=$'[\E[38;5;82mok\E[0m]\t\tnot run when ok'
  )

  local -A case2=(
    [name]='given short run, when progress, then skip'

    [cmd]='echo hello'
    [prog]=on
    [shortrun]=on
    [want]=$'\r[\E[38;5;208mskipping\E[0m]\tgiven short run, when progress, then skip'
  )

  local -A case3=(
    [name]='given short run, when unchg, then skip'

    [cmd]='echo hello'
    [shortrun]=on
    [unchg]=hello
    [want]=$'\r[\E[38;5;208mskipping\E[0m]\tgiven short run, when unchg, then skip'
  )

  # subtest runs each subtest.
  # casename is expected to be the name of an associative array holding at least the key "name".
  subtest() {
    local casename=$1

    ## arrange

    # create variables from the keys/values of the test map
    unset -v ok shortrun prog unchg want wanterr  # unset optional fields
    eval "$(tesht.Inherit "$casename")"

    desc "$name"  # desc resets the environment so make other changes after

    [[ -v ok        ]] && ok "$ok"
    [[ -v prog      ]] && prog "$prog"
    [[ -v shortrun  ]] && task.SetShortRun "$shortrun"
    [[ -v unchg     ]] && unchg "$unchg"

    ## act

    # run the command and capture the output and result code
    local got rc
    got=$(cmd "$cmd" 2>&1) && rc=$? || rc=$?

    ## assert

    # if this is a test for error behavior, check it
    [[ -v wanterr ]] && {
      (( rc == wanterr )) && return

      echo "${NL}cmd: error = $rc, want: $wanterr$NL$got"
      return 1
    }

    # assert no error
    (( rc == 0 )) || {
      echo "${NL}cmd: error = $rc, want: 0$NL$got"
      return 1
    }

    # assert that we got the wanted output
    [[ $got == "$want" ]] || {
      echo "${NL}cmd: got doesn't match want:$NL$(tesht.Diff "$got" "$want" 1)$NL"
      echo "use this line to update want to match this output:${NL}want=${got@Q}"
      return 1
    }
  }

  local failed=0 casename
  for casename in ${!case@}; do
    tesht.Run test_cmd $casename || {
      (( $? == 128 )) && return 128 # fatal
      failed=1
    }
  done

  return $failed
}

# test_cmd_GivenShortRunWhenProgressThenNotRun sees that an ok task does not invoke the command.
test_cmd_GivenShortRunWhenProgressThenNotRun() {
  ## arrange
  task.SetShortRun on
  desc 'test_cmd_GivenShortRunWhenProgressThenNotRun'
  prog on

  ## act
  # run the command and capture the output and result code
  local got rc
  got=$(cmd 'echo hello' 2>&1) && rc=$? || rc=$?

  ## assert

  # assert no error
  (( rc == 0 )) || {
    echo "${NL}cmd: error = $rc, want: 0$NL$got"
    return 1
  }

  # assert that we got the wanted output
  local want=$'\r[\E[38;5;208mskipping\E[0m]\ttest_cmd_GivenShortRunWhenProgressThenNotRun'
  [[ $got == "$want" ]] || {
    echo "${NL}cmd: got doesn't match want:$NL$(tesht.Diff "$got" "$want")$NL"
    echo "use this line to update want to match this output:${NL}want=${got@Q}"
    return 1
  }
}

## tasks

# test_task.GitClone tests whether git cloning works.
# It does its work in a directory it creates in /tmp.
test_task.GitClone() {
  ## arrange

  # temporary directory
  local dir=$(tesht.MktempDir) || return 128  # fatal if can't make dir
  trap "rm -rf $dir" EXIT                     # always clean up
  cd "$dir"

  createCloneRepo

  ## act

  # run the command and capture the output and result code
  local got rc
  got=$(task.GitClone clone clone2 main 2>&1) && rc=$? || rc=$?

  ## assert

  # assert no error
  (( rc == 0 )) || {
    echo "${NL}task.GitClone: error = $rc, want: 0$NL$got"
    return 1
  }

  # assert that the repo was cloned
  [[ -e clone2/.git ]] || {
    echo "${NL}task.GitClone: expected .git directory.$NL$got"
    return 1
  }

  # assert that we got the wanted output
  local want=$'[\E[38;5;220mbegin\E[0m]\t\tclone repo clone to clone2\r[\E[38;5;82mchanged\E[0m]\tclone repo clone to clone2'

  [[ $got == "$want" ]] || {
    echo "${NL}task.GitClone: got doesn't match want:$NL$(tesht.Diff "$got" "$want")$NL"
    echo "use this line to update want to match this output:${NL}want=${got@Q}"
    return 1
  }
}

# test_task.Ln tests whether the symlink task works.
# There are subtests for link creation and when link creation fails.
# Subtests are run with tesht.Run.
test_task.Ln() {
  local -A case1=(
    [name]='spaces in link and target'
    [targetname]='a target.txt'
    [linkname]='a link.txt'
    [want]=$'[\E[38;5;220mbegin\E[0m]\t\tsymlink a link.txt to a target.txt\r[\E[38;5;82mchanged\E[0m]\tsymlink a link.txt to a target.txt'
  )

  local -A case2=(
    [name]='fail on invalid link location'
    [targetname]='target.txt'
    [linkname]='/doesntexist/link.txt'
    [wanterr]=1
  )

  # subtest runs each subtest.
  # command is the parent function name.
  # case is expected to be the name of an associative array holding at least the key "name".
  # Each subtest that needs a directory creates it in /tmp.
  subtest() {
    local casename=$1

    ## arrange

    # temporary directory
    local dir=$(tesht.MktempDir) || return 128  # fatal if can't make dir
    trap "rm -rf $dir" EXIT                     # always clean up
    cd $dir

    # create variables from the keys/values of the test map
    unset -v wanterr  # unset optional fields
    eval "$(tesht.Inherit "$casename")"

    ## act

    # run the command and capture the output and result code
    local got rc
    got=$(task.Ln "$targetname" "$linkname" 2>&1) && rc=$? || rc=$?

    ## assert

    # if this is a test for error behavior, check it
    [[ -v wanterr ]] && {
      (( rc == wanterr )) && return

      echo -e "\ntask.Ln: error = $rc, want: $wanterr\n$got"
      return 1
    }

    # assert no error
    (( rc == 0 )) || {
      echo "${NL}task.Ln: error = $rc, want: 0$NL$got"
      return 1
    }

    # assert that the symlink was made
    [[ -L $linkname ]] || {
      echo "${NL}task.Ln: expected $linkname to be symlink$NL$got"
      return 1
    }

    # assert that we got the wanted output
    [[ $got == "$want" ]] || {
      echo "${NL}task.Ln: got doesn't match want:$NL$(tesht.Diff "$got" "$want")$NL"
      echo "use this line to update want to match this output:${NL}want=${got@Q}"
      return 1
    }
  }

  local failed=0 casename
  for casename in ${!case@}; do
    tesht.Run test_task.Ln $casename || {
      (( $? == 128 )) && return 128   # fatal
      failed=1
    }
  done

  return $failed
}

## helpers

# createCheckoutRepo creates a git repository in the current directory.
# It creates an initial commit.
# It creates, but does not switch to, branchname.
# It suppresses stdout with a redirection of the entire function.
createCheckoutRepo() {
  local branchname=$1

  git init
  echo hello >hello.txt
  git add hello.txt
  git commit -m init
  git branch $branchname
} >/dev/null

# createCloneRepo creates a git repository as a subdirectory of the current directory.
# It creates an initial commit.
# It runs in a subshell so it can change directory without affecting the caller.
# It suppresses stdout with a redirection of the entire function.
createCloneRepo() (
  git init clone
  cd clone
  echo hello >hello.txt
  git add hello.txt
  git commit -m init
) >/dev/null
