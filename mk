#!/usr/bin/env bash

mkProg=$(basename "$0")   # use the invoked filename as the program name

read -rd '' mkUsage <<END
Usage:

  $mkProg [OPTIONS] [--] COMMAND

  Commands:

  The following commands update REPORT.json:
    cover -- run kcov and record coverage_percent
    lines -- run scc and record code_lines
    test -- run tesht on task_test.bash and record test_failures
    stats -- run all three

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

  mkdir -p badges
  makeSVG "coverage" "$(jq -r .code_coverage REPORT.json)%" "#4c1" badges/coverage.svg
  makeSVG "source lines" $(addCommas $(jq -r .code_lines REPORT.json)) "#007ec6" badges/lines.svg
  makeSVG "tests" $(addCommas $(jq -r .test_failures REPORT.json)) "#4c1" badges/tests.svg
}

cmd.test() {
  count=$(tesht | tee /dev/tty | grep -o FAIL | wc -l)
  setField test_failures $count REPORT.json
}

## helpers

addCommas() { sed ':a;s/\B[0-9]\{3\}\>/,&/;ta' <<<$1; }
# Breakdown
#
# :a
# This defines a label called a. Think of it like a named point in the script — we’ll loop back to it later.
#
# s/\B[0-9]\{3\}\>/,&/;
# This is the substitution command. Let's dissect the regex:
#
# \B: Match a position that is not a word boundary.
# Ensures we don’t match at the start of the string.
#
# [0-9]\{3\}: Match exactly 3 digits.
#
# \>: Match the end of a word — which is the end of the number segment (i.e., before a comma or end of string).
#
# So, together: \B[0-9]\{3\}\> matches any group of 3 digits at the end of a longer number that’s not already at a boundary.
#
# Example:
# 1234567 -> matches 567, then 234, then 1
#
# Then we:
#
# Replace it with ,& -- the comma followed by the matched digits.
#
# This adds a comma before that 3-digit group.
#
# ta
# This is a conditional jump:
#
# t checks whether the previous s/// succeeded
#
# If so, it jumps to the label a
#
# This repeats the substitution until no more changes are made, i.e., all commas are inserted.

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

makeSVG() {
  local label=$1 value=$2 color=$3 filename=$4

  cat >$filename <<END
<svg xmlns="http://www.w3.org/2000/svg" width="200" height="20">
  <rect width="100" height="20" fill="#555"/>
  <rect x="100" width="100" height="20" fill="$color"/>
  <text x="50" y="14" fill="#fff" font-family="Verdana" font-size="11" text-anchor="middle">$label</text>
  <text x="150" y="14" fill="#fff" font-family="Verdana" font-size="11" text-anchor="middle">$value</text>
</svg>
END
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
