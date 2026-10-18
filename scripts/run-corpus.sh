#!/bin/sh
# Run the semantic regression corpus (plan M0 step 4).
#
# Each tests/corpus/NAME.shen runs as `SHEN script NAME.shen` from
# tests/corpus, so *home-directory* is that directory.  It passes when it
# exits 0 and its standard output equals NAME.expected, after dropping the
# "run time: N secs" lines load prints (wall-clock, so not reproducible).
#
#   SHEN   the launcher to test (default: deps/shen-erl/bin/shen-erl).  M1
#          points this at each backend candidate in turn.
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SHEN=${SHEN:-$ROOT/deps/shen-erl/bin/shen-erl}
CORPUS=$ROOT/tests/corpus
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

pass=0
fail=0
for src in "$CORPUS"/*.shen; do
  name=$(basename "$src" .shen)
  (cd "$CORPUS" && "$SHEN" script "$name.shen") >"$OUT/$name.raw" 2>"$OUT/$name.err"
  status=$?
  grep -Ev '^run time: [0-9.]+ secs$' "$OUT/$name.raw" >"$OUT/$name.out"
  if [ "$status" -eq 0 ] && cmp -s "$CORPUS/$name.expected" "$OUT/$name.out"; then
    pass=$((pass + 1))
    echo "ok   $name"
  else
    fail=$((fail + 1))
    echo "FAIL $name (exit $status)"
    diff -u "$CORPUS/$name.expected" "$OUT/$name.out" | sed 's/^/     /'
    sed 's/^/     stderr: /' "$OUT/$name.err"
  fi
done

echo "corpus: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
