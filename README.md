# Shen Protocol Actors

A protocol-oriented actor language in Shen, with checked conversations and
executable models, targeting BEAM/OTP.

Protocols, session ownership, state transitions, and effects are explicit
language concepts. One defined semantics drives four things: static checking
(types, affine session endpoints, closed effects), deterministic simulation,
runtime enforcement of external traffic, and execution as ordinary supervised
OTP processes. The system states which guarantee comes from which source;
passing tests is never reported as a proof.

This is not another Shen port. Ordinary Shen is provided by
[`pyrex41/shen-erl`](https://github.com/pyrex41/shen-erl), which this project
consumes as a pinned dependency and leaves unmodified. Standard Shen keeps
booting the unmodified ShenOSKernel and passing its complete compatibility
suite throughout.

## What it does

```lisp
(protocol reservation
  (roles client inventory)
  (phase open
    (client -> inventory (commit operation-id)
      (outcomes committed expired))
    (client -> inventory (cancel operation-id)
      (outcomes cancelled expired)))
  (terminal committed cancelled expired))
```

- A shared inventory actor holds many reservation sessions; a session is a
  ledger entry, not necessarily a process.
- A checked client that reuses a consumed session endpoint is rejected before
  it runs. An unchecked client that sends a stale generation is rejected before
  any domain state changes.
- A timeout yields `OutcomeUnknown`, never a fabricated fresh endpoint;
  recovery reconciles the same operation identifier.
- Actor restart produces a new incarnation; old sessions fail with
  `StaleIncarnation` instead of silently reviving.
- The simulator and the live OTP adapter agree on normalized traces for
  recorded schedules within the modeled boundary.

The syntax above is illustrative until the first frontend milestone freezes
the grammar. See [docs/prd.md](docs/prd.md) for the full product requirements
and technical specification, and [docs/plan.md](docs/plan.md) for how it is
being built.

## Layout

```text
language/       Protocol frontend and checker
ir/             Protocol and actor representations
simulator/      Reference execution and exploration
runtime/        Session enforcement and OTP integration
backends/       Erlang forms and LFE experiments
examples/       Reservation service and checked clients
tests/          Compatibility, negative cases, conformance
docs/           Spec, semantics, decisions
```

## Building

The runtime is pinned, not vendored: `shen-erl.rev` names the exact commit,
`scripts/fetch-shen-erl.sh` fetches it into `deps/`, and shen-erl's own
Makefile builds it. Requirements are shen-erl's: Erlang/OTP 27 or newer, a C
compiler, `curl`, `tar`, `shasum`, plus `git`.

```sh
make            # fetch and build the pinned shen-erl, compile this repo
make baseline   # the compatibility gate: kernel suite (143 tests) + shen-erl CT
make ct         # this repository's Common Test suites
```

With Nix, `nix develop` gives the same toolchain shen-erl builds with (the
flake reuses shen-erl's `toolchain` package and follows its nixpkgs), and
points the fetch script at the flake input so both pins resolve to one tree.
`scripts/check-pins.sh` fails if `shen-erl.rev` and `flake.lock` disagree.
With direnv, `direnv allow` opts in.

## Status

Pre-M0. The repository holds the specification, the repository-boundary
decision, the build skeleton, and the plan. Milestone gates and their exit
evidence are in [docs/plan.md](docs/plan.md).

## Decisions

Design decisions with evidence live in [docs/decisions](docs/decisions).
The first is [the repository boundary](docs/decisions/0001-repository-boundary.md):
what belongs here, what goes upstream to shen-erl, and how the backend
investigation avoids a third repository.
