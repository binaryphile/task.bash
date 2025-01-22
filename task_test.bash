source ./task.bash

Test_task.ln() {
  local -A test1=(
    [name]='basic'
    [args]='filename "$dir"filename'
    [dir]='$(mktemp -d /tmp/test.XXXXXX)/'
    [want]='[begin]		create symlink - filename "$dir"filename
[changed]	create symlink - filename "$dir"filename'
  )

  local -A test2=(
    [name]='fail on link creation'
    [args]='filename /mnt/chromeos/MyFiles/Downloads/crostini/filename'
    [wanterr]=1
  )

  testbody() {
    eval "$(TestInheritMap $1)"
    [[ -v dir ]] && {
      eval "dir=\"$dir\""
      trap "rm -rf $dir" EXIT
    }
    eval "set -- $args"

    got=$(task.ln $1 $2 2>&1) && rc=$? || rc=$?

    [[ -v wanterr ]] && {
      (( rc == wanterr )) && return
      echo -e "task.ln error = $rc, want: $wanterr\n$got"
      return 1
    }

    (( rc == 0 )) || {
      echo -e "task.ln error = $rc, want: 0\n$got"
      return 1
    }

    [[ -L $2 ]] || {
      echo -e "task.ln expected $2 to be symlink\n$got"
      return 1
    }

    eval "want=\"$want\""
    [[ $got == "$want" ]] || {
      echo -e "task.ln got doesn't match want:\n$(TestDiff "$got" "$want")"
      return 1
    }
  }

  failed=0
  for test in test1 test2; do
    TestRun testbody $test || failed=1
  done

  return $failed
}
