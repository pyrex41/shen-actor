# Implementation plan

Status: draft for M0 · 17 October 2026 · companion to [prd.md](prd.md) and
[ADR 0001](decisions/0001-repository-boundary.md)

This plan turns the PRD into ordered work in this repository, states what
must change upstream in shen-erl and why, and fixes the evidence each
milestone must produce. Milestones are gates, not dates.

## 1 Baseline facts

Facts about `pyrex41/shen-erl` at `ea5380a433d4d4281d4ea4dd88c0ade290028a6c`,
established by reading the revision. They are the ground for the plan; the
PRD's design requirements are not restated here.

**Build and launch**

- GNU Make plus a C launcher (`c_src/shen-erl.c`). The launcher runs
  `erl -pa ROOT/ebin -noshell -s shen_erl_init +P 524288 +t 4194304 -extra ARGS`.
  `ERL_FLAGS` is honored by `erl` itself, so this repository adds its own
  `ebin` to the code path without touching the launcher.
- No rebar3 and no running OTP application. `shen_erl.app.src` exists, but
  `shen_erl_init:start/0` builds the stores, boots the kernel and runs the
  program inside the `-s` init process, then calls `init:stop`. Nothing is
  supervised.
- `Erlmakefile` (erlang.mk) is used only inside Docker for `make tests` and
  dialyzer. `make ct` runs four Common Test suites: codegen, overrides,
  interop, json. `make shen-tests` runs the kernel's `runme.shen`, 143 tests.
- The kernel is ShenOSKernel 42.2, fetched as a release tarball and verified
  by SHA-256 before extraction (`scripts/fetch-kernel.sh`). `stlib.kl` is not
  booted. The launcher extension's `script FILE ARGS` sets `*argv*` to
  `[FILE | ARGS]`, which is enough for an `actor` command-line wrapper.
- The flake's `toolchain` is gnumake, gcc and `beamPackages.erlang` from
  nixpkgs-unstable at `ac6b216` (25 August 2026). No LFE.

**Stores and ownership** (`shen_erl_global_stores.erl`, 162 lines)

- Three named, protected ETS tables hold function bindings, global values and
  the variable counter. They are owned by whichever process calls `init/0`.
  Protected means other processes can read them and cannot write.
- `dict_new/0` creates a named ETS table `DICT<n>` per dictionary. An
  absvector is `{vector, Len, DictAtom}` over the same mechanism. Every vector
  and dictionary therefore creates an atom and a named table, owned by the
  creating process and dying with it. `shen_erl_interop:to_shen/1`
  recognizes both shapes by `is_atom(Tab)`.
- `get_varname/0` is a global counter in ETS used by both the compiler
  (variable naming) and `dict_new/0`. It is a write, so compiling or
  allocating a vector from any process other than the owner fails with
  `badarg`.

**Compiler and evaluation** (`shen_erl_kl_codegen.erl` 413 lines,
`shen_erl_kl_compiler.erl` 247 lines)

- Each KLambda file compiles to one module `kl_<name>` through
  `erl_syntax` and `compile:forms`. Each `eval-kl` of a non-defun form
  compiles a fresh module named `_kl_` plus 32 random letters, loads it with
  `code:load_binary`, runs `kl_tle/0`, and never purges it. Defuns compile
  into `_kl_<Name>` modules and are reloaded on redefinition. The launcher
  raises the atom limit to 4194304 because the type checker evaluates
  heavily. Module growth and old-code retention are unmeasured.
- Kernel and primitive calls are bound statically. Calls to user-defined
  functions go through `shen_erl_kl_compiler:invoke/2`, which reads the live
  MFA and arity, so redefinition with a different arity works.
- Port functions (`erl.*`, `json.*`, `js.*`) are registered in the kernel's
  `*property-vector*` under the `arity` and `shen.lambda-form` properties.
  The checker can read arity information from that dictionary.
- `erl.receive/1` is a catch-all `receive`. The generic interop turns tuples
  into lists. Both match the PRD's warnings (sections 11 and 15) and neither
  is used by the actor runtime.

**Baseline reproduction in this session**

Built under `nix develop` from the pinned flake. Results are recorded in
section 9.

## 2 Repository mechanics

**Pin.** `shen-erl.rev` holds the commit. `scripts/fetch-shen-erl.sh` fetches
it into `deps/shen-erl` (shallow `git fetch` of the exact commit), or copies
the Nix flake input when `SHEN_ERL_SRC` is set. `scripts/check-pins.sh` fails
when `shen-erl.rev` and `flake.lock` disagree. A pin bump is a one-line diff
plus `nix flake lock --update-input shen-erl`, reviewed with `make baseline`
on both sides.

**Build.** `make` fetches and builds shen-erl with its own Makefile, then
compiles this repository's Erlang modules into `ebin/`. `make baseline` runs
the kernel suite and shen-erl's CT suites unmodified; this is PRD success
criterion 7 and runs on every change. `make ct` runs this repository's
suites. `make run SCRIPT=... ARGS=...` runs a Shen script with both code
paths, which is how the `actor` subcommands will be exposed until a
`bin/shen-actor` wrapper is added in M0.

**Nix.** The flake takes shen-erl as an input pinned by commit, reuses its
`toolchain` package and follows its nixpkgs, so both trees build with one
Erlang/OTP. LFE comes from the same nixpkgs (verified: LFE 2.2.2 on OTP
28.5 at the pinned revision), so the M1 spike has a pinned LFE with no extra
input. Nix is optional; the Makefile path works with any toolchain.

**Languages.** The frontend, elaborator, checker and reference interpreter
are written in Shen and run on the pinned shen-erl. The runtime, ingress,
codecs, OTP adapter, simulator scheduler and conformance tooling are Erlang.
The LFE spike is Erlang plus LFE. Generated services are LFE or Erlang per
the backend decision.

**CI.** One workflow: `nix develop --command make baseline`, `make ct`,
`scripts/check-pins.sh`. Added in M0 once the baseline is green.

## 3 Components to directories to milestones

| PRD component | Directory | Milestone |
| --- | --- | --- |
| Shen frontend (protocol forms) | `language/` | M0 grammar, M2 parser |
| Protocol elaborator | `language/` to `ir/` | M2 |
| Actor checker (types, affine, effects, obligations) | `language/` | M3, M6 |
| Checked actor IR, protocol graph, artifact format | `ir/` | M2 |
| Reference step interpreter | `simulator/` | M2 |
| Simulator, explorer, shrinking, replay | `simulator/` | M5 |
| Runtime boundary: envelopes, ledgers, ingress, codecs | `runtime/` | M2 ledger, M4 rest |
| OTP application, supervision, incarnation | `runtime/` | M4 |
| Erlang forms generator, LFE spike, backend ADR | `backends/` | M1, M4 |
| Reservation service and clients | `examples/` | M2 onward |
| Compatibility, probes, corpus, negatives, conformance | `tests/` | every milestone |
| Derivation checker, evidence labels | `language/`, `docs/` | M6 |

## 4 Milestones

Each milestone keeps `make baseline` green and adds its own checks. Exit
evidence is what must exist in the repository, not a demonstration.

### M0 Baseline and semantic decisions

Goal: a reproducible baseline with explicit, recorded failures, and the
decisions later milestones depend on.

1. Repository skeleton, pin, flake, Makefile, README, PRD, ADR 0001. (This
   change.)
2. `make baseline` green in CI from a clean checkout; record OTP version,
   kernel checksum and suite counts in `tests/BASELINE.md`.
3. Ownership probes (`tests/ownership_SUITE.erl`): from a second process,
   read a global, set a global, create a vector, write to a vector created by
   the owner, call `eval-kl`, define a function. Each probe records the
   observed outcome (works, `badarg`, wrong value). Expected from section 1:
   reads work, every write and every compile fails. Observed: as expected,
   except that `eval-kl` of a non-defun expression works from any process
   (see `tests/BASELINE.md`). No store is changed in this milestone.
4. Semantic regression corpus (`tests/corpus/`): Shen programs with expected
   output for evaluation order, currying, computed application, closures,
   freeze/thaw, error propagation, equality, mutable values, redefinition with
   a different arity, nested `load`. Runs through `shen-erl script`. This is
   the fixed point M1 compares both backends against; M1 may not start until
   it exists.
5. Resource probes: repeated `eval-kl` in a loop, measuring module count,
   atom count and memory; repeated vector allocation, measuring atom count.
   Numbers go into `tests/BASELINE.md` and feed upstream items U1 and U4.
6. Grammar draft, ADR 0002: freeze the `protocol` form, the checked module
   form, handler and command syntax, with runnable examples under
   `examples/reservation/` that the kernel reader parses today (they are data
   until M2 interprets them). Includes the failure taxonomy as the closed set
   of rejection reasons from PRD sections 10, 11 and 16, and the inventory
   invariant statement for M6.
7. `bin/shen-actor`: a shell wrapper over `shen-erl script language/cli.shen`
   with the subcommands from PRD section 20 stubbed to print "not
   implemented" and exit non-zero. Integration, not replacement, of the
   launcher.

Exit evidence: CI green on `make baseline`; `tests/BASELINE.md` with
measured numbers; probe suite with every current failure asserted as the
current behavior; corpus with expected outputs; ADR 0002 with parsed
examples. No compatibility claim appears that a test does not make.

### M1 Backend spike

Goal: evidence for the LFE-versus-Erlang-forms decision.

1. `backends/lfe/`: KLambda-to-LFE emitter that reuses shen-erl's primitives,
   overrides and global stores unchanged (depends on U3 for a stable
   compiler entry point; until U3 lands, call `shen_erl_kl_compiler` and
   `shen_erl_kl_codegen` directly and note the coupling).
2. Compile the unmodified pinned kernel through it; boot; run the 143 kernel
   tests and the M0 corpus. Any divergence is a finding, not a tweak to the
   corpus.
3. Dynamic evaluation and redefinition through the LFE path, including arity
   change, with the same resource probes as M0.
4. One protocol actor skeleton (hand-written IR for the reservation service)
   lowered through both candidates to a running gen_statem or gen_server.
5. Measure compile latency, execution overhead on the corpus, module and
   atom growth under repeated eval, source-location fidelity, and
   implementation size.
6. ADR 0003 applying the PRD section 17 decision rule, with raw measurements
   and both candidates' kernel results attached.

Exit evidence: both candidates' full kernel results; corpus results side by
side; ADR 0003. If LFE wins and is a generally better Shen backend, the
upstreaming or extraction question is decided in the same ADR from the
working implementation (ADR 0001).

### M2 Protocol core

Goal: protocols are data with validated structure, and one interpreter
defines the step semantics. Backend-independent; does not wait for M1.

1. `language/`: parser for the ADR 0002 grammar producing the canonical
   protocol graph in `ir/`.
2. Elaborator validators for every rejection in PRD section 8, each with a
   negative fixture.
3. `ir/`: checked actor IR and the artifact record with schema version,
   digests and evidence slots (claims are empty until M3 and M6 fill them).
4. `simulator/`: reference step interpreter implementing PRD section 7
   exactly, with Accepted and Rejected as the only outcomes and
   `Rejected` leaving state untouched.
5. `runtime/`: session ledger and operation ledger as pure Erlang data
   structures with the validation order from PRD section 11; generation,
   duplicate, conflict and stale-incarnation cases.
6. Hand-authored traces for the reservation service: valid runs, duplicate
   operation, same id different payload, stale generation, stale incarnation,
   expiry racing commit.

Exit evidence: traces pass against the interpreter and the ledger; every
elaborator rejection has a fixture; the IR round-trips through its artifact
encoding.

### M3 Checked sessions

Goal: a checked client cannot misuse a session endpoint, and a checked
handler cannot hide an effect.

1. Affine checker with Gamma and Delta contexts, branch reconciliation,
   continuation typing, and the initial prohibitions (affine values in lists,
   maps, globals, payloads, arbitrary closures).
2. Closed effect checking: closed call graph, conservative whitelist,
   transitive purity, explicit host contracts; `erl.apply`, `eval-kl`,
   mutable global access and dynamic rebinding rejected in checked modules.
3. Pending and reconciliation types for PRD section 10: send consumes,
   await yields the four-way outcome, `OutcomeUnknown` yields no endpoint.
4. Diagnostics with consuming site and reuse site.
5. Negative corpus: aliasing, reuse after branch join, capture in a closure,
   an impure dependency behind a pure wrapper, a copied endpoint used after
   commit (acceptance matrix row 4).

Exit evidence: positive and negative corpus with the specified diagnostics;
the checker's own evidence label is `ProtocolChecked`, nothing stronger.

### M4 OTP integration

Goal: the reservation service runs live under supervision with the same
observable behavior as the interpreter.

Depends on U1 and U2 landing upstream and the pin being bumped; the ownership
probes from M0 turn from asserting failure to asserting success in the same
change.

1. OTP application: supervision tree, environment owner process (serializes
   declarations and compiles; handlers call only immutable versioned
   definitions), ingress process, service instances.
2. Typed codecs for transferable values with recursive validation; mutable
   vectors and dictionaries rejected at the boundary unless frozen.
3. Generator from checked IR to gen_statem or gen_server modules using the
   backend chosen in ADR 0003; ADR 0004 justifies the mapping by observable
   semantics and tests.
4. Incarnation semantics on restart; bounded dedup retention with explicit
   "reconciliation unavailable" after expiry.
5. Ingress limits: no per-request atom creation, bounded abuse handling,
   worker PIDs hidden behind ingress.
6. Live tests for acceptance matrix rows 1, 2, 5, 6, 7, 11, 12, 15, 16.

Exit evidence: reservation service live; ownership and restart tests pass;
`RuntimeValidated` claims attached to the artifact.

### M5 Simulation and conformance

Goal: reproducible exploration and model-versus-live agreement.

1. Choice tape, virtual time, timer generations, fault choices (crash,
   restart, drop, delay) in the simulator.
2. Seeded exploration with bounds and Inconclusive verdicts; bounded
   exhaustive exploration on tiny cases; shrinking that preserves protocol
   validity.
3. Trace normalization (PIDs and refs to logical ids; no timestamps) and
   replay of recorded live admission order against the model, with permitted
   partial orders for concurrent runs.
4. Independent validators and hand-authored reference scenarios so a shared
   IR bug cannot hide.
5. Acceptance matrix rows 3, 8, 9, 10 as explored properties with
   counterexamples when deliberately broken.

Exit evidence: model/live comparison reports for recorded schedules;
reproducible race counterexamples; `BoundedExplorationPassed` and
`TraceConformant` claims naming their bounds.

### M6 Invariant evidence and release

1. Local preservation obligations generated from the IR for the inventory
   invariant; derivations via sequent rules or Prolog search.
2. Small independent derivation checker for the supported fragment; search
   exhaustion is `Unknown`, never `Proven`. ADR 0005 names the fragment.
3. Deliberately broken transition rejected (acceptance row 14).
4. Benchmarks against a handwritten OTP equivalent and the existing backend,
   with the reporting requirements of PRD section 23; regression budgets set
   from the first credible numbers.
5. Release docs: guarantee table by evidence label, exclusions, operational
   limits.

Exit evidence: one invariant `InvariantProven` under named assumptions,
broken variant rejected, full acceptance matrix with results, benchmark
report with raw data.

**Dependencies.** M1 after the M0 corpus. M2 after ADR 0002, independent of
M1. M3 and M4 after M2; M4 also after U1, U2 and a pin bump. M5 starts with
M2 and finishes after M4. M6 after M3 and M5.

## 5 Upstream items for shen-erl

General runtime improvements, per ADR 0001. Each is an upstream PR against
shen-erl followed by a pin bump here, with `make baseline` on both sides.

| Id | Problem (from section 1) | Change in shen-erl | Needed by |
| --- | --- | --- | --- |
| U1 | `dict_new/0` creates a named ETS table and an atom per dictionary and vector | Unnamed tables (`ets:new(Name, [set])` returning a tid); `{vector, Len, Tid}` and `{dict, Tid}`; update `shen_erl_interop:to_shen/1` guards and equality; explicit delete on owner cleanup | M4 (owner-local mutable state), M0 probes measure it |
| U2 | Stores and boot run in the `-s` init process; nothing is supervised; writes from other processes fail | An OTP application with a supervised environment owner that owns the store tables and serializes `eval`, `load` and definitions; an embedding API (`shen_erl:start/0`, `shen_erl:eval/1`, `shen_erl:call/2`) whose contract states that reads from any process work and writes go through the owner; the launcher keeps its behavior by starting the application | M4 (environment owner), M1 (spike embeds the compiler) |
| U3 | Compiler entry points are internal (`compile/3` returns a loaded-or-not binary; `invoke/2` is the dispatch) | A stable compiler interface: compile KLambda forms to Erlang abstract forms or to a binary without loading, expose dispatch semantics, expose arity lookup | M1 (LFE spike reuses the pipeline), M4 (generator embeds handler code) |
| U4 | Every non-defun `eval-kl` loads a never-purged random module; growth unmeasured | Measure first (M0 probe). If growth is a problem, purge anonymous top-level modules after `kl_tle/0` where no closure escapes, or evaluate simple forms without a module. Closures referencing a purged module fail with `badfun`, so this change needs its own corpus cases | M1 decision, long-running services |
| U5 | `erl.receive/1` is a catch-all; generic interop is lossy | No code change. Document that embedders must not use them for OTP traffic; the actor runtime uses its own ingress and codecs | Documentation only |

What stays here: the checked subset and its prohibitions, affine endpoints,
the effect vocabulary, envelope validation, the ledgers, incarnation rules,
codecs for transferable values, simulation, conformance, evidence labels.

## 6 Backend spike detail (M1)

- Both candidates compile the same inputs: the pinned kernel `.kl` files and
  the M0 corpus. The existing path is the pinned shen-erl unchanged.
- The LFE emitter produces LFE forms from the parsed KLambda AST
  (`shen_erl_kl_parse`), reusing `shen_erl_kl_primitives`,
  `shen_erl_kl_overrides` and the global stores, so differences are the
  emitter's, not the runtime's.
- Dynamic features to cover: `eval-kl` of non-defuns, redefinition with
  changed arity through `invoke`, `freeze`/`thaw`, `trap-error` mapping to
  `try`, `%%let-label`/`%%goto-label` factorization, string boxing
  `{string, Chars}`, boolean assertion.
- Measurements: wall-clock to compile the kernel; corpus run time; module
  and atom counts after N evals; BEAM size; emitter line count; whether
  source locations survive to stack traces.
- Pinned versions: LFE and OTP from the flake; recorded in ADR 0003.
- The decision is made once with evidence attached. A second production
  emitter is kept only if a demonstrated maintenance or verification benefit
  pays for it.

## 7 Evidence and decision records

Evidence labels, used on artifacts and in docs exactly as PRD section 14
defines them: `TypeChecked`, `ProtocolChecked`, `RuntimeValidated`,
`InvariantProven` under named assumptions, `BoundedExplorationPassed` under
named bounds, `TraceConformant`. A test suite passing is reported as a test
suite passing.

Expected ADRs: 0002 surface grammar and failure taxonomy (M0); 0003 backend
(M1); 0004 gen_statem versus gen_server mapping (M4); 0005 first proof
fragment (M6); 0006 immutable domain-value representation (M2 or M4);
0007 baseline resource limits (M4). Each carries a runnable example or a
measurement.

## 8 Immediate next steps

In order, each a small reviewable change:

1. This change: skeleton, pin, flake, Makefile, README, PRD, ADR 0001, plan.
2. CI workflow running `make baseline`, `make ct`, `check-pins.sh`;
   `tests/BASELINE.md` with the numbers from section 9. (Done.)
3. Ownership probe suite asserting today's behavior. (Done.)
4. Semantic regression corpus and its runner. (Done.)
5. Resource probes (eval and vector growth) with numbers. (Done.)
6. ADR 0002 grammar draft with parsed reservation examples and the failure
   taxonomy; `bin/shen-actor` stub. (Done; ADR proposed, awaiting review.)
7. Upstream PRs to shen-erl for U3 (compiler interface) and U1 (unnamed
   tables), opened once probes and corpus exist to review them against.
8. M1 spike begins.

## 9 Baseline reproduction record

Environment: this session's container, `nix develop` on the pinned shen-erl
flake (nixpkgs `ac6b216`), network through a proxy.

| Step | Result |
| --- | --- |
| `make` (kernel fetch, checksum, compile 22 KLambda modules) | Compiled successfully |
| `make shen-tests` (ShenOSKernel 42.2 `runme.shen`) | passed 143, failed 0, pass rate 100%, run time 188 s |
| `make ct` (codegen, overrides, interop, json suites) | 46 ok, 0 failed of 46 |
| Erlang/OTP from the pinned nixpkgs | OTP 28 |

Notes:

- shen-erl's README states OTP 27 or newer and its Docker target uses
  `erlang:27.3`; the Nix toolchain resolves to OTP 28. Both are in play. The
  CI job should record the version it ran on, and the M4 ADR on resource
  limits should name the OTP version its numbers were taken on.
- The kernel test run is the slow step at about three minutes. The gate stays
  mandatory on every change; M0 may add a faster pre-check (corpus only) for
  local iteration, but not as a substitute.
- Results were produced by shen-erl's own Makefile targets on the pinned
  commit with no modification, which is exactly what `make baseline` in this
  repository runs.
