#!/bin/sh
# Turns a failed test's output into one GitHub Actions error annotation: its FAIL and SKIP lines first, then its
# last lines. Annotations of a public repository can be read without signing in
# (GET /repos/{owner}/{repo}/check-runs/{job id}/annotations), unlike the job's log.
#
#   .github/scripts/report_failure_as_annotation.sh TITLE LOG
title=${1:?a title}
log=${2:?a log file}

if [ ! -f "$log" ]; then
  echo "::error title=$title::no log at $log"
  exit 0
fi

{
  grep -E '(^| )(FAIL|SKIP) ' "$log" | head -n 40
  echo "-- last lines --"
  tail -n 60 "$log"
} | tr -d '\r' | sed 's/%/%25/g' | awk -v title="$title" '
  BEGIN { printf "::error title=%s::", title }
  { printf "%s%%0A", $0 }
  END { print "" }'
