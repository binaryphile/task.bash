source ./task.bash

# test_task.curl tests whether the curl download task receives a file from a local test http server.
# It does its work in a directory it creates in /tmp.
test_task.curl() {
  ## arrange

  subject=${FUNCNAME#test_}
  want=$'[begin]		curl http://127.0.0.1:8000/src.txt >dst.txt\n[changed]	curl http://127.0.0.1:8000/src.txt >dst.txt'

  # temporary directory
  dir=$(t.mktempdir) || return  # fail if can't make dir
  trapcmd="rm -rf $dir"
  trap $trapcmd EXIT            # always clean up
  cd $dir

  # create the downloadable file
  echo 'hello there' >src.txt

  # start the http server, redirect stdout so the test doesn't hang
  pid=$(python3 -m http.server 8000 --bind 127.0.0.1 &>/dev/null & echo $!)
  trapcmd="kill $pid >/dev/null; $trapcmd"
  trap $trapcmd EXIT  # always clean up

  ## act

  # run the command and capture the output and result code
  for duration in 0.1 0.2 0.4; do   # retry
    sleep $duration
    got=$($subject http://127.0.0.1:8000/src.txt dst.txt 2>&1)
    rc=$?
    (( rc == 0 )) && break
  done

  ## assert

  # assert no error
  (( rc == 0 )) || {
    echo -e "$subject() error = $rc, want: 0\n$got"
    return 1
  }

  # assert that the file was downloaded
  [[ $(<src.txt) == $(<dst.txt) ]] || {
    echo -e "$subject() expected file contents to match.\n$got"
    return 1
  }

  # assert that we got the wanted output
  [[ $got == "$want" ]] || {
    echo -e "$subject() got doesn't match want:\n$(t.diff "$got" "$want")"
    return 1
  }
}

# test_task.ln tests whether the symlink task works.
# There are subtests for link creation and when link creation fails.
# Subtests are run with t.run.
test_task.ln() {
  subject=${FUNCNAME#test_}

  local -A case1=(
    [name]='basic'
    [args]='target.txt link.txt'
    [want]=$'[begin]		create symlink - target.txt link.txt\n[changed]	create symlink - target.txt link.txt'
  )

  local -A case2=(
    [name]='fail on link creation'
    [args]='target.txt /mnt/chromeos/MyFiles/Downloads/crostini/link.txt'
    [wanterr]=1
  )

  # subtest runs each subtest.
  # subject is the parent function name.
  # case is expected to be the name of an associative array holding at least the key "name".
  # Each subtest that needs a directory creates it in /tmp.
  subtest() {
    ## arrange

    # create variables from the keys/values of the test map
    casename=$2
    eval "$(t.inherit $casename)"

    subject=$1
    name="    $subject/$name()"

    # temporary directory
    dir=$(t.mktempdir) || return  # fail if can't make dir
    trap "rm -rf $dir" EXIT       # always clean up
    cd $dir

    # set positional args for command
    eval "set -- $args"

    ## act

    # run the command and capture the output and result code
    got=$($subject $* 2>&1)
    rc=$?

    ## assert

    # if this is a test for error behavior, check it
    [[ -v wanterr ]] && {
      (( rc == wanterr )) && return

      echo -e "$name error = $rc, want: $wanterr\n$got"
      return 1
    }

    # assert no error
    (( rc == 0 )) || {
      echo -e "$name error = $rc, want: 0\n$got"
      return 1
    }

    # assert that the symlink was made
    [[ -L $2 ]] || {
      echo -e "$name expected $2 to be symlink\n$got"
      return 1
    }

    # assert that we got the wanted output
    [[ $got == "$want" ]] || {
      echo -e "$name got doesn't match want:\n$(t.diff "$got" "$want")"
      return 1
    }
  }

  failed=0
  for casename in ${!case@}; do
    t.run subtest $subject $casename || failed=1
  done

  return $failed
}

# test_task.mkdir tests whether a directory is made.
# It does its work in a directory it creates in /tmp.
test_task.mkdir() {
  ## arrange

  subject=${FUNCNAME#test_}
  want=$'[begin]		mkdir -p mydir\n[changed]	mkdir -p mydir'

  # temporary directory
  dir=$(t.mktempdir) || return  # fail if can't make dir
  trap "rm -rf $dir" EXIT       # always clean up
  cd $dir

  ## act

  # run the command and capture the output and result code
  got=$($subject mydir 2>&1)
  rc=$?

  ## assert

  # assert no error
  (( rc == 0 )) || {
    echo -e "$subject error = $rc, want: 0\n$got"
    return 1
  }

  # assert that the directory was made
  [[ -d mydir ]] || {
    echo -e "$subject expected directory mydir.\n$got"
    return 1
  }

  # assert that we got the wanted output
  [[ $got == "$want" ]] || {
    echo -e "$subject got doesn't match want:\n$(t.diff "$got" "$want")"
    return 1
  }
}

# test_task.git_clone tests whether git cloning works with github.
# It does its work in a directory it creates in /tmp.
test_task.git_clone() {
  ## arrange

  subject=${FUNCNAME#test_}
  want=$'[begin]		git clone https://github.com/binaryphile/task.bash task.bash\n[changed]	git clone https://github.com/binaryphile/task.bash task.bash'

  # temporary directory
  dir=$(t.mktempdir) || return  # fail if can't make dir
  trap "rm -rf $dir" EXIT       # always clean up
  cd $dir

  ## act

  # run the command and capture the output and result code
  got=$($subject https://github.com/binaryphile/task.bash task.bash 2>&1)
  rc=$?

  ## assert

  # assert no error
  (( rc == 0 )) || {
    echo -e "$subject error = $rc, want: 0\n$got"
    return 1
  }

  # assert that the repo was cloned
  [[ -e task.bash/.git ]] || {
    echo -e "$subject expected .git directory.\n$got"
    return 1
  }

  # assert that we got the wanted output
  [[ $got == "$want" ]] || {
    echo -e "$subject got doesn't match want:\n$(t.diff "$got" "$want")"
    return 1
  }
}
