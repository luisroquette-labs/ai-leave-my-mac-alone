#!/bin/bash
set -euo pipefail

log_dir="${HOME}/Library/Logs/CleanMyMac"
current="${log_dir}/clean-my-mac.log"
previous="${log_dir}/clean-my-mac.previous.log"
files=()
[[ -f "$current" ]] && files+=("$current")
[[ -f "$previous" ]] && files+=("$previous")

if (( ${#files[@]} == 0 )); then
  printf 'No cleanup log yet.\n'
  printf 'Expected: %s\n' "$current"
  exit 0
fi

awk '
  /END liberados=/ {
    if (match($0, /liberados=[0-9]+/)) {
      bytes = substr($0, RSTART + 10, RLENGTH - 10) + 0
      total += bytes
      runs++
      if (bytes > 0) positive++
    }
  }
  END {
    if (runs + 0 == 0) {
      print "The log exists, but it has no completed cleanup line (END liberados=)."
      exit
    }
    printf "Completed runs: %d\n", runs
    printf "Runs that increased free space: %d\n", positive + 0
    printf "Free space gained: %d bytes\n", total + 0
    printf "Free space gained: %.2f GB\n", total / 1000000000
    printf "Free space gained: %.2f GiB\n", total / 1073741824
  }
' "${files[@]}"

printf '\n'
printf '%s\n' "liberados is the increase in free bytes on the data volume during that run."
printf '%s\n' "A Trash destination often records 0, because space returns when the Trash is emptied."
printf '%s\n' "If other writes filled the disk during the run, that run contributes 0."
printf '%s\n' "Only this log and one rotated previous log are kept. Rotation happens at 5 MB."
