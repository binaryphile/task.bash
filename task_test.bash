source ./task.bash

# test_each tests the application of a command with no output to a list of invocations from stdin.
# There are subtests that are run with t.run.
test_each() {
  local -A case1=(
    [name]='puts items in a file as a side effect'
    [args]=$'Hello\nWorld!'
    [expression]=$(appendToFile out.txt)
    [want]=''
    [wantInFile]=$'Hello\nWorld!'
  )

  # subtest runs each subtest.
  # command is the parent function name.
  # case is expected to be the name of an associative array holding at least the key "name".
  subtest() {
    local casename=$1

    ## arrange

    # temporary directory
    local dir=$(t.mktempdir) || return 128  # fatal if can't make dir
    trap "rm -rf $dir" EXIT                 # always clean up
    cd $dir

    # create variables from the keys/values of the test map
    eval "$(t.inherit $casename)"

    ## act

    # run the command and capture the output and result code
    local got rc
    got=$(echo "$args" | each $expression 2>&1) && rc=$? || rc=$?

    ## assert

    # assert no error
    (( rc == 0 )) || {
      echo -e "\teach: error = $rc, want: 0\n$got"
      return 1
    }

    # assert that the file got the output
    local content=$(<out.txt)
    [[ $content == "$wantInFile" ]] || {
      echo -e "\teach: out.txt content doesn't match wantInFile:\n$(t.diff "$content" "$wantInFile")"
      return 1
    }

    # assert that we got no output
    [[ $got == "$want" ]] || {
      echo -e "\teach: got doesn't match want:\n$(t.diff "$got" "$want")"
      return 1
    }
  }

  local failed=0 casename
  for casename in ${!case@}; do   # ${!case@} lists all variable names starting with "case"
    t.run subtest test_each $casename || {
      (( $? == 128 )) && return   # fatal
      failed=1
    }
  done

  return $failed
}

# test_glob tests
# There are subtests that are run with t.run.
test_glob() {
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
    local casename=$1

    ## arrange

    # temporary directory
    local dir=$(t.mktempdir) || return 128  # fatal if can't make dir
    trap "rm -rf $dir" EXIT                 # always clean up
    cd $dir

    # create variables from the keys/values of the test map
    unset -v filenames  # necessary for testing for existence with -v
    eval "$(t.inherit $casename)"

    # create files if requested
    [[ -v filenames ]] && echo "$filenames" | each 'echo >'

    ## act

    # run the command and capture the output and result code
    local got rc
    got=$(glob $pattern 2>&1) && rc=$? || rc=$?

    ## assert

    # assert no error
    (( rc == 0 )) || {
      echo -e "\tglob: error = $rc, want: 0\n$got"
      return 1
    }

    # assert that we got expected output
    [[ $got == "$want" ]] || {
      echo -e "\tglob: got doesn't match want:\n$(t.diff "$got" "$want")"
      return 1
    }
  }

  local failed=0 casename
  for casename in ${!case@}; do   # ${!case@} lists all variable names starting with "case"
    t.run subtest test_glob $casename || {
      (( $? == 128 )) && return   # fatal
      failed=1
    }
  done

  return $failed
}

# test_map tests the application of an expression to a list of invocations from stdin.
# There are subtests that are run with t.run.
test_map() {
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
    local casename=$1

    ## arrange
    # create variables from the keys/values of the test map
    eval "$(t.inherit $casename)"

    ## act

    # run the command and capture the output and result code
    local got rc
    got=$(map $varname $expression <<<"$args" 2>&1) && rc=$? || rc=$?

    ## assert

    # assert no error
    (( rc == 0 )) || {
      echo -e "\tmap: error = $rc, want: 0\n$got"
      return 1
    }

    # assert that we got the wanted output
    [[ $got == "$want" ]] || {
      echo -e "\tmap: got doesn't match want:\n$(t.diff "$got" "$want")"
      return 1
    }
  }

  local failed=0 casename
  for casename in ${!case@}; do
    t.run subtest test_map $casename || {
      (( $? == 128 )) && return   # fatal
      failed=1
    }
  done

  return $failed
}

# test_task.curl tests whether the curl download task receives a file from a local test http server.
# It does its work in a directory it creates in /tmp.
test_task.curl() {
  ## arrange

  # temporary directory
  local dir trapcmd
  dir=$(t.mktempdir) || return 128  # fatal
  trapcmd="rm -rf $dir"
  trap $trapcmd EXIT  # always clean up
  cd $dir

  # create the downloadable file
  echo 'hello there' >src.txt

  local pid
  pid=$(t.start_http_server) || { echo $pid; return 128; }  # if fatal pid is the error message
  trapcmd="kill $pid >/dev/null; $trapcmd"
  trap $trapcmd EXIT  # always clean up

  ## act

  # run the command and capture the output and result code
  local got rc
  got=$(task.curl http://127.0.0.1:8000/src.txt dst.txt 2>&1) && rc=$? || rc=$?

  ## assert

  # assert no error
  (( rc == 0 )) || {
    echo -e "task.curl: error = $rc, want: 0\n$got"
    return 1
  }

  # assert that the file was downloaded
  [[ -f dst.txt && $(<src.txt) == $(<dst.txt) ]] || {
    echo -e "task.curl: expected file contents to match.\n$got"
    return 1
  }

  # assert that we got the wanted output
  local want=$'[\E[38;5;220mbegin\E[0m]\t\tdownload src.txt from http://127.0.0.1:8000 as dst.txt
[\E[38;5;208mchanged\E[0m]\tdownload src.txt from http://127.0.0.1:8000 as dst.txt'

  [[ $got == "$want" ]] || {
    echo -e "task.curl: got doesn't match want:\n$(t.diff "$got" "$want")"
    return 1
  }
}

# test_task.git_clone tests whether git cloning works with github.
# It does its work in a directory it creates in /tmp.
test_task.git_clone() {
  ## arrange
  # temporary directory
  local dir=$(t.mktempdir) || return 128  # fatal if can't make dir
  trap "rm -rf $dir" EXIT                 # always clean up
  cd $dir

  # TODO: build and clone local repo instead of from github

  ## act

  # run the command and capture the output and result code
  local got rc
  got=$(task.git_clone https://github.com/binaryphile/task.bash task.bash 2>&1) && rc=$? || rc=$?

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
  local want=$'[\E[38;5;220mbegin\E[0m]\t\tclone repo https://github.com/binaryphile/task.bash to task.bash
[\E[38;5;208mchanged\E[0m]\tclone repo https://github.com/binaryphile/task.bash to task.bash'

  [[ $got == "$want" ]] || {
    echo -e "task.git_clone got doesn't match want:\n$(t.diff "$got" "$want")"
    return 1
  }
}

# test_task.ln tests whether the symlink task works.
# There are subtests for link creation and when link creation fails.
# Subtests are run with t.run.
test_task.ln() {
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
    local casename=$1

    ## arrange

    # temporary directory
    local dir=$(t.mktempdir) || return 128  # fatal if can't make dir
    trap "rm -rf $dir" EXIT                 # always clean up
    cd $dir

    # create variables from the keys/values of the test map
    unset -v wanterr  # necessary for testing for existence with -v
    eval "$(t.inherit $casename)"

    ## act

    # run the command and capture the output and result code
    local got rc
    got=$(task.ln $targetname $linkname 2>&1) && rc=$? || rc=$?

    ## assert

    # if this is a test for error behavior, check it
    [[ -v wanterr ]] && {
      (( rc == wanterr )) && return

      echo -e "\ttask.ln: error = $rc, want: $wanterr\n$got"
      return 1
    }

    # assert no error
    (( rc == 0 )) || {
      echo -e "\ttask.ln: error = $rc, want: 0\n$got"
      return 1
    }

    # assert that the symlink was made
    [[ -L $linkname ]] || {
      echo -e "\ttask.ln: expected $2 to be symlink\n$got"
      return 1
    }

    # assert that we got the wanted output
    [[ $got == "$want" ]] || {
      echo -e "\ttask.ln: got doesn't match want:\n$(t.diff "$got" "$want")"
      return 1
    }
  }

  local failed=0 casename
  for casename in ${!case@}; do
    t.run subtest test_task.ln $casename || {
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
  # temporary directory
  local dir=$(t.mktempdir) || return 128  # fatal if can't make dir
  trap "rm -rf $dir" EXIT                 # always clean up
  cd $dir

  ## act

  # run the command and capture the output and result code
  local got rc
  got=$(task.mkdir 'a dir' 2>&1) && rc=$? || rc=$?

  ## assert

  # assert no error
  (( rc == 0 )) || {
    echo -e "task.mkdir error = $rc, want: 0\n$got"
    return 1
  }

  # assert that the directory was made
  [[ -d 'a dir' ]] || {
    echo -e "task.mkdir expected directory a\ dir.\n$got"
    return 1
  }

  # assert that we got the wanted output
  local want=$'[\E[38;5;220mbegin\E[0m]\t\tmake directory a\ dir
[\E[38;5;208mchanged\E[0m]\tmake directory a\ dir'

  [[ $got == "$want" ]] || {
    echo -e "task.mkdir got doesn't match want:\n$(t.diff "$got" "$want")"
    return 1
  }
}

appendToFile() { echo "_() { echo \$* >>$1; }; _"; }
