#!/usr/bin/env bash

mkProg=$(basename "$0")   # use the invoked filename as the program name

read -rd '' mkUsage <<END
Usage:

  $mkProg [OPTIONS] [--] COMMAND

  Commands:

  The following commands update REPORT.json:
    cover -- run kcov and record coverage_percent
    lines -- run scc and record code_lines
    stats -- run all three of the above
    test -- run tesht on task_test.bash and record test_failures

  Options (if multiple, must be provided as separate flags):

    -h | --help     show this message and exit
    -v | --version  show the program version and exit
    -x | --trace    enable debug tracing
END

## commands

cmd.cover() {
  kcov --include-path task.bash kcov tesht >/dev/null
  local filenames=( $(glob kcov/tesht.*/coverage.json) )
  (( ${#filenames[*]} == 1 )) || { echo 'fatal: could not identify report file'; exit 1; }

  local percent=$(jq -r .percent_covered ${filenames[0]})
  setField coverage_percent ${percent%%.*} REPORT.json
}

cmd.lines() {
  local lines=$(scc -f csv task.bash | tail -n 1 | { IFS=, read -r language rawLines lines rest; echo $lines; })
  setField code_lines $lines REPORT.json
}

cmd.stats() {
  cmd.cover
  cmd.lines
  count=$(tesht | grep -o FAIL | wc -l)
  setField test_failures $count REPORT.json
}

cmd.test() {
  count=$(tesht | tee /dev/tty | grep -o FAIL | wc -l)
  setField test_failures $count REPORT.json
}

## helpers

createReport() {
  cat >$1 <<'END'
{
  "code_lines": 0,
  "coverage_percent": 0,
  "test_failures": 0
}
END
}

# glob works the same independent of IFS, noglob and nullglob
glob() {
  local pattern=$1

  local nullglobWasOn=0 noglobWasOn=1
  [[ $(shopt nullglob) == *on ]] && nullglobWasOn=1 || shopt -s nullglob  # enable nullglob
  [[ $- != *f* ]] && noglobWasOn=0 || set +o noglob                       # disable noglob

  local sep=${IFS:0:1} result
  local results=( $pattern )
  printf -v result "%q$sep" "${results[@]}"
  echo "${result%$sep}"

  # reset to old settings
  (( noglobWasOn )) && set -o noglob
  (( nullglobWasOn )) || shopt -u nullglob
}

setField() {
  local fieldname=$1 value=$2 filename=$3

  [[ -e REPORT.json ]] || createReport REPORT.json
  tmpname=$(mktemp tmp.XXXXXX) && trap "rm -f $tmpname" EXIT
  jq ".$fieldname = $value" $filename >$tmpname && mv $tmpname $filename
}

## globals

## boilerplate

source ~/.local/lib/mk.bash 2>/dev/null || { echo 'fatal: mk.bash not found' >&2; exit 1; }

# enable safe expansion
IFS=$'\n'
set -o noglob

return 2>/dev/null    # stop if sourced, for interactive debugging
mk.handleOptions $*   # standard options
mk.main ${*:$?+1}     # showtime
