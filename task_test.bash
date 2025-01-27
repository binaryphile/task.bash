source ./task.bash

# test_task.curl tests whether the curl download task receives a file from a local test http server.
# It does its work in a directory it creates in /tmp.
test_task.curl() {
  ## arrange

  want='[begin]		curl http://127.0.0.1:8000/src.txt >dst.txt
[changed]	curl http://127.0.0.1:8000/src.txt >dst.txt'

  # temporary directory
  dir=$(mktemp -d /tmp/tesht.XXXXXX)
  [[ $dir == /tmp/tesht.* ]] || { echo "task.curl couldn't create temp directory"; return 1; }
  trapcmd="rm -rf $dir"
  trap $trapcmd EXIT        # always clean up
  cd $dir

  # create the downloadable file
  echo 'hello there' >src.txt

  # start the http server, redirect stdout so the test doesn't hang
  pid=$(python3 -m http.server 8000 --bind 127.0.0.1 &>/dev/null& echo $!)
  trapcmd="kill $pid >/dev/null; $trapcmd"
  trap $trapcmd EXIT  # always clean up
  sleep 0.1           # give python time to start (double the minimum I tested)

  ## act

  # run the command and capture the output and result code
  got=$(task.curl http://127.0.0.1:8000/src.txt dst.txt 2>&1)
  rc=$?

  ## assert

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
  local -A testcase1=(
    [name]=basic
    [args]='target.txt link.txt'
    [want]='[begin]		create symlink - target.txt link.txt
[changed]	create symlink - target.txt link.txt'
  )

  local -A testcase2=(
    [name]='fail on link creation'
    [args]='target.txt /mnt/chromeos/MyFiles/Downloads/crostini/link.txt'
    [wanterr]=1
  )

  # subtest runs each subtest.
  # testcase is expected to be the name of an associative array holding at least the key "name".
  # Each subtest that needs a directory creates it in /tmp.
  subtest() {
    testcasename=$1
    eval "$(t.inherit $testcasename)"  # create variables from the keys/values of the test map

    ## arrange

    # temporary directory
    dir=$(mktemp -d /tmp/tesht.XXXXXX)
    [[ $dir == /tmp/tesht.* ]] || { echo "    task.ln/$name fatal: couldn't create temp directory"; return 1; }
    trap "rm -rf $dir" EXIT # always clean up
    cd $dir

    # set positional args for command
    eval "set -- $args"

    ## act

    # run the command and capture the output and result code
    got=$(task.ln $* 2>&1)
    rc=$?

    ## assert

    # if this is a test for error behavior, check it
    [[ -v wanterr ]] && {
      (( rc == wanterr )) && return
      echo -e "    task.ln/$name error = $rc, want: $wanterr\n$got"
      return 1
    }

    # assert no error
    (( rc == 0 )) || {
      echo -e "    task.ln/$name error = $rc, want: 0\n$got"
      return 1
    }

    # assert that the symlink was made
    [[ -L $2 ]] || {
      echo -e "    task.ln/$name expected $2 to be symlink\n$got"
      return 1
    }

    # assert that we got the wanted output
    [[ $got == "$want" ]] || {
      echo -e "    task.ln/$name got doesn't match want:\n$(t.diff "$got" "$want")"
      return 1
    }
  }

  failed=0
  for testcasename in testcase{1,2}; do
    t.run subtest $testcasename || failed=1
  done

  return $failed
}

# test_task.git_clone tests whether git cloning works with github.
# It does its work in a directory it creates in /tmp.
test_task.git_clone() {
  ## arrange

  want='[begin]		git clone https://github.com/binaryphile/task.bash task.bash
[changed]	git clone https://github.com/binaryphile/task.bash task.bash'

  # temporary directory
  dir=$(mktemp -d /tmp/tesht.XXXXXX)
  [[ $dir == /tmp/tesht.* ]] || { echo "task.git_clone fatal: couldn't create temp directory"; return 1; }
  trapcmd="rm -rf $dir"
  trap $trapcmd EXIT        # always clean up
  cd $dir

  ## act

  # run the command and capture the output and result code
  got=$(task.git_clone https://github.com/binaryphile/task.bash task.bash 2>&1)
  rc=$?

  ## assert

  # assert no error
  (( rc == 0 )) || {
    echo -e "task.git_clone error = $rc, want: 0\n$got"
    return 1
  }

  # assert that the repo was cloned
  [[ -e task.bash/.git ]] || {
    echo -e "task.git_clone expected .git directory.\n$got"
    return 1
  }

  # assert that we got the wanted output
  [[ $got == "$want" ]] || {
    echo -e "task.git_clone got doesn't match want:\n$(t.diff "$got" "$want")"
    return 1
  }
}
