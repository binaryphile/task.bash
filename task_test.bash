source ./task.bash

# test_each tests the application of a command with no output to a list of invocations from stdin.
# There are subtests that are run with t.run.
test_each() {
  command=${FUNCNAME#test_}

  local -A case1=(
    [name]='puts items in a file as a side effect'
    [args]=$'Hello\nWorld!'
    [lambda]=$(appendToFile out.txt)
    [want]=''
    [wantInFile]=$'Hello\nWorld!'
  )

  # subtest runs each subtest.
  # command is the parent function name.
  # case is expected to be the name of an associative array holding at least the key "name".
  subtest() {
    command=$1 casename=$2

    ## arrange

    # temporary directory
    dir=$(t.mktempdir) || return 128  # fatal if can't make dir
    trap "rm -rf $dir" EXIT           # always clean up
    cd $dir

    # create variables from the keys/values of the test map
    eval "$(t.inherit $casename)"

    ## act

    # run the command and capture the output and result code
    got=$(echo "$args" | $command $lambda 2>&1)
    rc=$?

    ## assert

    # assert no error
    (( rc == 0 )) || {
      echo -e "\t$command: error = $rc, want: 0\n$got"
      return 1
    }

    # assert that the file got the output
    content=$(<out.txt)
    [[ $content == "$wantInFile" ]] || {
      echo -e "\t$command: out.txt content doesn't match wantInFile:\n$(t.diff "$content" "$wantInFile")"
      return 1
    }

    # assert that we got no output
    [[ $got == "$want" ]] || {
      echo -e "\t$command: got doesn't match want:\n$(t.diff "$got" "$want")"
      return 1
    }
  }

  failed=0
  for casename in ${!case@}; do   # ${!case@} lists all variable names starting with "case"
    t.run subtest $command $casename || {
      (( $? == 128 )) && return   # fatal
      failed=1
    }
  done

  return $failed
}

# test_glob tests
# There are subtests that are run with t.run.
test_glob() {
  command=${FUNCNAME#test_}

  local -A case1=(
    [name]='generates a list of two items'
    [pattern]='*'
    [filenames]=$'file1\nfile2'
    [want]=$'file1\nfile2'
  )

  local -A case2=(
    [name]='returns an empty list'
    [pattern]='*'
    [want]=''
  )

  # subtest runs each subtest.
  # command is the parent function name.
  # case is expected to be the name of an associative array holding at least the key "name".
  subtest() {
    local command=$1 casename=$2

    ## arrange

    # temporary directory
    dir=$(t.mktempdir) || return 128  # fatal if can't make dir
    trap "rm -rf $dir" EXIT           # always clean up
    cd $dir

    # create variables from the keys/values of the test map
    unset -v filenames  # necessary for testing for existence with -v
    eval "$(t.inherit $casename)"

    # create files if requested
    [[ -v filenames ]] && echo "$filenames" | each 'echo >'

    ## act

    # run the command and capture the output and result code
    got=$($command $pattern 2>&1)
    rc=$?

    ## assert

    # assert no error
    (( rc == 0 )) || {
      echo -e "\t$command: error = $rc, want: 0\n$got"
      return 1
    }

    # assert that we got expected output
    [[ $got == "$want" ]] || {
      echo -e "\t$command: got doesn't match want:\n$(t.diff "$got" "$want")"
      return 1
    }
  }

  failed=0
  for casename in ${!case@}; do   # ${!case@} lists all variable names starting with "case"
    t.run subtest $command $casename || {
      (( $? == 128 )) && return   # fatal
      failed=1
    }
  done

  return $failed
}

# test_map tests the application of an expression to a list of invocations from stdin.
# There are subtests that are run with t.run.
test_map() {
  command=${FUNCNAME#test_}

  local -A case1=(
    [name]='basic'
    [args]=$'Hello\nWorld!'
    [varname]='target'
    [expression]='[$target]'
    [want]=$'[Hello]\n[World!]'
  )

  # subtest runs each subtest.
  # command is the parent function name.
  # case is expected to be the name of an associative array holding at least the key "name".
  subtest() {
    command=$1 casename=$2

    ## arrange
    # create variables from the keys/values of the test map
    eval "$(t.inherit $casename)"

    ## act

    # run the command and capture the output and result code
    got=$($command $varname $expression <<<"$args" 2>&1)
    rc=$?

    ## assert

    # assert no error
    (( rc == 0 )) || {
      echo -e "\t$command: error = $rc, want: 0\n$got"
      return 1
    }

    # assert that we got the wanted output
    [[ $got == "$want" ]] || {
      echo -e "\t$command: got doesn't match want:\n$(t.diff "$got" "$want")"
      return 1
    }
  }

  failed=0
  for casename in ${!case@}; do
    t.run subtest $command $casename || {
      (( $? == 128 )) && return   # fatal
      failed=1
    }
  done

  return $failed
}

# test_task.curl tests whether the curl download task receives a file from a local test http server.
# It does its work in a directory it creates in /tmp.
test_task.curl() {
  command=${FUNCNAME#test_}

  ## arrange

  # temporary directory
  dir=$(t.mktempdir) || return 128  # fatal
  trapcmd="rm -rf $dir"
  trap $trapcmd EXIT  # always clean up
  cd $dir

  # create the downloadable file
  echo 'hello there' >src.txt

  pid=$(t.start_http_server) || { echo $pid; return 128; }  # if fatal pid is the error message
  trapcmd="kill $pid >/dev/null; $trapcmd"
  trap $trapcmd EXIT  # always clean up

  want=$'[\E[38;5;220mbegin\E[0m]\t\tdownload src.txt from http://127.0.0.1:8000 as dst.txt
[\E[38;5;208mchanged\E[0m]\tdownload src.txt from http://127.0.0.1:8000 as dst.txt'

  ## act

  # run the command and capture the output and result code
  got=$($command http://127.0.0.1:8000/src.txt dst.txt 2>&1)
  rc=$?

  ## assert

  # assert no error
  (( rc == 0 )) || {
    echo -e "$command: error = $rc, want: 0\n$got"
    return 1
  }

  # assert that the file was downloaded
  [[ -f dst.txt && $(<src.txt) == $(<dst.txt) ]] || {
    echo -e "$command: expected file contents to match.\n$got"
    return 1
  }

  # assert that we got the wanted output
  [[ $got == "$want" ]] || {
    echo -e "$command: got doesn't match want:\n$(t.diff "$got" "$want")"
    return 1
  }
}

# test_task.git_clone tests whether git cloning works with github.
# It does its work in a directory it creates in /tmp.
test_task.git_clone() {
  ## arrange

  command=${FUNCNAME#test_}
  want=$'[\E[38;5;220mbegin\E[0m]\t\tclone repo https://github.com/binaryphile/task.bash to task.bash
[\E[38;5;208mchanged\E[0m]\tclone repo https://github.com/binaryphile/task.bash to task.bash'

  # temporary directory
  dir=$(t.mktempdir) || return 128  # fatal if can't make dir
  trap "rm -rf $dir" EXIT           # always clean up
  cd $dir

  # TODO: build and clone local repo instead of from github

  ## act

  # run the command and capture the output and result code
  got=$($command https://github.com/binaryphile/task.bash task.bash 2>&1)
  rc=$?

  ## assert

  # assert no error
  (( rc == 0 )) || {
    echo -e "$command error = $rc, want: 0\n$got"
    return 1
  }

  # assert that the repo was cloned
  [[ -e task.bash/.git ]] || {
    echo -e "$command expected .git directory.\n$got"
    return 1
  }

  # assert that we got the wanted output
  [[ $got == "$want" ]] || {
    echo -e "$command got doesn't match want:\n$(t.diff "$got" "$want")"
    return 1
  }
}

# test_task.ln tests whether the symlink task works.
# There are subtests for link creation and when link creation fails.
# Subtests are run with t.run.
test_task.ln() {
  command=${FUNCNAME#test_}

  local -A case1=(
    [name]='spaces in link and target'
    [targetname]='a\ target.txt'
    [linkname]='a\ link.txt'
    [want]=$'[\E[38;5;220mbegin\E[0m]\t\tsymlink a\\\\ link.txt to a\\\\ target.txt
[\E[38;5;208mchanged\E[0m]\tsymlink a\\\\ link.txt to a\\\\ target.txt'
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
    command=$1 casename=$2

    ## arrange

    # temporary directory
    dir=$(t.mktempdir) || return 128  # fatal if can't make dir
    trap "rm -rf $dir" EXIT           # always clean up
    cd $dir

    # create variables from the keys/values of the test map
    unset -v wanterr  # necessary for testing for existence with -v
    eval "$(t.inherit $casename)"

    ## act

    # run the command and capture the output and result code
    got=$($command $targetname $linkname 2>&1)
    rc=$?

    ## assert

    # if this is a test for error behavior, check it
    [[ -v wanterr ]] && {
      (( rc == wanterr )) && return

      echo -e "\t$command: error = $rc, want: $wanterr\n$got"
      return 1
    }

    # assert no error
    (( rc == 0 )) || {
      echo -e "\t$command: error = $rc, want: 0\n$got"
      return 1
    }

    # assert that the symlink was made
    [[ -L $linkname ]] || {
      echo -e "\t$command: expected $2 to be symlink\n$got"
      return 1
    }

    # assert that we got the wanted output
    [[ $got == "$want" ]] || {
      echo -e "\t$command: got doesn't match want:\n$(t.diff "$got" "$want")"
      return 1
    }
  }

  failed=0
  for casename in ${!case@}; do
    t.run subtest $command $casename || {
      (( $? == 128 )) && return   # fatal
      failed=1
    }
  done

  return $failed
}

# test_task.mkdir tests whether a directory is made.
# It does its work in a directory it creates in /tmp.
test_task.mkdir() {
  ## arrange

  command=${FUNCNAME#test_}
  want=$'[\E[38;5;220mbegin\E[0m]\t\tmake directory a\ dir
[\E[38;5;208mchanged\E[0m]\tmake directory a\ dir'

  # temporary directory
  dir=$(t.mktempdir) || return 128  # fatal if can't make dir
  trap "rm -rf $dir" EXIT           # always clean up
  cd $dir

  ## act

  # run the command and capture the output and result code
  got=$($command 'a dir' 2>&1)
  rc=$?

  ## assert

  # assert no error
  (( rc == 0 )) || {
    echo -e "$command error = $rc, want: 0\n$got"
    return 1
  }

  # assert that the directory was made
  [[ -d 'a dir' ]] || {
    echo -e "$command expected directory a\ dir.\n$got"
    return 1
  }

  # assert that we got the wanted output
  [[ $got == "$want" ]] || {
    echo -e "$command got doesn't match want:\n$(t.diff "$got" "$want")"
    return 1
  }
}

appendToFile() {
  local filename=$1
  echo "_() { echo \$* >>$filename; }; _"
}
