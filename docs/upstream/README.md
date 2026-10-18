# Upstream patches for shen-erl

Plan section 5 items, prepared against `pyrex41/shen-erl` at the pin
(`ea5380a`, which is also its `master`). They are `git format-patch` files
for review and for opening as shen-erl pull requests; this repository does
not apply them. When one merges upstream, bump `shen-erl.rev` and
`flake.lock`, re-run `make baseline` and the probes, and update
`tests/BASELINE.md` and `tests/ownership_SUITE.erl` in the same change.

```sh
git -C path/to/shen-erl am docs/upstream/u1-unnamed-tables.patch
git -C path/to/shen-erl am docs/upstream/u3-compiler-interface.patch
```

Results on the pinned toolchain (OTP 28, `nix develop`):

| Tree | Kernel suite | shen-erl CT |
| --- | --- | --- |
| U1 alone | 143 passed, 0 failed | 49 ok (46 + 3 new) |
| U3 alone | 143 passed, 0 failed | 57 ok (46 + 11 new) |
| U1 then U3 | 143 passed, 0 failed | 60 ok |

## U1: unnamed ETS tables

`dict_new/0` creates `ets:new(dict, [set, protected])` instead of a named
`DICT<n>` table, so vectors and dictionaries create no atoms and no longer
bump the shared variable counter. Protection stays `protected`, as today.
`shen_erl_interop:to_shen/1` recognises the table by `is_reference/1`.

Resource probes, N = 1000 (atoms created): absvector 1000 to 0, `shen.dict`
2000 to 1000 (the rest is U4's per-eval module), redefinition 5799 to 1005,
distinct definitions 10800 to 6000. Tables are still freed only when their
owner exits; that limit remains.

## U3: compiler interface

A new public module `shen_erl_compiler_api`: `parse_string/1`,
`parse_file/1`, `forms/2` and `compile/2` (no loading, no change to function
bindings), `load/2` (the one side-effecting step: load and register),
`run_toplevel/1`, `call/2` (the `invoke/2` dispatch), `arity/1`,
`lookup/1`. Codegen gains an overlay of the functions being compiled so
that registration can move after compilation without changing generated
code; `eval/1` uses it and produces byte-identical BEAM to before. The
kernel build path is untouched and its 22 beams rebuild byte-identical.

Limits, as the module documents: `forms/2` and `compile/2` still advance the
shared variable counter (ADR 0003 notes the per-compile counter that would
remove this); functions loaded through `load/2` are visible to Shen's `fn`
and partial application only after `update-lambda-table`.
