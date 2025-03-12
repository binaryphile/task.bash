source ./task.bash

## collection functions

# test_collect tests the collection of a stream into a safe, space-separated string.
# There are subtests that are run with tesht.run.
test_collect() {
  local -A case1=(
    [name]='turn a stream into a space-separated string'
    [args]=$'Hello there,\n World!'
    [want]='Hello there,  World!'
  )

  # subtest runs each subtest.
  # command is the parent function name.
  # case is expected to be the name of an associative array holding at least the key "name".
  subtest() {
    local casename=$1

    ## arrange
    # create variables from the keys/values of the test map
    eval "$(tesht.inherit $casename)"

    ## act
    # run the command and capture the output and result code
    local got rc
    got=$(echo "$args" | collect 2>&1) && rc=$? || rc=$?

    ## assert

    # assert no error
    (( rc == 0 )) || {
      echo -e "\n\tcollect: error = $rc, want: 0\n$got"
      return 1
    }

    # assert that we got expected output
    [[ $got == "$want" ]] || {
      echo -e "\n\tcollect: got doesn't match want:\n$(tesht.diff "$got" "$want")\n"
      echo -e "\tuse this line to update want to match this output:\n\twant=${got@Q}"
      return 1
    }
  }

  local failed=0 casename
  for casename in ${!case@}; do   # ${!case@} lists all variable names starting with "case"
    tesht.run test_collect $casename || {
      (( $? == 128 )) && return   # fatal
      failed=1
    }
  done

  return $failed
}

# test_each_side_effect tests each's ability to create side effects.
test_each_side_effect() {
  ## arrange
  # temporary directory
  local dir=$(tesht.mktempdir) || return 128  # fatal if can't make dir
  trap "rm -rf $dir" EXIT                     # always clean up
  cd $dir

  ## act
  # run the command and capture the output and result code
  local got rc
  got=$(echo $'Hello\nWorld!' | each $(appendToFile out.txt) 2>&1) && rc=$? || rc=$?

  ## assert

  # assert no error
  (( rc == 0 )) || {
    echo -e "\n\teach: error = $rc, want: 0\n$got"
    return 1
  }

  # assert that the file got the output
  want=$'Hello\nWorld!'
  [[ -e out.txt && $(<out.txt) == "$want" ]] || {
    echo -e "\n\teach: out.txt content does not match want:\n$(tesht.diff "$(<out.txt)" "$want")"
    return 1
  }

  # assert that we got no output
  [[ $got == '' ]] || {
    echo -e "\n\teach: got doesn't match want:\n$(tesht.diff "$got" "$want")\n"
    echo -e "\tuse this line to update want to match this output:\n\twant=${got@Q}"
    return 1
  }
}

# test_each tests the application of a command with to a list of invocations from stdin.
# There are subtests that are run with tesht.run.
test_each() {
  local -A case1=(
    [name]='take commands'

    [args]=$'Hello\nWorld!'
    [expression]=$'echo one'
    [want]=$'one Hello\none World!'
  )

  # subtest runs each subtest.
  # command is the parent function name.
  # case is expected to be the name of an associative array holding at least the key "name".
  subtest() {
    local casename=$1

    ## arrange
    # create variables from the keys/values of the test map
    eval "$(tesht.inherit $casename)"

    ## act
    # run the command and capture the output and result code
    local got rc
    got=$(echo "$args" | each $expression 2>&1) && rc=$? || rc=$?

    ## assert

    # assert no error
    (( rc == 0 )) || {
      echo -e "\n\teach: error = $rc, want: 0\n$got"
      return 1
    }

    # assert that we got the output we wanted
    [[ $got == "$want" ]] || {
      echo -e "\n\teach: got doesn't match want:\n$(tesht.diff "$got" "$want")\n"
      echo -e "\tuse this line to update want to match this output:\n\twant=${got@Q}"
      return 1
    }
  }

  local failed=0 casename
  for casename in ${!case@}; do   # ${!case@} lists all variable names starting with "case"
    tesht.run test_each $casename || {
      (( $? == 128 )) && return   # fatal
      failed=1
    }
  done

  return $failed
}

# test_glob tests globbing.
# There are subtests that are run with tesht.run.
test_glob() {
  local -A case1=(
    [name]='generate a list of two items'
    [pattern]='*'
    [filenames]=$'file1\nfile2'
    [want]=$'file1\nfile2'
  )

  local -A case2=(
    [name]='return an empty list'
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
    local dir=$(tesht.mktempdir) || return 128  # fatal if can't make dir
    trap "rm -rf $dir" EXIT                 # always clean up
    cd $dir

    # create variables from the keys/values of the test map
    unset -v filenames  # unset optional fields
    eval "$(tesht.inherit $casename)"

    # create files if requested
    [[ -v filenames ]] && {
      echo "$filenames" | each 'echo >'
    }

    ## act

    # run the command and capture the output and result code
    local got rc
    got=$(glob $pattern 2>&1) && rc=$? || rc=$?

    ## assert

    # assert no error
    (( rc == 0 )) || {
      echo -e "\n\tglob: error = $rc, want: 0\n$got"
      return 1
    }

    # assert that we got expected output
    [[ $got == "$want" ]] || {
      echo -e "\n\tglob: got doesn't match want:\n$(tesht.diff "$got" "$want")\n"
      echo -e "\tuse this line to update want to match this output:\n\twant=${got@Q}"
      return 1
    }
  }

  local failed=0 casename
  for casename in ${!case@}; do   # ${!case@} lists all variable names starting with "case"
    tesht.run test_glob $casename || {
      (( $? == 128 )) && return   # fatal
      failed=1
    }
  done

  return $failed
}

# test_map tests the application of an expression to a list of invocations from stdin.
# There are subtests that are run with tesht.run.
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
    eval "$(tesht.inherit $casename)"

    ## act

    # run the command and capture the output and result code
    local got rc
    got=$(map $varname $expression <<<"$args" 2>&1) && rc=$? || rc=$?

    ## assert

    # assert no error
    (( rc == 0 )) || {
      echo -e "\n\tmap: error = $rc, want: 0\n$got"
      return 1
    }

    # assert that we got the wanted output
    [[ $got == "$want" ]] || {
      echo -e "\n\tmap: got doesn't match want:\n$(tesht.diff "$got" "$want")\n"
      echo got=${got@Q}
      return 1
    }
  }

  local failed=0 casename
  for casename in ${!case@}; do
    tesht.run test_map $casename || {
      (( $? == 128 )) && return   # fatal
      failed=1
    }
  done

  return $failed
}

# test_stream tests echoing inputs separated by newline.
test_stream() {
  ## arrange
  # check that it's our stream since stream is already a command on some systems
  [[ $(type -t stream) == function ]] || { echo -e "\nstream should be a function"; return 1; }

  ## act
  # run the command and capture the output and result code
  local got rc
  got=$(stream * *2 2>&1) && rc=$? || rc=$?

  ## assert

  # assert no error
  (( rc == 0 )) || {
    echo -e "\nstream error = $rc, want: 0\n$got"
    return 1
  }

  # assert that we got the wanted output
  local want
  want=$'\*\n\*2'

  [[ $got == "$want" ]] || {
    echo -e "\nstream got doesn't match want:\n$(tesht.diff "$got" "$want")\n"
    echo -e "\tuse this line to update want to match this output:\n\twant=${got@Q}"
    return 1
  }
}

## tasks

# test_t.curl tests whether the curl download task receives a file from a local test http server.
# It does its work in a directory it creates in /tmp.
test_t.curl() {
  ## arrange

  # temporary directory
  local dir trapcmd
  dir=$(tesht.mktempdir) || return 128  # fatal
  trapcmd="rm -rf $dir"
  trap $trapcmd EXIT  # always clean up
  cd $dir

  # create the downloadable file
  echo 'hello there' >src.txt

  local pid
  pid=$(tesht.start_http_server) || { echo $pid; return 128; }  # if fatal pid is the error message
  trapcmd="kill $pid >/dev/null; $trapcmd"
  trap $trapcmd EXIT  # always clean up

  ## act

  # run the command and capture the output and result code
  local got rc
  got=$(t.curl http://127.0.0.1:8000/src.txt dst.txt 2>&1) && rc=$? || rc=$?

  ## assert

  # assert no error
  (( rc == 0 )) || {
    echo -e "\nt.curl: error = $rc, want: 0\n$got"
    return 1
  }

  # assert that the file was downloaded
  [[ -f dst.txt && $(<src.txt) == $(<dst.txt) ]] || {
    echo -e "\nt.curl: expected file contents to match.\n$got"
    return 1
  }

  # assert that we got the wanted output
  local want
  want=$'[\E[38;5;220mbegin\E[0m]\t\tdownload src.txt from http://127.0.0.1:8000 as dst.txt\r[\E[38;5;82mchanged\E[0m]\tdownload src.txt from http://127.0.0.1:8000 as dst.txt'

  [[ $got == "$want" ]] || {
    echo -e "\nt.curl: got doesn't match want:\n$(tesht.diff "$got" "$want")\n"
    echo -e "\tuse this line to update want to match this output:\n\twant=${got@Q}"
    return 1
  }
}

# test_t.git_checkout tests checking out a branch.
# It does its work in a directory it creates in /tmp.
test_t.git_checkout() {
  ## arrange
  # temporary directory
  local dir=$(tesht.mktempdir) || return 128  # fatal if can't make dir
  trap "rm -rf $dir" EXIT                 # always clean up
  cd $dir

  createCheckoutRepo develop

  ## act

  # run the command and capture the output and result code
  local got rc
  got=$(t.git_checkout develop . 2>&1) && rc=$? || rc=$?

  ## assert

  # assert no error
  (( rc == 0 )) || {
    echo -e "\nt.git_checkout error = $rc, want: 0\n$got"
    return 1
  }

  # assert that the branch was checked out
  [[ $(git rev-parse --abbrev-ref HEAD) == develop ]] || {
    echo -e "\nt.git_checkout could not switch to branch develop.\n$got"
    return 1
  }

  # assert that we got the wanted output
  local want
  want=$'[\E[38;5;220mbegin\E[0m]\t\tcheckout branch develop in repo .\r[\E[38;5;82mchanged\E[0m]\tcheckout branch develop in repo .'

  [[ $got == "$want" ]] || {
    echo -e "\nt.git_checkout got doesn't match want:\n$(tesht.diff "$got" "$want")\n"
    echo -e "\tuse this line to update want to match this output:\n\twant=${got@Q}"
    return 1
  }
}

# test_t.git_clone tests whether git cloning works.
# It does its work in a directory it creates in /tmp.
test_t.git_clone() {
  ## arrange
  # temporary directory
  local dir=$(tesht.mktempdir) || return 128  # fatal if can't make dir
  trap "rm -rf $dir" EXIT                 # always clean up
  cd $dir

  createCloneRepo

  ## act

  # run the command and capture the output and result code
  local got rc
  got=$(t.git_clone clone clone2 2>&1) && rc=$? || rc=$?

  ## assert

  # assert no error
  (( rc == 0 )) || {
    echo -e "\nt.git_clone error = $rc, want: 0\n$got"
    return 1
  }

  # assert that the repo was cloned
  [[ -e clone2/.git ]] || {
    echo -e "\nt.git_clone expected .git directory.\n$got"
    return 1
  }

  # assert that we got the wanted output
  local want
  want=$'[\E[38;5;220mbegin\E[0m]\t\tclone repo clone to clone2\r[\E[38;5;82mchanged\E[0m]\tclone repo clone to clone2'

  [[ $got == "$want" ]] || {
    echo -e "\nt.git_clone got doesn't match want:\n$(tesht.diff "$got" "$want")\n"
    echo -e "\tuse this line to update want to match this output:\n\twant=${got@Q}"
    return 1
  }
}

# test_t.ln tests whether the symlink task works.
# There are subtests for link creation and when link creation fails.
# Subtests are run with tesht.run.
test_t.ln() {
  local -A case1=(
    [name]='spaces in link and target'
    [targetname]='a\ target.txt'
    [linkname]='a\ link.txt'
    [want]=$'[\E[38;5;220mbegin\E[0m]\t\tsymlink a\\\\ link.txt to a\\\\ target.txt\r[\E[38;5;82mchanged\E[0m]\tsymlink a\\\\ link.txt to a\\\\ target.txt'
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
    local dir=$(tesht.mktempdir) || return 128  # fatal if can't make dir
    trap "rm -rf $dir" EXIT                 # always clean up
    cd $dir

    # create variables from the keys/values of the test map
    unset -v wanterr  # necessary for testing for existence with -v
    eval "$(tesht.inherit $casename)"

    ## act

    # run the command and capture the output and result code
    local got rc
    got=$(t.ln $targetname $linkname 2>&1) && rc=$? || rc=$?

    ## assert

    # if this is a test for error behavior, check it
    [[ -v wanterr ]] && {
      (( rc == wanterr )) && return

      echo -e "\n\tt.ln: error = $rc, want: $wanterr\n$got"
      return 1
    }

    # assert no error
    (( rc == 0 )) || {
      echo -e "\n\tt.ln: error = $rc, want: 0\n$got"
      return 1
    }

    # assert that the symlink was made
    [[ -L $linkname ]] || {
      echo -e "\n\tt.ln: expected $2 to be symlink\n$got"
      return 1
    }

    # assert that we got the wanted output
    [[ $got == "$want" ]] || {
      echo -e "\n\tt.ln: got doesn't match want:\n$(tesht.diff "$got" "$want")\n"
      echo -e "\tuse this line to update want to match this output:\n\twant=${got@Q}"
      return 1
    }
  }

  local failed=0 casename
  for casename in ${!case@}; do
    tesht.run test_t.ln $casename || {
      (( $? == 128 )) && return   # fatal
      failed=1
    }
  done

  return $failed
}

# test_t.mkdir tests whether a directory is made.
# It does its work in a directory it creates in /tmp.
test_t.mkdir() {
  ## arrange
  # temporary directory
  local dir=$(tesht.mktempdir) || return 128  # fatal if can't make dir
  trap "rm -rf $dir" EXIT                 # always clean up
  cd $dir

  ## act

  # run the command and capture the output and result code
  local got rc
  got=$(t.mkdir 'a dir' 2>&1) && rc=$? || rc=$?

  ## assert

  # assert no error
  (( rc == 0 )) || {
    echo -e "\nt.mkdir error = $rc, want: 0\n$got"
    return 1
  }

  # assert that the directory was made
  [[ -d 'a dir' ]] || {
    echo -e "\nt.mkdir expected directory a\ dir.\n$got"
    return 1
  }

  # assert that we got the wanted output
  local want
  want=$'[\E[38;5;220mbegin\E[0m]\t\tmake directory a\\ dir\r[\E[38;5;82mchanged\E[0m]\tmake directory a\\ dir'

  [[ $got == "$want" ]] || {
    echo -e "\nt.mkdir got doesn't match want:\n$(tesht.diff "$got" "$want")\n"
    echo -e "\tuse this line to update want to match this output:\n\twant=${got@Q}"
    return 1
  }
}

## helpers

# appendToFile creates a lambda that echoes its arguments to the provided filename argument.
appendToFile() { echo "_() { echo \$* >>$1; }; _"; }

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
  git init clone
  cd clone
  echo hello >hello.txt
  git add hello.txt
  git commit -m init
) >/dev/null
