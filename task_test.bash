source ./task.bash

# Enable safe expansion (test consumer of task.bash; library doesn't force
# discipline per bash style guide §1 "libraries should not force strict mode").
IFS=$'\n'
set -o noglob

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

  # case4 + case5: gate on TTY availability (#19448). Override task.hasTty to
  # force the no-TTY branch portably -- the override is scoped to the subshell
  # tesht runs each subtest in. Pre-fix: tee /dev/tty fails with rc=1, cmd
  # mis-reports [failed] for a successful wrapped command.
  local -A case4=(
    [name]='prog on without TTY: success rc preserved (#19448)'

    [command]="cmd 'echo hello'"
    [prog]=on
    [hasTty]=no
    [wants]="(changed 'prog on without TTY: success rc preserved (#19448)')"
  )

  local -A case5=(
    [name]='prog on without TTY: failure rc preserved (#19448)'

    [command]="cmd 'false'"
    [prog]=on
    [hasTty]=no
    [wanterr]=1
    [wants]="(failed 'prog on without TTY: failure rc preserved (#19448)')"
  )

  # case6 exercises the live-tee branch (hasTty=yes) with tee mocked to fail
  # at runtime. Verifies PIPESTATUS[0] preserves the wrapped command's rc
  # even when tee aborts mid-pipeline -- closes the regression-hole that
  # case4/case5 leave open (a future revert of the gating would only surface
  # in non-TTY environments, but case6 catches it regardless of host TTY
  # state because tee itself is shadowed). See UC-4 Extension 2b (#19448).
  local -A case6=(
    [name]='prog on with TTY: tee runtime failure rc preserved (#19448)'

    [command]="cmd 'echo hello'"
    [prog]=on
    [hasTty]=yes
    [teeFails]=yes
    [wants]="(changed 'prog on with TTY: tee runtime failure rc preserved (#19448)')"
  )

  # subtest runs each subtest.
  # casename is expected to be the name of an associative array holding at least the key "name".
  subtest() {
    local casename=$1

    ## arrange

    # create variables from the keys/values of the test map
    unset -v ok shortrun prog unchg want wanterr hasTty teeFails  # unset optional fields
    eval "$(tesht.Inherit $casename)"

    desc $name  # desc resets the environment so make other changes after

    [[ -v ok        ]] && ok $ok
    [[ -v prog      ]] && prog $prog
    [[ -v shortrun  ]] && task.SetShortRun $shortrun
    [[ -v unchg     ]] && unchg $unchg
    [[ -v hasTty && $hasTty == no  ]] && task.hasTty() { return 1; }
    [[ -v hasTty && $hasTty == yes ]] && task.hasTty() { return 0; }
    [[ -v teeFails && $teeFails == yes ]] && tee() { return 1; }

    ## act

    # run the command and capture the output and result code
    local got rc
    got=$(eval $command 2>&1) && rc=$? || rc=$?

    ## assert

    # assert wanted rc (default 0; cases expecting non-zero set [wanterr]=N)
    local wantrc=${wanterr:-0}
    (( rc == wantrc )) || {
      echo "${NL}cmd: error = $rc, want: $wantrc$NL$got"
      return 1
    }

    # assert that we got the wanted output
    local want=$(IFS='*'; echo "*${wants[*]}*")
    [[ $got == $want ]] || {
      echo "${NL}cmd: got doesn't match want:$NL$(tesht.Diff $got $want 1)$NL"
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

    eval "$(tesht.Inherit $casename)"

    ## act

    local got rc

    case $name in
      'failing command shows tried and returns 0' )
        failingTask() {
          desc $name
          ok false
          cmd false
        }
        got=$(try failingTask 2>&1) && rc=$? || rc=$?
        ;;

      'succeeding command works normally under try' )
        succeedingTask() {
          desc $name
          ok '[[ -e / ]]'
          cmd true
        }
        got=$(try succeedingTask 2>&1) && rc=$? || rc=$?
        ;;

      'subsequent cmd skipped after try failure' )
        multiCmdTask() {
          desc $name
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
          desc $name
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
      echo "${NL}try: got doesn't match want:$NL$(tesht.Diff $got $want 1)$NL"
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
  cd $dir

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
    echo "${NL}task.GitClone: got doesn't match want:$NL$(tesht.Diff $got $want)$NL"
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
    eval "$(tesht.Inherit $casename)"

    ## act

    # run the command and capture the output and result code
    local got rc
    got=$(task.Ln $targetname $linkname 2>&1) && rc=$? || rc=$?

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
      echo "${NL}task.Ln: got doesn't match want:$NL$(tesht.Diff $got $want)$NL"
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

# Contract: pre-existing absolute symlink pointing at the wrong target gets
# repaired to the declared target. Hardened predicate detects the mismatch
# (literal readlink equality fails), cmd removes the wrong link and creates
# the right one. Exit 0, output reports [changed].
test_task.Ln_wrong_target_absolute_repairs() {
  ## arrange
  local dir
  tesht.MktempDir dir || return 128
  echo correct > "$dir/correct.txt"
  echo wrong > "$dir/wrong.txt"
  ln -s "$dir/wrong.txt" "$dir/link"

  ## act
  local got rc
  got=$(task.Ln "$dir/correct.txt" "$dir/link" 2>&1) && rc=$? || rc=$?

  ## assert
  (( rc == 0 )) || {
    echo "${NL}task.Ln: error = $rc, want: 0$NL$got"
    return 1
  }
  local actual
  actual=$(readlink "$dir/link")
  [[ $actual == "$dir/correct.txt" ]] || {
    echo "${NL}task.Ln: readlink = $actual, want $dir/correct.txt$NL$got"
    return 1
  }
  [[ $got == *changed* ]] || {
    echo "${NL}task.Ln: expected [changed] event in output$NL$got"
    return 1
  }
}

# Contract: pre-existing dangling absolute symlink (link exists, source
# missing) and task.Ln re-invoked with the SAME absolute target — predicate
# fails source-existence check, cmd refuses to recreate. Exit 1, link
# unchanged (still dangling).
test_task.Ln_dangling_absolute_refuses() {
  ## arrange
  local dir
  tesht.MktempDir dir || return 128
  # Pre-existing dangling link: target source does not exist
  ln -s "$dir/nonexistent.txt" "$dir/link"

  ## act
  local got rc
  got=$(task.Ln "$dir/nonexistent.txt" "$dir/link" 2>&1) && rc=$? || rc=$?

  ## assert
  (( rc == 1 )) || {
    echo "${NL}task.Ln: error = $rc, want: 1 (refuse on absolute + missing source)$NL$got"
    return 1
  }
  # Link should still exist (cmd refused BEFORE removing) pointing at the
  # same dangling target
  [[ -L $dir/link ]] || {
    echo "${NL}task.Ln: expected $dir/link to still exist as symlink$NL$got"
    return 1
  }
  local actual
  actual=$(readlink "$dir/link")
  [[ $actual == "$dir/nonexistent.txt" ]] || {
    echo "${NL}task.Ln: readlink = $actual, want $dir/nonexistent.txt (unchanged)$NL$got"
    return 1
  }
}

# Contract: no pre-existing link, absolute target source missing — cmd
# refuses to create the dangling link. Exit 1, no link created.
test_task.Ln_missing_absolute_source_refuses() {
  ## arrange
  local dir
  tesht.MktempDir dir || return 128

  ## act
  local got rc
  got=$(task.Ln "$dir/nonexistent.txt" "$dir/link" 2>&1) && rc=$? || rc=$?

  ## assert
  (( rc == 1 )) || {
    echo "${NL}task.Ln: error = $rc, want: 1 (refuse on absolute + missing source)$NL$got"
    return 1
  }
  [[ ! -L $dir/link && ! -e $dir/link ]] || {
    echo "${NL}task.Ln: expected $dir/link to NOT be created$NL$got"
    return 1
  }
}

# Contract: relative targetname creates the link without source-existence
# check, since relative resolution depends on the link's parent directory
# which task.Ln does not navigate. Pressures multiple relative shapes
# (bare-name, ./, ../, subdir/) in a single test to avoid further
# fragmenting the test harness while still pinning each shape's literal
# readlink contract. Bare-name `nix-wrapper` is the highest-volume
# production pattern (bin/{node,npx,...} → nix-wrapper across many
# project repos); the other shapes pin the broader literal-equality
# contract.
test_task.Ln_relative_target_greenfield() {
  local dir
  tesht.MktempDir dir || return 128

  local target linkname got rc actual sanitized failed=0
  for target in nix-wrapper ./foo ../foo subdir/foo; do
    # Sanitize target into a unique linkname per shape.
    sanitized=${target//[\.\/]/_}
    linkname="$dir/link_$sanitized"
    got=$(task.Ln $target $linkname 2>&1) && rc=$? || rc=$?
    (( rc == 0 )) || {
      echo "${NL}task.Ln (shape '$target'): error = $rc, want: 0$NL$got"
      failed=1; continue
    }
    actual=$(readlink $linkname)
    [[ $actual == "$target" ]] || {
      echo "${NL}task.Ln (shape '$target'): readlink = $actual, want literal '$target'$NL$got"
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

  # case5 + case6 (post-condition: HEAD == upstream after rebase, #18218):
  local -A case5=(
    [name]='post-condition passes when rebase brings HEAD forward'
  )

  local -A case6=(
    [name]='post-condition catches silent no-op rebase'
  )

  subtest() {
    local casename=$1

    ## arrange

    eval "$(tesht.Inherit $casename)"

    local dir
    tesht.MktempDir dir || return 128
    cd $dir

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

      'post-condition passes when rebase brings HEAD forward' )
        # Ordinary happy path; verify the new post-condition does not
        # false-positive when rebase advances HEAD to upstream.
        git -C clone -c user.email=test@test -c user.name=test -c commit.gpgsign=false \
          commit --allow-empty -m 'upstream change' >/dev/null 2>&1

        local got_
        got_=$(task.GitUpdate "$dir/local" 2>&1) && rc=$? || rc=$?

        # Assert success (post-condition does not trip).
        (( rc == 0 )) || {
          echo "${NL}GitUpdate post-condition happy: error = $rc, want: 0$NL$got_"
          return 1
        }

        # Assert NO divergence message in output.
        [[ $got_ != *'post-rebase divergence'* ]] || {
          echo "${NL}GitUpdate post-condition happy: false-positive divergence$NL$got_"
          return 1
        }
        ;;

      'post-condition catches silent no-op rebase' )
        # Add an upstream commit so HEAD..@{upstream} is non-zero unless
        # rebase actually advances HEAD.
        git -C clone -c user.email=test@test -c user.name=test -c commit.gpgsign=false \
          commit --allow-empty -m 'upstream change' >/dev/null 2>&1

        # Install a PATH stub for git that intercepts `git rebase` and
        # returns 0 without doing the work. Simulates the silent-no-op
        # failure class the post-condition exists to catch (corrupted
        # tracking ref, race condition where rebase replays onto stale
        # upstream, etc.). All non-rebase git invocations pass through to
        # the real binary. Per tesht.md: this is a thin inter-system
        # boundary stub, not internal mocking.
        local realGit_
        realGit_=$(command -v git)
        mkdir -p stub
        cat > stub/git <<STUB
#!/usr/bin/env bash
for arg; do
  [[ \$arg == rebase ]] && exit 0
done
exec $realGit_ "\$@"
STUB
        chmod +x stub/git
        local oldPath=$PATH
        PATH=$PWD/stub:$PATH

        local got_
        got_=$(task.GitUpdate "$dir/local" 2>&1) && rc=$? || rc=$?
        PATH=$oldPath

        # Assert non-zero return (silent no-op surfaces).
        (( rc != 0 )) || {
          echo "${NL}GitUpdate post-condition no-op: rc=$rc, want non-zero$NL$got_"
          return 1
        }

        # Assert output contains the literal divergence message.
        [[ $got_ == *'post-rebase divergence'* ]] || {
          echo "${NL}GitUpdate post-condition no-op: output missing 'post-rebase divergence'$NL$got_"
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
    eval "$(tesht.Inherit $casename)"

    desc $name
    [[ -v condition  ]] && ok $condition
    [[ -v checkExpr  ]] && check $checkExpr
    [[ -v tryFailed  ]] && TryFailedX=$tryFailed
    [[ -v shortrun   ]] && task.SetShortRun $shortrun
    [[ -v prog       ]] && prog $prog
    [[ -v unchg      ]] && unchg $unchg

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
    eval "$(tesht.Inherit $casename)"

    desc $name
    [[ -v condition ]] && ok $condition
    [[ -v unchg     ]] && unchg $unchg
    OutputX=${output:-}

    ## act
    local got
    got=$(task.classifyResult $rc)

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

## gitUpdateSafe policy

# test_task.gitUpdateSafe verifies the skip-only-on-diverged policy.
# Uses real git repos (integration style): the function calls git subprocesses
# that can't be meaningfully stubbed.
test_task.gitUpdateSafe() {
  local -A case1=(
    [name]='even: safe'
    [scenario]='even'
    [want_rc]=0
  )
  local -A case2=(
    [name]='behind-only: safe'
    [scenario]='behind-only'
    [want_rc]=0
  )
  local -A case3=(
    [name]='ahead-only: safe (rebase is no-op)'
    [scenario]='ahead-only'
    [want_rc]=0
  )
  local -A case4=(
    [name]='diverged: skip with message'
    [scenario]='diverged'
    [want_rc]=1
    [want_msg]='diverged'
  )
  local -A case5=(
    [name]='detached HEAD: skip with message'
    [scenario]='detached-head'
    [want_rc]=1
    [want_msg]='detached HEAD'
  )

  subtest() {
    local casename=$1
    unset -v want_msg
    eval "$(tesht.Inherit $casename)"

    local dir
    tesht.MktempDir dir || return 128

    gitUpdateSafe.setupScenario $dir $scenario

    local got rc
    got=$(task.gitUpdateSafe "$dir/local") && rc=$? || rc=$?

    (( rc == want_rc )) || {
      echo "rc=$rc want=$want_rc output: $got"
      return 1
    }
    [[ -v want_msg ]] || return 0
    [[ $got == *"$want_msg"* ]] || {
      echo "output '$got' missing expected pattern '$want_msg'"
      return 1
    }
  }

  tesht.Run ${!case@}
}

# gitUpdateSafe.setupScenario creates a bare remote + local clone in $dir,
# then sets up the requested git scenario.
# All git output suppressed so test output stays clean.
gitUpdateSafe.setupScenario() {
  local dir=$1 scenario=$2
  (
    cd $dir
    git init --bare remote
    git clone remote local
    cd local
    git config user.email 'test@test'
    git config user.name  'test'
    git config commit.gpgsign false
    echo init > file.txt
    git add file.txt
    git commit -m 'init'
    git push

    case $scenario in
      even) ;;

      ahead-only)
        echo ahead > file.txt
        git add file.txt
        git commit -m 'local commit'
        ;;

      behind-only)
        cd $dir
        git clone remote other
        cd other
        git config user.email 'test@test'
        git config user.name  'test'
        git config commit.gpgsign false
        echo behind > file.txt
        git add file.txt
        git commit -m 'remote commit'
        git push
        cd "$dir/local"
        git fetch
        ;;

      diverged)
        echo ahead > file.txt
        git add file.txt
        git commit -m 'local commit'
        cd $dir
        git clone remote other
        cd other
        git config user.email 'test@test'
        git config user.name  'test'
        git config commit.gpgsign false
        echo diverged > file.txt
        git add file.txt
        git commit -m 'remote commit'
        git push
        cd "$dir/local"
        git fetch
        ;;

      detached-head)
        git checkout --detach HEAD
        ;;
    esac
  ) >/dev/null 2>&1
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
