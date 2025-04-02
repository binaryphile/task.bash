#!/usr/bin/env bash

Prog=$(basename "$0")   # match what the user called
Version=0.1

read -rd '' Usage <<END
Usage:

  $Prog [OPTIONS] [--] COMMAND

  Commands:

  The following commands update report.json:
    cover -- run kcov and record results
    lines -- run scc and record results
    test -- run tesht and record results
    badges -- run all three and create badges from the results

  Options (if multiple, must be provided as separate flags):

    -h | --help     show this message and exit
    -v | --version  show the program version and exit
    -x | --trace    enable debug tracing
END

## commands

# cmd.badges renders badges for program version, source lines, tests passed and coverage.
# It updates the latter three statistics beforehand.
cmd.badges() {
  cmd.cover
  cmd.lines
  local result=$(tesht | tail -n 1)
  [[ -e report.json ]] || echo '{}' >$report.json
  setField tests_passed \"$result\" report.json

  mkdir -p assets
  mk.Each makeBadge <<'  END'
    "version"       $(<VERSION)                                         "#007ec6" assets/version.svg
    "coverage"      "$(getField code_coverage report.json)%"            "#4c1"    assets/coverage.svg
    "source lines"  $(addCommas $(getField code_lines report.json))     "#007ec6" assets/lines.svg
    "tests"         $(addCommas $(getField tests_passed report.json))   "#4c1"    assets/tests.svg
  END
}

# cmd.cover runs coverage testing and saves the result to report.json.
# It parses the result from kcov's output directory.
# The badges appear in README.md.
cmd.cover() {
  kcov --include-path task.bash kcov tesht &>/dev/null
  local filenames=( $(mk.Glob kcov/tesht.*/coverage.json) )
  (( ${#filenames[*]} == 1 )) || mk.Fatal 'could not identify report file' 1

  local percent=$(jq -r .percent_covered ${filenames[0]})
  setField code_coverage ${percent%%.*} report.json
}

# cmd.gif creates a gif showing a sample run of update-env for README.md.
cmd.gif() {
  asciinema rec -c '/usr/bin/bash -c update-env' update-env.cast
  agg --speed 0.5 update-env.cast assets/update-env.gif
  rm update-env.cast
}

# cmd.lines determines the number of lines of source and saves it to report.json.
cmd.lines() {
  local lines=$(scc -f csv task.bash | tail -n 1 | { IFS=, read -r language rawLines lines rest; echo $lines; })
  setField code_lines $lines report.json
}

# cmd.test runs tesht and saves the summary of passing tests to report.json.
cmd.test() {
  local result=$(tesht | tee /dev/tty | tail -n 1)
  setField tests_passed \"$result\" report.json
}

## helpers

# addCommas adds commas to a number at every 10^3 place.
#
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
addCommas() { sed ':a;s/\B[0-9]\{3\}\>/,&/;ta' <<<$1; }

# makeBadge makes an svg badge showing label and value, rendered in color and saved to filename.
makeBadge() {
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

# accessors

# getField gets fieldname's value from filename.
getField() {
  local fieldname=$1 filename=$2
  jq -r .$fieldname $filename
}

# setField sets fieldname to value in a simple json object in filename.
setField() {
  local fieldname=$1 value=$2 filename=$3

  tmpname=$(mktemp)
  jq ".$fieldname = $value" $filename >$tmpname && mv $tmpname $filename
}

## globals

## boilerplate

source ~/.local/lib/mk.bash 2>/dev/null || { echo 'fatal: mk.bash not found' >&2; exit 1; }

# enable safe expansion
IFS=$'\n'
set -o noglob

mk.SetProg $Prog
mk.SetUsage "$Usage"
mk.SetVersion $Version

return 2>/dev/null    # stop if sourced, for interactive debugging
mk.HandleOptions $*   # standard options
mk.Main ${*:$?+1}     # showtime
