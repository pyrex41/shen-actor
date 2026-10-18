# Semantic regression corpus

The fixed point M1 compares backend candidates against (plan M0 step 4).
Each `NAME.shen` runs as a script from this directory and must exit 0 with
standard output equal to `NAME.expected`. `scripts/run-corpus.sh` drops the
`run time: N secs` lines `load` prints, since they are wall-clock.

```sh
make corpus                              # the pinned shen-erl
SHEN=path/to/launcher make corpus        # another backend
```

Expected outputs are what the language specifies, checked by hand, not
whatever the current backend printed. Two kinds of line come from the kernel
itself (its KLambda, identical on every correct backend) and are part of the
expected output: `load` echoing each loaded form's value, and the
"changing the arity of F may cause errors" warning. Where Shen leaves a
behaviour open, the case says so in a comment and records shen-erl's choice
(argument evaluation order in `eval-order.shen`). Unspecified behaviour with
no useful fixed point (equality of functions) is not tested.

A divergence on a new backend is a finding about that backend. Changing an
expected file needs a reason in the commit message.

| Case | Covers |
| --- | --- |
| `eval-order` | `do`, `let`, argument order, `if`/`and`/`or` short-circuit |
| `currying` | partial application of defined functions, lambdas, primitives, `fn` |
| `computed-application` | applying computed functions, higher-order composition |
| `closures` | capture by value, closures over mutable vectors, shadowing |
| `freeze-thaw` | delayed evaluation, re-forcing, laziness |
| `errors` | `error`, `simple-error`, `trap-error`, nesting, primitive errors |
| `equality` | structural `=` on numbers, lists, strings, symbols, vectors, tuples |
| `mutable-values` | vectors, aliasing, out-of-range reads, globals, property lists |
| `redefinition` | redefinition seen by existing callers, arity change both ways |
| `nested-load` | `load` within `load`, relative to `*home-directory*` |
