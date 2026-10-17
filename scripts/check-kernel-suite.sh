#!/bin/sh
# Check the kernel suite's summary.  shen-erl's `make shen-tests` loads the
# kernel's runme.shen, which prints its counts and exits 0 whether or not
# tests failed, so the gate reads the counts instead of the exit status.
#
#   check-kernel-suite.sh LOG EXPECTED_PASSED
set -eu

LOG=$1
WANT=$2
passed=$(sed -n 's/^passed \.\.\. \([0-9][0-9]*\)$/\1/p' "$LOG" | tail -n 1)
failed=$(sed -n 's/^failed \.\.\. \([0-9][0-9]*\)$/\1/p' "$LOG" | tail -n 1)

echo "kernel suite: passed ${passed:-?}, failed ${failed:-?}, expected $WANT passed"
[ "${passed:-}" = "$WANT" ] && [ "${failed:-}" = 0 ]
