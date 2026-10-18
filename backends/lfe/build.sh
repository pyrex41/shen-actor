#!/bin/sh
# Build the LFE candidate (plan M1): a copy of the pinned shen-erl tree in
# DEST whose shen_erl_kl_codegen is the LFE shim, with the unmodified
# kernel .kl files recompiled through backends/lfe/shen_kl_lfe.erl.
# deps/shen-erl is only read.  Requires `make` to have built it, and LFE on
# PATH (the Nix shell provides it) or LFE_EBIN.
#
#   DEST  where the candidate tree goes (default: deps/shen-erl-lfe)
set -eu

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SRC=$ROOT/deps/shen-erl
DEST=${DEST:-$ROOT/deps/shen-erl-lfe}

test -x "$SRC/bin/shen-erl" || { echo "build.sh: run make first" >&2; exit 1; }
# LFE_EBIN overrides; otherwise found from the lfe executable (the Nix shell
# puts it on PATH but not on erl's code path).
if [ -z "${LFE_EBIN:-}" ] && command -v lfe >/dev/null; then
  LFE_EBIN=$(dirname "$(readlink -f "$(command -v lfe)")")/../lib/lfe/ebin
fi
test -f "${LFE_EBIN:-}/lfe_comp.beam" || { echo "build.sh: LFE not found; set LFE_EBIN" >&2; exit 1; }

rm -rf "$DEST"
cp -R "$SRC" "$DEST"
chmod -R u+w "$DEST"
rm -f "$DEST"/ebin/kl_*.beam

cp "$LFE_EBIN"/*.beam "$DEST/ebin/"
erlc -o "$DEST/ebin" +debug_info "$ROOT/backends/lfe/shen_kl_lfe.erl"
erlc -o "$DEST/ebin" +debug_info "$ROOT/backends/lfe/shim/shen_erl_kl_codegen.erl"

cd "$DEST"
start=$(date +%s)
# The same 22 files shen-erl's Makefile compiles (KERNEL_KL); order does not
# matter because every defun is registered before any is compiled.
SHEN_ERL_ROOTDIR=$DEST bin/shen-erl --kl kl/*.kl --output-dir ebin
echo "build.sh: kernel compiled through LFE in $(( $(date +%s) - start )) s"
