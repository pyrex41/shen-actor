#!/bin/sh
# Fetch the pinned shen-erl runtime into DESTDIR.
#
# shen-erl is a dependency, not a fork: this script never modifies what it
# fetches, and the only pin is the commit in shen-erl.rev (mirrored in
# flake.lock for Nix users; scripts/check-pins.sh keeps the two equal).
#
#   SHEN_ERL_REV   commit to check out (required; passed by the Makefile)
#   SHEN_ERL_URL   git URL (default: https://github.com/pyrex41/shen-erl)
#   SHEN_ERL_SRC   optional path to an already-fetched tree (for example the
#                  Nix flake input); copied instead of cloning
#   DESTDIR        where the tree ends up (required)
set -eu

: "${SHEN_ERL_REV:?}" "${DESTDIR:?}"
URL=${SHEN_ERL_URL:-https://github.com/pyrex41/shen-erl}
SRC=${SHEN_ERL_SRC:-}

if [ -d "$DESTDIR/.git" ]; then
  HAVE=$(git -C "$DESTDIR" rev-parse HEAD 2>/dev/null || echo none)
  if [ "$HAVE" = "$SHEN_ERL_REV" ]; then
    echo "fetch-shen-erl: $DESTDIR already at $SHEN_ERL_REV"
    exit 0
  fi
  echo "fetch-shen-erl: $DESTDIR is at $HAVE, want $SHEN_ERL_REV; refetching" >&2
fi

rm -rf "$DESTDIR"
mkdir -p "$(dirname "$DESTDIR")"

if [ -n "$SRC" ]; then
  test -f "$SRC/src/shen_erl_kl_compiler.erl"
  cp -R "$SRC" "$DESTDIR"
  chmod -R u+w "$DESTDIR"
  echo "fetch-shen-erl: copied $SRC (pinned by flake.lock)"
else
  git init -q "$DESTDIR"
  git -C "$DESTDIR" remote add origin "$URL"
  git -C "$DESTDIR" fetch -q --depth 1 origin "$SHEN_ERL_REV"
  git -C "$DESTDIR" checkout -q FETCH_HEAD
  echo "fetch-shen-erl: checked out $URL at $SHEN_ERL_REV"
fi

test -f "$DESTDIR/Makefile"
test -f "$DESTDIR/src/shen_erl_kl_compiler.erl"
