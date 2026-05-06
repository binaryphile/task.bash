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

# test_task.GitUpdate tests git update with fetch+rebase and untracked conflict stashing.
# Subtests cover: happy path, untracked conflict, restore after failure, no-conflict passthrough.
test_task.GitUpdate() {
  local -A case1=(
    [name]='happy path with upstream changes'
  )

  local -A case2=(
    [name]='untracked file conflict resolved by stash'
  )

  local -A case3=(
    [name]='restore after rebase failure'
  )

  local -A case4=(
    [name]='unrelated untracked files untouched'
  )

  subtest() {
    local casename=$1

    ## arrange

    eval "$(tesht.Inherit "$casename")"

    local dir
    tesht.MktempDir dir || return 128
    cd "$dir"

    # Create "remote" repo and clone it.
    createCloneRepo
    git clone clone local >/dev/null 2>&1
    cd local
    git config user.email "test@test"
    git config user.name "test"
    git config commit.gpgsign false
    cd ..

    local got rc

    case $name in
      'happy path with upstream changes' )
        # Add a commit to the remote.
        git -C clone -c user.email=test@test -c user.name=test -c commit.gpgsign=false \
          commit --allow-empty -m 'upstream change' >/dev/null 2>&1

        got=$(task.GitUpdate "$dir/local" 2>&1) && rc=$? || rc=$?

        # Assert success.
        (( rc == 0 )) || {
          echo "${NL}GitUpdate happy: error = $rc, want: 0$NL$got"
          return 1
        }

        # Assert upstream commit is present.
        git -C local log --oneline | grep -q 'upstream change' || {
          echo "${NL}GitUpdate happy: upstream commit not found$NL$got"
          return 1
        }
        ;;

      'untracked file conflict resolved by stash' )
        # Remote adds a tracked bin/node.
        mkdir -p clone/bin
        echo '#!/bin/sh' >clone/bin/node
        git -C clone add bin/node
        git -C clone -c user.email=test@test -c user.name=test -c commit.gpgsign=false \
          commit -m 'add bin/node' >/dev/null 2>&1

        # Local has an untracked bin/node symlink (scaffold artifact).
        mkdir -p local/bin
        ln -s nix-wrapper local/bin/node
        echo '/bin' >>local/.git/info/exclude

        got=$(task.GitUpdate "$dir/local" 2>&1) && rc=$? || rc=$?

        # Assert success.
        (( rc == 0 )) || {
          echo "${NL}GitUpdate conflict: error = $rc, want: 0$NL$got"
          return 1
        }

        # Assert bin/node is still a symlink (not the upstream file).
        [[ -L local/bin/node ]] || {
          echo "${NL}GitUpdate conflict: bin/node is not a symlink$NL$got"
          return 1
        }
        ;;

      'restore after rebase failure' )
        # Create a tracked file in both remote and local with conflicting content.
        echo 'remote content' >clone/conflict.txt
        git -C clone add conflict.txt
        git -C clone -c user.email=test@test -c user.name=test -c commit.gpgsign=false \
          commit -m 'add conflict.txt' >/dev/null 2>&1

        # Local diverges: create the same file with different content and commit.
        echo 'local content' >local/conflict.txt
        git -C local add conflict.txt
        git -C local -c user.email=test@test -c user.name=test -c commit.gpgsign=false \
          commit -m 'local conflict.txt' >/dev/null 2>&1

        # Also add an untracked scaffold file that collides with something upstream will add.
        # We need a second remote commit for this.
        mkdir -p clone/bin
        echo '#!/bin/sh' >clone/bin/tool
        git -C clone add bin/tool
        git -C clone -c user.email=test@test -c user.name=test -c commit.gpgsign=false \
          commit -m 'add bin/tool' >/dev/null 2>&1

        mkdir -p local/bin
        ln -s nix-wrapper local/bin/tool
        echo '/bin' >>local/.git/info/exclude

        got=$(try task.GitUpdate "$dir/local" 2>&1) && rc=$? || rc=$?

        # Assert try succeeded (try always returns 0).
        (( rc == 0 )) || {
          echo "${NL}GitUpdate restore: try error = $rc, want: 0$NL$got"
          return 1
        }

        # Assert scaffold file was restored (even though rebase failed).
        [[ -L local/bin/tool ]] || {
          echo "${NL}GitUpdate restore: bin/tool symlink not restored$NL$got"
          return 1
        }

        # Clean up rebase state for test teardown.
        git -C local rebase --abort 2>/dev/null || true
        ;;

      'unrelated untracked files untouched' )
        # Remote adds a commit (no bin/ files).
        git -C clone -c user.email=test@test -c user.name=test -c commit.gpgsign=false \
          commit --allow-empty -m 'upstream change' >/dev/null 2>&1

        # Local has an untracked file that does NOT conflict with upstream.
        echo 'my notes' >local/scratch.txt

        got=$(task.GitUpdate "$dir/local" 2>&1) && rc=$? || rc=$?

        # Assert success.
        (( rc == 0 )) || {
          echo "${NL}GitUpdate passthrough: error = $rc, want: 0$NL$got"
          return 1
        }

        # Assert unrelated file was not moved/modified.
        [[ -f local/scratch.txt ]] || {
          echo "${NL}GitUpdate passthrough: scratch.txt missing$NL$got"
          return 1
        }
        [[ $(cat local/scratch.txt) == 'my notes' ]] || {
          echo "${NL}GitUpdate passthrough: scratch.txt content changed$NL$got"
          return 1
        }
        ;;
    esac
  }

  local failed=0 casename
  for casename in ${!case@}; do
    tesht.Run $casename || {
      (( $? == 128 )) && return 128
      failed=1
    }
  done

  return $failed
}

# test_task.classify tests the pre-execution classification logic.
test_task.classify() {
  local -A case1=(
    [name]='skipping when TryFailedX is set'
    [tryFailed]=1
    [wants]=skipping
  )

  local -A case2=(
    [name]='ok when condition is met'
    [condition]='true'
    [wants]=ok
  )

  local -A case3=(
    [name]='check_failed when check fails'
    [condition]='false'
    [checkExpr]='false'
    [wants]=check_failed
  )

  local -A case4=(
    [name]='shortrun_skip when short run and unchg set'
    [shortrun]=on
    [unchg]=anything
    [wants]=shortrun_skip
  )

  local -A case5=(
    [name]='shortrun_skip when short run and progress set'
    [shortrun]=on
    [prog]=on
    [wants]=shortrun_skip
  )

  local -A case6=(
    [name]='run when nothing blocks'
    [wants]=run
  )

  local -A case7=(
    [name]='run when condition not met and no check'
    [condition]='false'
    [wants]=run
  )

  local -A case8=(
    [name]='run when short run but no unchg or progress'
    [shortrun]=on
    [wants]=run
  )

  subtest() {
    local casename=$1

    ## arrange
    unset -v condition checkExpr tryFailed shortrun prog unchg
    eval "$(tesht.Inherit "$casename")"

    desc "$name"
    [[ -v condition  ]] && ok "$condition"
    [[ -v checkExpr  ]] && check "$checkExpr"
    [[ -v tryFailed  ]] && TryFailedX=$tryFailed
    [[ -v shortrun   ]] && task.SetShortRun "$shortrun"
    [[ -v prog       ]] && prog "$prog"
    [[ -v unchg      ]] && unchg "$unchg"

    ## act
    local got
    got=$(task.classify)

    ## assert
    [[ $got == "$wants" ]] || {
      echo "${NL}classify: got=$got, want=$wants"
      return 1
    }
  }

  local failed=0 casename
  for casename in ${!case@}; do
    tesht.Run $casename || {
      (( $? == 128 )) && return 128
      failed=1
    }
  done

  return $failed
}

# test_task.classifyResult tests the post-execution classification logic.
test_task.classifyResult() {
  local -A case1=(
    [name]='ok when unchg text found in output'
    [unchg]='up to date'
    [output]='Already up to date.'
    [rc]=0
    [wants]=ok
  )

  local -A case2=(
    [name]='changed when rc=0 and condition met'
    [condition]='true'
    [rc]=0
    [wants]=changed
  )

  local -A case3=(
    [name]='failed when rc!=0'
    [rc]=1
    [wants]=failed
  )

  local -A case4=(
    [name]='failed when rc=0 but condition not met'
    [condition]='false'
    [rc]=0
    [wants]=failed
  )

  local -A case5=(
    [name]='unchg takes priority over condition'
    [unchg]='no change'
    [output]='no change detected'
    [condition]='false'
    [rc]=0
    [wants]=ok
  )

  subtest() {
    local casename=$1

    ## arrange
    unset -v condition unchg output
    eval "$(tesht.Inherit "$casename")"

    desc "$name"
    [[ -v condition ]] && ok "$condition"
    [[ -v unchg     ]] && unchg "$unchg"
    OutputX=${output:-}

    ## act
    local got
    got=$(task.classifyResult "$rc")

    ## assert
    [[ $got == "$wants" ]] || {
      echo "${NL}classifyResult: got=$got, want=$wants"
      return 1
    }
  }

  local failed=0 casename
  for casename in ${!case@}; do
    tesht.Run $casename || {
      (( $? == 128 )) && return 128
      failed=1
    }
  done

  return $failed
}

# test_task.gitUpdateSafe tests the preflight safety check for git update.
test_task.gitUpdateSafe() {
  local -A case1=(
    [name]='safe when on branch with upstream and not ahead'
  )

  local -A case2=(
    [name]='blocks on detached HEAD'
  )

  local -A case3=(
    [name]='blocks when ahead of upstream'
  )

  local -A case4=(
    [name]='blocks when no upstream tracking'
  )

  subtest() {
    local casename=$1

    ## arrange
    eval "$(tesht.Inherit "$casename")"

    local dir
    tesht.MktempDir dir || return 128
    cd "$dir"

    createCloneRepo
    git clone clone local >/dev/null 2>&1
    (cd local && git config user.email t@t && git config user.name t && git config commit.gpgsign false)

    local got rc

    case $name in
      'safe when on branch with upstream and not ahead' )
        got=$(task.gitUpdateSafe "$dir/local" 2>&1) && rc=$? || rc=$?
        (( rc == 0 )) || {
          echo "${NL}gitUpdateSafe: expected rc=0, got rc=$rc$NL$got"
          return 1
        }
        ;;

      'blocks on detached HEAD' )
        git -C local checkout --detach >/dev/null 2>&1
        got=$(task.gitUpdateSafe "$dir/local" 2>&1) && rc=$? || rc=$?
        (( rc != 0 )) || {
          echo "${NL}gitUpdateSafe: expected nonzero rc for detached HEAD"
          return 1
        }
        [[ $got == *'detached HEAD'* ]] || {
          echo "${NL}gitUpdateSafe: expected 'detached HEAD' in output, got: $got"
          return 1
        }
        ;;

      'blocks when ahead of upstream' )
        git -C local commit --allow-empty -m 'local commit' >/dev/null 2>&1
        got=$(task.gitUpdateSafe "$dir/local" 2>&1) && rc=$? || rc=$?
        (( rc != 0 )) || {
          echo "${NL}gitUpdateSafe: expected nonzero rc when ahead"
          return 1
        }
        [[ $got == *'unpushed'* ]] || {
          echo "${NL}gitUpdateSafe: expected 'unpushed' in output, got: $got"
          return 1
        }
        ;;

      'blocks when no upstream tracking' )
        git -C local branch --unset-upstream >/dev/null 2>&1
        got=$(task.gitUpdateSafe "$dir/local" 2>&1) && rc=$? || rc=$?
        (( rc != 0 )) || {
          echo "${NL}gitUpdateSafe: expected nonzero rc when no upstream"
          return 1
        }
        [[ $got == *'no upstream'* ]] || {
          echo "${NL}gitUpdateSafe: expected 'no upstream' in output, got: $got"
          return 1
        }
        ;;
    esac
  }

  local failed=0 casename
  for casename in ${!case@}; do
    tesht.Run $casename || {
      (( $? == 128 )) && return 128
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
