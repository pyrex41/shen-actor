# tests/

Compatibility, negative cases, and conformance.

- Compatibility: `make baseline` runs the pinned shen-erl's kernel suite (143
  tests) and its Common Test suites unmodified. This is the gate for every
  change, including pin bumps.
- Semantic regression corpus (M0): Shen programs with expected results for
  evaluation order, currying, computed application, closures, freeze/thaw,
  errors, equality, mutable values, arity redefinition and nested load, run
  against each backend candidate. `make corpus`; see `corpus/README.md`.
- Ownership probes (M0): cross-process access to vectors, dictionaries,
  globals, and eval; records what fails today before any store changes.
- Negative checker fixtures (M3): endpoint reuse, aliasing through branches,
  capture in closures, hidden impurity, affine values in unrestricted
  containers; each must be rejected with the specified diagnostic.
- Conformance (M5): recorded live runs replayed against the model; hand-
  authored reference scenarios and independent validators so a shared IR bug
  cannot hide.

Common Test suites in this directory run with `make ct`.
