#!/bin/sh
# M1 measurements for ADR 0003 (plan section 6), both candidates side by side:
# kernel compile time, corpus run time, resource growth under repeated
# evaluation, kernel BEAM size and emitter size.  Run after `make` and
# backends/lfe/build.sh, inside the Nix shell.  Prints Markdown.
set -eu

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
ERL_TREE=$ROOT/deps/shen-erl
LFE_TREE=${DEST:-$ROOT/deps/shen-erl-lfe}
N=${N:-1000}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

secs() {
  start=$(date +%s%N)
  "$@" >/dev/null 2>&1 || { echo FAILED; return 0; }
  end=$(date +%s%N)
  echo "$(( (end - start) / 1000000 ))"
}

kernel_compile() {
  tree=$1
  mkdir -p "$TMP/out-$2"
  (cd "$tree" && secs env SHEN_ERL_ROOTDIR="$tree" bin/shen-erl --kl kl/*.kl --output-dir "$TMP/out-$2")
}

corpus() { secs env SHEN="$1/bin/shen-erl" sh "$ROOT/scripts/run-corpus.sh"; }

beam_kb() { du -ck "$1"/ebin/kl_*.beam | tail -n 1 | cut -f1; }

erlc -o "$TMP" "$ROOT/tests/probes/resource_probes.erl"
probes() {
  erl -noshell +P 524288 +t 4194304 -pa "$1/ebin" -pa "$TMP" -s resource_probes main "$N" |
    grep -v '^probe,' | sed "s/^/$2,/"
}

echo "| Measure | Erlang forms (shen-erl) | LFE |"
echo "| --- | --- | --- |"
echo "| Kernel compile, 22 files (ms) | $(kernel_compile "$ERL_TREE" erl) | $(kernel_compile "$LFE_TREE" lfe) |"
echo "| Corpus run, 10 cases (ms) | $(corpus "$ERL_TREE") | $(corpus "$LFE_TREE") |"
echo "| Kernel BEAM size (KB) | $(beam_kb "$ERL_TREE") | $(beam_kb "$LFE_TREE") |"
echo "| Emitter source lines | $(cat "$ERL_TREE/src/shen_erl_kl_codegen.erl" "$ERL_TREE/src/shen_erl_kl_env.erl" | wc -l) | $(cat "$ROOT/backends/lfe/shen_kl_lfe.erl" "$ROOT/backends/lfe/shim/shen_erl_kl_codegen.erl" | wc -l) |"
echo
echo "Resource probes, N = $N:"
echo
echo '```text'
echo "backend,probe,n,modules,atoms,ets_tables,memory_total_kb,memory_code_kb,us_per_op"
probes "$ERL_TREE" erlang
probes "$LFE_TREE" lfe
echo '```'
