#!/bin/sh
# The shen-erl commit is pinned in two places for two audiences: shen-erl.rev
# (plain Makefile builds) and flake.lock (Nix).  They must agree.
set -eu
cd "$(dirname "$0")/.."
REV=$(cat shen-erl.rev)
LOCKED=$(sed -n '/"shen-erl": {/,/^    }/p' flake.lock | sed -n 's/.*"rev": "\([0-9a-f]*\)".*/\1/p' | head -1)
if [ -z "$LOCKED" ]; then
  echo "check-pins: no shen-erl rev found in flake.lock (run: nix flake lock)" >&2
  exit 1
fi
if [ "$REV" != "$LOCKED" ]; then
  echo "check-pins: shen-erl.rev ($REV) and flake.lock ($LOCKED) disagree" >&2
  exit 1
fi
echo "check-pins: shen-erl pinned at $REV"
