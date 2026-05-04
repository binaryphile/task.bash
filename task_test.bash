source ./task.bash

NL=$'\n'

## functions

# test_cmd tests the function that runs tasks.
# Subtests are run with tesht.Run.
test_cmd() {
  local -A case1=(
    [name]='not run when ok'

    [command]="cmd 'echo hello'"
    [ok]=true
    [wants]="(ok 'not run when ok')"
  )

  local -A case2=(
    [name]='given short run, when progress, then skip'

    [command]="cmd 'echo hello'"
    [prog]=on
    [shortrun]=on
    [wants]="(skipping 'given short run, when progress, then skip')"
  )

  local -A case3=(
    [name]='given short run, when unchg, then skip'

    [command]="cmd 'echo hello'"
    [shortrun]=on
    [unchg]=hello
    [wants]="(skipping 'given short run, when unchg, then skip')"
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
    got=$(eval "$command" 2>&1) && rc=$? || rc=$?

    ## assert

    # assert no error
    (( rc == 0 )) || {
      echo "${NL}cmd: error = $rc, want: 0$NL$got"
      return 1
    }

    # assert that we got the wanted output
    local want=$(IFS='*'; echo "*${wants[*]}*")
    [[ $got == $want ]] || {
      echo "${NL}cmd: got doesn't match want:$NL$(tesht.Diff "$got" "$want" 1)$NL"
      echo "use this line to update want to match this output:${NL}want=${got@Q}"
      return 1
    }
  }

  local failed=0 casename
  for casename in ${!case@}; do
    tesht.Run $casename || {
      (( $? == 128 )) && return 128 # fatal
      failed=1
    }
  done

  return $failed
}

# test_try tests the try wrapper for graceful failure.
test_try() {
  local -A case1=(
    [name]='failing command shows tried and returns 0'

    [wants]="(tried 'failing command shows tried and returns 0')"
  )

  local -A case2=(
    [name]='succeeding command works normally under try'

    [wants]="(ok 'succeeding command works normally under try')"
  )

  local -A case3=(
    [name]='subsequent cmd skipped after try failure'

    [wants]="(tried 'subsequent cmd skipped after try failure' skipping 'second task in try block')"
  )

  local -A case4=(
    [name]='check failure shows tried under try'

    [wants]="(tried 'check failure shows tried under try')"
  )

  local -A case5=(
    [name]='nested try restores outer state'

    [wants]="(tried 'outer failing task' tried 'inner failing task' skipping 'task after outer failure')"
  )

  subtest() {
    local casename=$1

    ## arrange

    eval "$(tesht.Inherit "$casename")"

    ## act

    local got rc

    case $name in
      'failing command shows tried and returns 0' )
        failingTask() {
          desc "$name"
          ok false
          cmd false
        }
        got=$(try failingTask 2>&1) && rc=$? || rc=$?
        ;;

      'succeeding command works normally under try' )
        succeedingTask() {
          desc "$name"
          ok '[[ -e / ]]'
          cmd true
        }
        got=$(try succeedingTask 2>&1) && rc=$? || rc=$?
        ;;

      'subsequent cmd skipped after try failure' )
        multiCmdTask() {
          desc "$name"
          ok false
          cmd false

          desc 'second task in try block'
          ok false
          cmd true
        }
        got=$(try multiCmdTask 2>&1) && rc=$? || rc=$?
        ;;

      'check failure shows tried under try' )
        checkFailTask() {
          desc "$name"
          ok    false
          check false
          cmd   true
        }
        got=$(try checkFailTask 2>&1) && rc=$? || rc=$?
        ;;

      'nested try restores outer state' )
        nestedTryTask() {
          desc 'outer failing task'
          ok false
          cmd false

          try innerTask

          desc 'task after outer failure'
          ok false
          cmd true
        }
        innerTask() {
          desc 'inner failing task'
          ok false
          cmd false
        }
        got=$(try nestedTryTask 2>&1) && rc=$? || rc=$?
        ;;
    esac

    ## assert

    # assert no error
    (( rc == 0 )) || {
      echo "${NL}try: error = $rc, want: 0$NL$got"
      return 1
    }

    # assert that we got the wanted output
    local want=$(IFS='*'; echo "*${wants[*]}*")
    [[ $got == $want ]] || {
      echo "${NL}try: got doesn't match want:$NL$(tesht.Diff "$got" "$want" 1)$NL"
      echo "use this line to update want to match this output:${NL}want=${got@Q}"
      return 1
    }
  }

  local failed=0 casename
  for casename in ${!case@}; do
    tesht.Run $casename || {
      (( $? == 128 )) && return 128 # fatal
      failed=1
    }
  done

  return $failed
}

## tasks

# test_task.GitClone tests whether git cloning works.
# It does its work in a directory it creates in /tmp.
test_task.GitClone() {
  ## arrange

  # temporary directory
  local dir
  tesht.MktempDir dir || return 128  # fatal if can't make dir
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
  local wants=(begin 'clone repo clone to clone2' changed 'clone repo clone to clone2')
  local want=$(IFS='*'; echo "*${wants[*]}*")
  [[ $got == $want ]] || {
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
    [wants]="(begin 'symlink a link.txt to a target.txt' changed 'symlink a link.txt to a target.txt')"
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
    local dir
    tesht.MktempDir dir || return 128  # fatal if can't make dir
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
    local want=$(IFS='*'; echo "*${wants[*]}*")
    [[ $got == $want ]] || {
      echo "${NL}task.Ln: got doesn't match want:$NL$(tesht.Diff "$got" "$want")$NL"
      echo "use this line to update want to match this output:${NL}want=${got@Q}"
      return 1
    }
  }

  local failed=0 casename
  for casename in ${!case@}; do
    tesht.Run $casename || {
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
  git init -b main clone
  cd clone
  git config user.email "test@test"
  git config user.name "test"
  git config commit.gpgsign false
  echo hello >hello.txt
  git add hello.txt
  git commit -m init
) >/dev/null
