# ADR 0001: Repository boundary and the shen-erl dependency

Status: accepted · 17 October 2026

## Context

The PRD ([docs/prd.md](../prd.md)) specifies proposal B: a protocol-oriented
actor language with its own semantics, affine checker, simulator, OTP
generation, and release criteria. Its baseline is `pyrex41/shen-erl` at
`ea5380a433d4d4281d4ea4dd88c0ade290028a6c`, a Shen port that compiles KLambda
to Erlang abstract forms and boots the unmodified ShenOSKernel 42.2.

Two shapes were possible: grow B inside shen-erl, or give B its own repository
that depends on shen-erl. The PRD also calls for a KLambda-to-LFE backend
spike, which raised the question of a third repository for backends.

## Decision

**B lives in a new repository with `shen-erl` as its initial runtime
dependency.** B's language semantics, checker, simulator, and release criteria
deserve an identity beyond maintaining a Shen port.

| Repository | Owns |
| --- | --- |
| `pyrex41/shen-erl` | Standard Shen compatibility, KLambda compilation, runtime primitives, general Erlang interop |
| this repository | Protocol language, affine checker, actor IR, simulator, OTP generation, protocol runtime, evidence tooling |

**General runtime improvements go upstream into shen-erl**: ownership fixes,
embedding APIs, environment isolation, and compiler interfaces. They are
useful to any embedder of Shen on BEAM and are not specific to protocols.
**Protocol-specific restrictions and semantics stay here**: the checked
subset, affine endpoints, effect vocabulary, envelope validation, session
ledger, simulation, and conformance tooling.

**The runtime is pinned, not forked.** `shen-erl.rev` (and the `shen-erl`
input in `flake.lock`) name one commit. The tree is fetched into `deps/` and
built with shen-erl's own Makefile; nothing in this repository edits it.
Changes shen-erl needs are made in shen-erl and consumed by bumping the pin.
Nix makes the combined development environment reproducible: this flake
reuses shen-erl's `toolchain` package and follows its nixpkgs, so both trees
build with one Erlang/OTP.

**The backend investigation runs here, against the pinned shen-erl.** The
KLambda-to-LFE spike lives in `backends/`, reuses shen-erl's runtime
primitives and compatibility tests, and is judged by the decision rule in PRD
section 17. If it turns out to be a generally better Shen backend, it moves
upstream or is extracted based on the working implementation. **No third
repository is created before that boundary is clear.**

**One cohesive project layout**, by responsibility rather than by language:

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

The README leads with the project's actual purpose, a protocol-oriented
actor language in Shen with checked conversations and executable models
targeting BEAM/OTP, so the distinction from a Shen port is immediate.

## Consequences

- Every change here runs shen-erl's full kernel suite and Common Test suites
  unchanged (`make baseline`). Compatibility is measured, not inferred.
- Work that touches shen-erl internals (ETS ownership, the boot process,
  the compiler entry points) is an upstream PR first and a pin bump second.
  [docs/plan.md](../plan.md) lists the known upstream items.
- Checked actor modules are a distinct mode. Their restrictions never change
  ordinary Shen, which this repository does not own.
- The pin is a commit, so a bump is a reviewable diff of behavior; the
  compatibility gate runs on both sides of it.
- The LFE spike can be dropped, promoted, or extracted without reorganizing
  this repository.
