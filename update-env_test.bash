source ./update-env   # defines NL=$'\n'

## functions

# test_each tests that each applies functions to arguments.
# Subtests are run with tesht.Run.
test_each() {
  local -A case1=(
    [name]='capitalize a list of words'

    [command]="each '_() { echo \${1^}; }; _'"
    [inputs]='(foo bar baz)'
    [wants]="(Foo Bar Baz)"
  )

  # subtest runs each subtest.
  # casename is expected to be the name of an associative array holding at least the key "name".
  subtest() {
    local casename=$1

    ## arrange

    # create variables from the keys/values of the test map
    eval "$(tesht.Inherit "$casename")"

    ## act

    # run the command and capture the output and result code
    local got rc
    got=$(stream "${inputs[@]}" | eval "$command" 2>&1) && rc=$? || rc=$?

    ## assert

    # assert no error
    (( rc == 0 )) || {
      echo "${NL}each: error = $rc, want: 0$NL$got"
      return 1
    }

    # assert that we got the wanted output
    local want=$(stream "${wants[@]}")
    [[ $got == "$want" ]] || {
      echo "${NL}each: got doesn't match want:$NL$(tesht.Diff "$got" "$want" 1)$NL"
      echo "use this line to update want to match this output:${NL}want=${got@Q}"
      return 1
    }
  }

  local failed=0 casename
  for casename in ${!case@}; do
    tesht.Run test_each $casename || {
      (( $? == 128 )) && return 128 # fatal
      failed=1
    }
  done

  return $failed
}

# test_keepIf tests that keepIf filters lines by a pattern.
# Subtests are run with tesht.Run.
test_keepIf() {
  local -A case1=(
    [name]='keep only lines that match the pattern'

    [command]="keepIf '_() { [[ \$1 == a* ]]; }; _'"
    [inputs]='(apple banana apricot)'
    [wants]='(apple apricot)'
  )

  local -A case2=(
    [name]='keep only exact matches'

    [command]="keepIf '_() { [[ \$1 == cat ]]; }; _'"
    [inputs]='(cat catalog bobcat)'
    [wants]='(cat)'
  )

  # subtest runs each subtest.
  # casename is expected to be the name of an associative array holding at least the key "name".
  subtest() {
    local casename=$1

    ## arrange

    # create variables from the keys/values of the test map
    eval "$(tesht.Inherit "$casename")"

    ## act

    # run the command and capture the output and result code
    local got rc
    got=$(stream "${inputs[@]}" | eval "$command" 2>&1) && rc=$? || rc=$?

    ## assert

    # assert no error
    (( rc == 0 )) || {
      echo "${NL}keepIf: error = $rc, want: 0$NL$got"
      return 1
    }

    # assert that we got the wanted output
    local want=$(stream "${wants[@]}")
    [[ $got == "$want" ]] || {
      echo "${NL}keepIf: got doesn't match want:$NL$(tesht.Diff "$got" "$want" 1)$NL"
      echo "use this line to update want to match this output:${NL}want=${got@Q}"
      return 1
    }
  }

  local failed=0 casename
  for casename in ${!case@}; do
    tesht.Run test_keepIf $casename || {
      (( $? == 128 )) && return 128 # fatal
      failed=1
    }
  done

  return $failed
}

# test_map tests that map applies a command to each line.
# Subtests are run with tesht.Run.
test_map() {
  local -A case1=(
    [name]='prefix each line with a label'

    [command]="map line 'line: \$line'"
    [inputs]='(alpha beta)'
    [wants]="('line: alpha' 'line: beta')"
  )

  local -A case2=(
    [name]='double each numeric line'

    [command]="map line '\$(( line * 2 ))'"
    [inputs]='(1 2 3)'
    [wants]='(2 4 6)'
  )


  # subtest runs each subtest.
  # casename is expected to be the name of an associative array holding at least the key "name".
  subtest() {
    local casename=$1

    ## arrange

    # create variables from the keys/values of the test map
    eval "$(tesht.Inherit "$casename")"

    ## act

    # run the command and capture the output and result code
    local got rc
    got=$(stream "${inputs[@]}" | eval "$command" 2>&1) && rc=$? || rc=$?

    ## assert

    # assert no error
    (( rc == 0 )) || {
      echo "${NL}map: error = $rc, want: 0$NL$got"
      return 1
    }

    # assert that we got the wanted output
    local want=$(stream "${wants[@]}")
    [[ $got == "$want" ]] || {
      echo "${NL}map: got doesn't match want:$NL$(tesht.Diff "$got" "$want" 1)$NL"
      echo "use this line to update want to match this output:${NL}want=${got@Q}"
      return 1
    }
  }

  local failed=0 casename
  for casename in ${!case@}; do
    tesht.Run test_map $casename || {
      (( $? == 128 )) && return 128 # fatal
      failed=1
    }
  done

  return $failed
}


# test_stream tests that stream splits space-separated input into separate lines
# Subtests are run with tesht.Run.
test_stream() {
  local -A case1=(
    [name]='split arguments into separate lines'

    [command]='stream foo bar baz'
    [want]=$'foo\nbar\nbaz'
  )

  # subtest runs each subtest.
  # casename is expected to be the name of an associative array holding at least the key "name".
  subtest() {
    local casename=$1

    ## arrange

    # create variables from the keys/values of the test map
    eval "$(tesht.Inherit "$casename")"

    ## act

    # run the command and capture the output and result code
    local got rc
    got=$(eval "$command" 2>&1) && rc=$? || rc=$?

    ## assert

    # assert no error
    (( rc == 0 )) || {
      echo "${NL}stream: error = $rc, want: 0$NL$got"
      return 1
    }

    # assert that we got the wanted output
    [[ $got == "$want" ]] || {
      echo "${NL}stream: got doesn't match want:$NL$(tesht.Diff "$got" "$want" 1)$NL"
      echo "use this line to update want to match this output:${NL}want=${got@Q}"
      return 1
    }
  }

  local failed=0 casename
  for casename in ${!case@}; do
    tesht.Run test_stream $casename || {
      (( $? == 128 )) && return 128 # fatal
      failed=1
    }
  done

  return $failed
}
