source ./task.bash

# test_task.curl tests whether the curl download task receives a file from a local test http server.
# It does its work in a directory it creates in /tmp.
test_task.curl() {
    dir=$(mktemp -d /tmp/test.XXXXXX)
    args=( http://127.0.0.1:8000/src.txt dst.txt )
    want='[begin]		curl http://127.0.0.1:8000/src.txt >dst.txt
[changed]	curl http://127.0.0.1:8000/src.txt >dst.txt'

    # arrange

    # temporary directory
    [[ $dir == /*/*/ ]]       # assert we got a directory
    trapcmd="rm -rf $dir"
    trap $trapcmd EXIT        # always clean up
    cd $dir

    # create the downloadable file
    echo 'hello there' >src.txt

    # start the http server, redirect stdout so it doesn't hang
    pid=$(python3 -m http.server 8000 --bind 127.0.0.1 &>/dev/null& echo $!)
    trapcmd="kill $pid >/dev/null; $trapcmd"
    trap $trapcmd EXIT  # always clean up
    sleep 0.5           # give python time to start

    # act

    # run the command and capture the output and result code
    got=$(task.curl ${args[*]} 2>&1) && rc=$? || rc=$?

    # assert

    # assert no error
    (( rc == 0 )) || {
      echo -e "task.curl error = $rc, want: 0\n$got"
      return 1
    }

    # assert that the file was downloaded
    [[ $(<src.txt) == $(<dst.txt) ]] || {
      echo -e "task.curl expected file contents to match.\n$got"
      return 1
    }

    # assert that we got the wanted output
    [[ $got == "$want" ]] || {
      echo -e "task.curl got doesn't match want:\n$(t.diff "$got" "$want")"
      return 1
    }
}

# test_task.ln tests whether the symlink task works.
# There are subtests for link creation and when link creation fails.
# Subtests are run with t.run.
test_task.ln() {
  local -A test1=(
    [name]=basic
    [dir]='$(mktemp -d /tmp/test.XXXXXX)'
    [args]='target.txt link.txt'
    [want]='[begin]		create symlink - target.txt link.txt
[changed]	create symlink - target.txt link.txt'
  )

  local -A test2=(
    [name]='fail on link creation'
    [args]='target.txt /mnt/chromeos/MyFiles/Downloads/crostini/link.txt'
    [wanterr]=1
  )

  # testfunc runs each subtest.
  # It expects as $1 the name of an associative array with test parameters of at least "name".
  # Each subtest that needs a directory creates it in /tmp.
  testfunc() {
    # arrange

    # create variables from the keys/values of the test map
    eval "$(t.inherit $1)"

    # temporary directory
    [[ -v dir ]] && {
      eval "dir=\"$dir\""     # run mktemp
      [[ $dir == /*/*/ ]]     # assert we got a directory
      trap "rm -rf $dir" EXIT # always clean up
      cd $dir
    }

    # set positional args for command
    eval "set -- $args"

    # act

    # run the command and capture the result code
    got=$(task.ln $* 2>&1) && rc=$? || rc=$?

    # assert

    # if this is a test for error behavior, check it
    [[ -v wanterr ]] && {
      (( rc == wanterr )) && return
      echo -e "task.ln error = $rc, want: $wanterr\n$got"
      return 1
    }

    # assert no error
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
      echo -e "task.ln got doesn't match want:\n$(t.diff "$got" "$want")"
      return 1
    }
  }

  failed=0
  for test in test1 test2; do
    t.run testfunc $test || failed=1
  done

  return $failed
}
