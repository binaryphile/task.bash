source ./task.bash

Test_task.curl() {
    name='basic'
    args='http://127.0.0.1/$filename "$dir"downloadedfile'
    filename='filename'
    filecontent='hello there'
    dir=$(mktemp -d /tmp/test.XXXXXX)/
    want='[begin]		curl filename >"$dir"filename
[changed]	curl filename >"$dir"filename'

    # arrange

    # temporary directory
    [[ $dir == /*/*/ ]]       # assert we got a directory
    trap "rm -rf $dir" EXIT   # always clean up

    # set positional arguments for the command, expanding variables
    eval "set -- $args"

    # create the downloadable file
    echo "$filecontent" >$dir$filename

    # start the http server
    pid=$(cd $dir; python3 -m http.server 8000 --bind 127.0.0.1 >/dev/null& echo $!)
    trap "kill $pid >/dev/null; $(trap -p EXIT)" EXIT   # always clean up

    # act

    # run the command and capture the result code
    got=$(task.curl $1 $2 2>&1) && rc=$? || rc=$?

    # assert

    # flag any error
    (( rc == 0 )) || {
      echo -e "task.curl error = $rc, want: 0\n$got"
      return 1
    }

    # assert that the file was downloaded
    [[ $(<$1) == $(<$2) ]] || {
      echo -e "task.curl expected file contents to match.\n$got"
      return 1
    }

    # assert that we got the wanted output
    eval "want=\"$want\""  # expand $dir
    [[ $got == "$want" ]] || {
      echo -e "task.curl got doesn't match want:\n$(TestDiff "$got" "$want")"
      return 1
    }
}

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
    # arrange

    # create variables from the keys/values of the test map
    eval "$(TestInheritMap $1)"
    [[ -v dir ]] && {
      eval "dir=\"$dir\""     # run mktemp
      [[ $dir == /* ]]        # assert we got a directory
      trap "rm -rf $dir" EXIT # always clean up
    }

    # set positional arguments for the command, expanding $dir
    eval "set -- $args"

    # act

    # run the command and capture the result code
    got=$(task.ln $1 $2 2>&1) && rc=$? || rc=$?

    # assert

    # if this is a test for error behavior, check it
    [[ -v wanterr ]] && {
      (( rc == wanterr )) && return
      echo -e "task.ln error = $rc, want: $wanterr\n$got"
      return 1
    }

    # if not an error test, flag any error
    (( rc == 0 )) || {
      echo -e "task.ln error = $rc, want: 0\n$got"
      return 1
    }

    # assert that the symlink was made
    [[ -L $2 ]] || {
      echo -e "task.ln expected $2 to be symlink\n$got"
      return 1
    }

    # assert that we got the wanted output
    eval "want=\"$want\""   # expand $dir
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
