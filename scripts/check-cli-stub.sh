#!/bin/sh
# bin/shen-actor runs and every stubbed subcommand fails with its message
# (plan M0 step 7).
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
ERR=$(mktemp)
trap 'rm -f "$ERR"' EXIT

for cmd in check simulate replay explain build run; do
  if "$ROOT/bin/shen-actor" "$cmd" x 2>"$ERR"; then
    echo "shen-actor $cmd: exited 0" >&2
    exit 1
  fi
  grep -q "shen-actor $cmd: not implemented" "$ERR" || { cat "$ERR" >&2; exit 1; }
done
echo "shen-actor stub: all subcommands report not implemented"
