#!/usr/bin/env bash
# Turns the error lines of a build or test log into one GitHub Actions annotation, so a
# failure can be read on the run page (and through the public API) without the full log.
# Usage: annotate-errors.sh <log file> <title>
set -uo pipefail
log="$1"
title="$2"
[ -f "$log" ] || exit 0
lines="$(grep -E 'error:|: error|failed|Failing tests|XCTAssert|fatal' "$log" | grep -vE '^\s*$|^ *[0-9]+ \|' | awk '!seen[$0]++' | head -n 60)"
[ -n "$lines" ] || lines="$(tail -n 30 "$log")"
# Annotations are one line: escape %, CR and LF as the workflow command format requires.
message="$(printf '%s' "$lines" | sed -e 's/%/%25/g' | sed -e ':a' -e 'N' -e '$!ba' -e 's/\r/%0D/g' -e 's/\n/%0A/g')"
echo "::error title=${title}::${message}"
