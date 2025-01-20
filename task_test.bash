source ./task.bash

Test_task.ln() {
  format=/tmp/test.XXXXXX
  tests=(
    '
      [name]="basic"
      [args]="filename \${dir}filename"
      [dir]=$(mktemp -d $format)
      [want]=$(cat <<END
[begin]		create symlink - filename \${dir}filename
[changed]	create symlink - filename \${dir}filename
END
      )
    '
    '
      [name]="fail on link creation"
      [args]="second /mnt/chromeos/MyFiles/Downloads/crostini/second"
      [wanterr]=1
    '
  )

  for test in "${tests[@]}"; do
    (
      local -A map="( $test )"
      dir=${map[dir]:-}${map[dir]:+/}
      [[ $dir != '' ]] && trap "rm -rf $dir" EXIT

      eval "set -- ${map[args]}"

      got=$(task.ln $1 $2 2>&1) && rc=$? || rc=$?

      [[ -v map[wanterr] ]] && {
        want=${map[wanterr]}
        (( rc == want )) || Error "task.ln result code, got: $rc, want: $want\n$got"
        return
      }

      (( rc == 0 )) || { Error "task.ln result code, got: $rc, want: 0\n$got"; return; }

      [[ -L $2 ]] || { Error "task.ln expected $2 to be symlink\n$got"; return; }

      want=$(eval "echo \"${map[want]}\"")
      if [[ $got != "$want" ]]; then
        Error "task.ln got doesn't match want:\n$(Diff "$got" "$want")"
      fi
    )
  done
}
