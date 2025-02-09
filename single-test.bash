#!/usr/bin/env bash

# This is a sample test file.  To use it, copy the file to a name that ends in `_test.bash`
# (note the underscore rather than hyphen).

source ./task.bash

sut=sut   # system under test

# It does its work in a directory it creates in /tmp.
test_sut() {
  ## arrange

  # temporary directory

  dir=$(mktemp -d /tmp/tesht.XXXXXX) || return

  trapcmd="rm -rf $dir"
  trap $trapcmd EXIT        # always clean up
  cd $dir

  set -- 'args to $sut go here'
  want=''

  ## act

  # run the command and capture the output and result code
  got=$($sut $* 2>&1)
  rc=$?

  ## assert

  # assert no error
  (( rc == 0 )) || {
    echo -e "$sut() error = $rc, want: 0\n$got"
    return 1
  }

  # assert that we got the wanted output
  [[ $got == "$want" ]] || {
    echo -e "$sut() got doesn't match want:\n$(t.diff "$got" "$want")"
    return 1
  }
}
