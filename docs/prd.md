# Shen BEAM Protocol Actors PRD and Technical Specification

Version 0.1 · Draft for implementation · 17 October 2026

## 1 Purpose and product decision

Build a protocol-oriented actor language embedded in Shen, running as ordinary supervised BEAM processes. Protocols, session ownership, state transitions, and effects are explicit language concepts. The same defined semantics support static checking, deterministic simulation, runtime enforcement, and execution through OTP.

This is proposal B. A library that merely wraps Shen functions in OTP callbacks does not satisfy the product requirements. A small OTP adapter is an implementation component, not the product boundary.

The language must provide useful guarantees beyond message payload typing: checked clients follow permitted conversations, session endpoints cannot be reused after consumption, transitions preserve declared invariants where discharged, and failures have explicit outcomes. The system must state precisely which guarantees come from static checking, runtime validation, proofs, or bounded exploration.

Working descriptor: Shen Protocol Actors. Naming is not a release dependency.

## 2 Users and primary workflows

The primary user is a developer building stateful services whose correctness depends on interactions over time: reservations, job execution, leases, workflows, resource ownership, and orchestration.

The developer defines a protocol and state transition logic, receives understandable diagnostics, simulates concurrent clients and faults, then runs the checked artifact under OTP. Existing Erlang, Elixir, LFE, and Gleam applications can invoke generated boundary APIs without adopting Shen wholesale.

An implementation agent must be able to build the system from this specification with the pinned Shen kernel suite as continuous compatibility backpressure. Passing a toy actor example is insufficient.

## 3 Success criteria

The first useful release must demonstrate all of the following:

1. A shared reservation service creates multiple independent sessions without requiring one process per session.
2. A checked client attempting to reuse a consumed endpoint is rejected before execution.
3. An unchecked client sending a stale generation is rejected before domain mutation.
4. The simulator and live adapter agree on normalized observable traces for recorded schedules within the modeled boundary.
5. Timeout followed by retry cannot silently be treated as proof that the original operation did not happen.
6. Actor restart invalidates old ephemeral sessions using a new incarnation identifier.
7. Ordinary Shen continues to boot the unmodified pinned kernel and pass the complete compatibility suite.
8. At least one nontrivial invariant is established by an independently checked derivation, with a deliberately broken transition rejected.

## 4 Scope and exclusions

Initial scope: a single BEAM node; shared services; two-party sessions; explicit immutable domain state; request/reply; explicit timeouts and cancellation; declared effects; supervised processes; deterministic simulation; protocol monitors; affine endpoint checking; versioned artifacts; an interop boundary.

The initial language excludes arbitrary selective receive in checked actor code, unrestricted endpoint capture in closures, arbitrary dynamic evaluation in checked modules, transparent distributed session recovery, general multiparty protocol inference, unrestricted hot code replacement, and blanket claims of deadlock freedom or exactly-once external effects.

Distribution may be modeled as fault events before a distributed runtime is implemented. A modeled capability is not evidence of a production capability.

## 5 Baseline repository and compatibility

The inspected baseline is pyrex41/shen-erl commit ea5380a433d4d4281d4ea4dd88c0ade290028a6c. It compiles KLambda to Erlang abstract forms using compile:forms, boots the community ShenOSKernel 42.2, and has Erlang interop for apply, send, receive, and tuple construction.

The existing stores use named protected ETS tables for global values, function bindings, and allocation counters. Vectors and dictionaries carry ETS table references represented by names. These choices require an explicit concurrency redesign; changing ETS protection to public does not establish actor isolation.

Compatibility requirements:

- Preserve the upstream kernel unchanged, including compiler, typechecker, Prolog, YACC, macros, packages, and ordinary dynamic evaluation.
- Preserve standard Shen evaluation order, currying, computed application, closures, freeze/thaw, errors, equality, and mutable-value semantics in ordinary Shen.
- Preserve existing launcher behavior and supported interop unless a separately documented compatibility change is approved.
- Keep checked actor modules distinct from unrestricted Shen execution. Restrictions inside checked modules do not silently change ordinary Shen.
- Record the actual current repository revision before implementation; reconcile later changes against this baseline.

## 6 Architecture

There are six logical components:

| Component | Responsibility |
| --- | --- |
| Shen frontend | Parse protocol forms and ordinary Shen computations |
| Protocol elaborator | Resolve roles, phases, schemas, branches, and obligations into a canonical protocol graph |
| Actor checker | Check types, endpoint use, effects, total event handling, and proof obligations |
| Checked actor IR | Preserve protocol identity, handlers, state, commands, and source locations |
| Execution backends | Interpret in simulation or lower into LFE/Erlang OTP modules |
| Runtime boundary | Validate envelopes, enforce sessions, execute effects, manage lifecycle and tracing |

The protocol graph is language-neutral. KLambda remains the computation representation for ordinary Shen. Actor semantics must survive until actor checking completes; do not erase protocols into opaque ordinary function calls first.

A module representation joins lowered computation and actor machinery. It may contain functions, calls, patterns, receive constructs, exports, callbacks, literals, and source metadata. Reuse the existing backend if this representation adds no value; do not create an abstraction merely to support hypothetical emitters.

## 7 Semantic model

An actor instance contains a logical service identifier, an incarnation identifier, protocol version, domain state, session ledger, pending effect ledger, and runtime metadata. A service reference identifies a shareable entry point. A session endpoint identifies a role in one interaction and carries an expected phase and generation.

An abstract event step is:

```text
step(Protocol, DomainState, SessionLedger, Event)
  -> Accepted(NewDomainState, NewSessionLedger, Commands)
   | Rejected(Reason)
```

Rejected events do not mutate domain state or advance sessions. Diagnostic counters may change in the runtime layer. Accepted transitions commit the local state and ordered command intent before effect results are delivered as later events. This is a semantic boundary, not a transaction spanning external systems.

The simulator state additionally contains actors, logical mailboxes, timers, in-flight commands, an external-world model, virtual time, and a choice tape. Explicit scheduler actions select one enabled event delivery or fault. One transition is run to completion in the abstract semantics; divergence or a resource limit is a failed or inconclusive execution, never a successful transition.

## 8 Protocol language

Protocols declare named roles, phases, messages with payload schemas, accepted outcomes, cancellation, timeout events, and terminal phases. Branch choice has an identified owner. External nondeterministic outcomes are explicit events, not hidden calls inside transition logic.

Illustrative syntax below communicates intent; the first frontend milestone must freeze a grammar and runnable examples before treating this syntax as normative:

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

Service admission is a separate protocol: reserve may reject or return an open reservation endpoint. A single inventory actor can hold many reservation sessions. Protocol phase describes one session, not the whole shared service state.

The elaborator rejects missing destinations, unreachable mandatory phases, ambiguous ownership of a branch, duplicate message tags with incompatible schemas in one phase, and references to undefined phases. Recursive graphs must be explicit and finite as representations; execution may revisit phases.

Every application event has a defined policy in every relevant phase: accept, reject, or an explicitly modeled defer. Initial release supports accept and reject; defer is reserved until its queue semantics are specified.

## 9 References and endpoint ownership

Conceptual types:

```text
ServiceRef(Protocol, Version)
SessionRef(Protocol, Version, Role, Phase)
OperationId
Outcome(ResultType)
```

Service references are unrestricted and shareable. Session endpoints are affine: a checked program may use one at most once. An operation consumes an endpoint and returns a continuation endpoint or a terminal outcome. Abandonment is permitted; cancellation and lease expiry provide application policies for cleanup. Affinity does not promise eventual completion.

The checker maintains an unrestricted context Gamma and affine context Delta. Session send consumes an entry from Delta. Branches must reconcile endpoint ownership: a value consumed on one branch cannot reappear after the join. Returned continuations must have compatible types or an explicit tagged sum. Initial release disallows affine values in unrestricted lists, maps, global variables, message payloads, or arbitrary closures. Dedicated affine aggregates and delegation are future features.

No implicit copy, serialization, or unsafe declaration may manufacture a checked endpoint. Boundary construction validates an external token and yields a dynamically checked endpoint with explicitly recorded trust. An affine type protects checked usage; runtime ledger validation remains mandatory because raw BEAM messages can bypass generated clients.

## 10 Request and continuation semantics

Sending begins an operation and consumes the ready endpoint. It produces a pending handle, not an immediately advanced endpoint. Awaiting the handle yields a tagged result:

| Outcome | Meaning |
| --- | --- |
| Succeeded | Authoritative successful result; contains continuation if the protocol continues |
| Rejected | Authoritative rejection with specified continuation or termination |
| Unavailable | Admission or transport could not establish execution; only use when nonexecution is known |
| OutcomeUnknown | Execution may have happened; no reusable ready endpoint is fabricated |

A timeout yields OutcomeUnknown unless stronger evidence exists. Recovery uses the same operation identifier through a status/reconcile operation defined by the protocol. Retrying with a fresh identifier is a new operation and must never be silently substituted.

Late replies are correlated to pending operations. A reconciled result may resolve an unknown outcome once. Duplicate replies cannot create duplicate affine continuations. Dropped pending handles do not cancel server execution implicitly.

## 11 Wire representation and runtime enforcement

The native internal envelope contains protocol identifier and version, service identifier, incarnation, session identifier where applicable, sender role, expected generation, operation identifier, message tag, payload, and reply correlation information. These fields use fixed atoms for structure and bounded data for values; user input must not create unbounded atoms.

Validation order: envelope shape and limits; protocol/version; actor incarnation; session existence and role; generation; operation deduplication; phase/message; payload; domain precondition. Validation errors return structured reasons where a safe reply path exists.

For accepted session operations, generation advancement and the operation result or pending record are committed together in the actor's serialized local step. A duplicate of the same operation returns its known result or pending status rather than executing again. Reusing an operation identifier with a different request digest is an error.

Malformed traffic must not be held indefinitely in a mailbox waiting for a matching receive. A runtime ingress loop consumes envelopes and classifies them. Abuse handling is bounded and configurable. This does not prevent an arbitrary process with the raw PID from filling the BEAM mailbox; strong admission control requires hiding worker PIDs behind a controlled ingress and imposing limits there.

Tuple/list conversion in the existing generic interop is lossy. Typed actor codecs must be explicit and preserve protocol representation. Do not reuse implicit generic conversion as the wire specification.

## 12 Domain state and Shen environments

Actor domain state consists of immutable transferable values passed explicitly through handlers. Initial transferable values are bounded numbers, booleans, symbols from a controlled vocabulary, strings, lists, immutable records/maps, and actor references. Mutable vectors, dictionaries, streams, host closures, ETS identifiers, and arbitrary opaque host objects are not transferable by default.

Mutable Shen objects remain owner-local in ordinary Shen. Provide explicit freeze/copy operations into immutable actor values and explicit reconstruction when needed. Nested values must be checked recursively, including closure captures if later supported.

Compiler state and runtime domain state are separate. A supervised environment owner serializes changes to declarations, macros, function bindings, and global kernel state. Checked handlers execute only immutable versioned definitions and declared pure dependencies; a compiler owner is not a bottleneck on every message transition.

A process dictionary may hold an internal environment handle, but must not define application semantics. Eliminate global allocation-name dependence from actor-local allocation. Prefer unnamed ETS tables for owner-local mutable resources and explicit cleanup. Audit vector/dictionary lifetime and atom growth before claiming long-running service readiness.

## 13 Effects and checked computation subset

Handlers compute new state and commands. The initial command vocabulary includes Reply, Send, StartTimer, CancelTimer, and InvokeEffect. Lifecycle and durable storage commands are added through versioned schemas, not arbitrary host terms.

Each effect adapter declares request/result schemas, failure outcomes, idempotency behavior, and simulator behavior. Time, randomness, filesystem access, network access, process operations, and persistence are effects. Their results reenter as explicit events.

The checker permits only known pure computations or declared effect constructors in checked handlers. Initially use a closed call graph and conservative whitelist. Unknown higher-order callees, mutable global access, arbitrary erl.apply, eval-kl, and unchecked dynamic rebinding are rejected. Ordinary Shen retains those facilities outside checked modules.

Purity must be checked transitively. A pure-looking wrapper around an impure primitive is still impure. Host functions enter through explicit contracts and are part of the trusted boundary. Type annotations alone are not evidence of purity or invariant preservation.

## 14 Proof obligations and claims

Each invariant claim names its predicate, transition definitions, assumptions, dependency digests, and proof method. The first supported obligation is local preservation:

```text
Invariant(state) and Precondition(state, event)
  and Transition(state, event, next, commands)
  implies Invariant(next)
```

Initialization must establish the invariant separately. Command constraints, such as total requested quantity not exceeding available stock, may require additional predicates. Effects cannot be assumed successful unless their returned events establish that result.

Shen may generate derivations using sequent rules or Prolog search. A small separate derivation checker must validate the supported proof fragment. Arbitrary user-defined type rules are not automatically accepted as trusted axioms. Search timeout produces Unknown, not Proven; unsupported obligations remain explicitly unproved.

The implementation must label evidence as one of: TypeChecked, ProtocolChecked, RuntimeValidated, InvariantProven under named assumptions, BoundedExplorationPassed under named bounds, or TraceConformant. Passing tests does not become a proof. Local protocol safety does not imply global progress.

## 15 OTP execution

Use an OTP application and supervision tree for environment ownership, ingress, and service instances. gen_statem is the default candidate for protocol-heavy services; gen_server remains valid where an explicit session ledger better represents concurrent sessions. The backend must justify the selected mapping through observable semantics and tests.

OTP's internal messages and supervision events belong to the adapter. Application receive code must not accidentally consume call envelopes or DOWN messages through the existing catch-all erl.receive helper.

Handlers do not block awaiting another actor. They emit a command and record pending state, then process the correlated result event. Long pure computations must yield through explicitly modeled continuation steps or run as supervised jobs with result events. Resource limits must produce explicit failure observations.

Native BEAM scheduling is not deterministic. Production supports tracing and controlled test ingress; deterministic replay is guaranteed only within the declared simulation/effect boundary.

## 16 Restart and durability

The default service is ephemeral. Restart creates a fresh incarnation and initial domain state. Old session tokens fail with StaleIncarnation. Stable service discovery may return the new instance, but cannot silently revive old sessions.

Deduplication is bounded by documented retention and incarnation. Once an operation record expires, the API must report that authoritative reconciliation is unavailable rather than reexecute an old identifier as if unseen. Session tombstones or nonreuse rules prevent accidental resurrection.

A later durable profile persists domain transitions, session generations, operation outcomes, and command intents atomically in a journal. An outbox executes effects after durable commit. Adapters still require idempotency keys or reconciliation for effects that may complete before acknowledgement. No exactly-once external effect guarantee is provided merely by a journal.

## 17 Backend evaluation and decision gate

Preserve semantics, not the current compiler implementation. The existing Erlang forms backend and a KLambda-to-LFE backend must be evaluated as real alternatives. Core Erlang is an optional investigated alternative, not a required third implementation.

The LFE spike initially reuses runtime primitives, compiles the unmodified pinned kernel, supports dynamic evaluation/redefinition, and emits one protocol actor. Pin LFE and OTP versions and include them in the reproducible development environment.

Evaluate kernel compatibility, currying, computed calls, closure behavior, freeze/thaw, error propagation, dynamic function arity changes, source locations, native pattern matching, module lifecycle, compile latency, execution overhead, and implementation complexity. Test repeated eval for module/atom growth and code-version retention.

Decision rule: choose LFE if it preserves compatibility and materially simplifies the compiler and actor generation without an unacceptable measured regression. Choose existing Erlang forms if it remains simpler. Record results and the decision in a backend ADR. Retain two production emitters only if a demonstrated maintenance or verification benefit pays their cost; a shared IR is not a commitment to two permanent backends.

## 18 Simulation and exploration

The simulator interprets checked actor IR and effect models using virtual time and recorded choices. A run records artifact digests, initial state, bounds, external events, scheduler choices, and normalized observations. Replaying the same run reproduces its abstract execution exactly.

The scheduler preserves modeled per-sender/per-destination ordering. Separate senders may interleave. Delivery, timer firing, effect completion, actor crash, and restart are explicit choices. Timer cancellation does not erase a timeout event already admitted for delivery; timer generations make stale events harmless.

Bounds include actor count, session count, queue length, event count, payload size, transition fuel, virtual time, and fault count. Exceeding a bound is Inconclusive or a configured resource property failure, never a clean proof of safety. Liveness checks require explicit fairness and environment assumptions.

Begin with reproducible seeded exploration and bounded exhaustive exploration on tiny cases. Partial-order reduction and state symmetry reduction follow only after the baseline explorer is correct. Shrinking must preserve protocol validity for valid-run campaigns; invalid-input campaigns retain their intended violation.

## 19 Conformance and trace semantics

Observations include accepted/rejected protocol events, authoritative results, committed state digests, command intents, effect completions, timeouts, crashes, and incarnation changes. Normalize host PIDs and references into stable logical identifiers; do not compare wall-clock timestamps or incidental log order.

Live runs record the admitted event order. Replay that order against the model and compare observable behavior, allowing explicitly specified internal stuttering. Concurrent runs are checked against permitted partial orders rather than one arbitrary global sequence. State snapshots are taken at defined transition boundaries.

Using the same IR in both paths provides consistency but can conceal shared mistakes. Maintain hand-authored reference scenarios, independent protocol validators, negative checker fixtures, and differential backend tests. A complete compiler refinement proof is not an initial release requirement.

## 20 Developer interface and diagnostics

Proposed commands, to be integrated with the existing launcher rather than breaking it:

```text
actor check MODULE
actor simulate MODULE --seed N --bounds FILE
actor replay RUN
actor explain RUN
actor build MODULE --backend lfe|erlang
actor run MODULE
```

Diagnostics identify source span, protocol, role, current phase, operation, failed rule, and a concrete repair where available. Endpoint-reuse errors show the consuming site and reuse site. Counterexamples show the shortest retained event trace and the violated property. Proof search exhaustion is distinguishable from a false obligation.

Artifacts contain schema version, canonical protocol graph, checked actor IR, source map, effect contracts, kernel/compiler/backend versions, dependency digests, evidence claims, runtime profile, and content digest. A digest identifies bytes and dependencies; it is not proof of correctness or authenticity.

## 21 Reference application and acceptance matrix

Build an inventory reservation service with at least two items, competing clients, bounded stock, expiry, commit/cancel, operation reconciliation, and supervised restart. A session is a ledger entry rather than necessarily a process.

| Case | Required result |
| --- | --- |
| Successful reserve then commit | Stock accounting preserved; terminal result correlated |
| Insufficient stock | Rejected without allocation |
| Two concurrent reserves | No overselling under any explored permitted schedule |
| Commit then cancel using copied endpoint | Static rejection in checked client |
| Same operation sent twice externally | One transition; same result or pending status |
| Same ID with different payload | OperationConflict before mutation |
| Old generation with new operation | StaleGeneration before mutation |
| Expiry races with commit | One permitted winner; accounting remains valid |
| Cancelled timer arrives late | Stale timer ignored according to protocol |
| Reply lost after commit | OutcomeUnknown, then reconciliation returns committed |
| Actor restarts | Old sessions rejected with StaleIncarnation |
| Mutable nested vector in payload | Boundary rejection or explicit freeze required |
| Hidden impure dependency | Checked build rejection |
| Broken invariant transition | Failed derivation or concrete counterexample, never Proven |
| Envelope version mismatch | Structured rejection before interpretation |
| Unknown tag or malformed payload | Bounded rejection; actor stays responsive |

## 22 Delivery plan

Milestones are gates, not dates. Every milestone keeps the full existing Shen suite active and adds relevant Erlang/Common Test and actor-language checks.

| Gate | Deliverables | Exit evidence |
| --- | --- | --- |
| M0 Baseline and semantic decisions | Baseline build, ownership probes, grammar draft, failure taxonomy, invariant statement | Reproducible baseline and explicit failures; no inferred compatibility claims |
| M1 Backend spike | KLambda-to-LFE implementation, current backend comparison, actor skeleton, backend ADR | Full kernel results and semantic regression corpus for both candidates |
| M2 Protocol core | Canonical graph, validators, actor IR, reference step interpreter, runtime session ledger | Hand-authored valid/invalid traces and duplicate/stale cases pass |
| M3 Checked sessions | Affine checker, closed effect checking, pending/reconciliation types, source diagnostics | Positive/negative corpus covers aliasing, branches, closures, and hidden impurity |
| M4 OTP integration | Generated modules, supervised lifecycle, ingress, codecs, incarnation semantics | Reservation service works live; ownership and restart tests pass |
| M5 Simulation and conformance | Choice tape, virtual timers, bounded explorer, shrinking, trace replay | Model/live comparison and reproducible race counterexamples |
| M6 Invariant evidence and release | Small derivation checker, proof obligations, benchmarks, docs, examples | Inventory invariant checked, broken variant rejected, release matrix complete |

M1 can begin once M0 fixes the semantic regression corpus; M2 need not wait for the final backend decision because its interpreter is backend-independent. M3 and M4 depend on the protocol core. M5 begins with M2 and completes after live integration. M6 does not retroactively turn earlier checks into stronger guarantees.

Suggested small contributions: baseline ownership tests; environment owner; transferable-value codec; backend spike; backend decision; protocol grammar/elaborator; reference interpreter; session ledger; affine checker; effect checker; OTP generator; restart semantics; simulator; conformance; invariant derivation checker; release docs. Each contribution must state its supported guarantees and exclusions.

## 23 Performance and operational readiness

Compare generated services to handwritten equivalent OTP implementations and to the existing Shen backend. Workloads include tiny messages, larger immutable payloads, many sessions per actor, many actors, timer churn, duplicate requests, and error traffic.

Report throughput, p50/p95/p99 latency, scheduler utilization, memory per actor/session, mailbox growth, codec overhead, compile latency, proof/check time, and atom/module growth. Publish hardware, OTP/LFE revisions, workload definitions, repetitions, and raw measurements. Set numeric regression budgets after the first credible baseline; do not invent unsupported performance promises.

Operational acceptance requires bounded session/dedup retention, documented overload behavior, cleanup after owner termination, no per-request atom creation, and useful metrics for queue depth, pending effects, unknown outcomes, rejected generations, and restarts. Trace collection must have bounded retention and a payload-redaction policy.

## 24 Risks and safeguards

| Risk | Required mitigation |
| --- | --- |
| Programmable types mistaken for sound ownership | Dedicated affine checker and adversarial negative corpus |
| Model and runtime share a bug | Independent reference scenarios and validators |
| Dynamic rebinding invalidates claims | Immutable checked artifacts and dependency digests |
| ETS objects break isolation | Owner-local mutable state and recursive transfer validation |
| Backend migration consumes project | Time-bounded evidence gate; working baseline preserved |
| Failure semantics become accidental | Explicit unknown outcomes, generations, and operation ledger |
| Protocol monitor doubles application state | Generate monitor state and domain obligations from one IR |
| Proof search becomes unusable | Small supported fragment, bounded search, explicit Unknown |
| Mailboxes grow without bound | Controlled ingress and measured admission limits |
| Session types imply false progress claims | Separate safety, invariants, exploration, and liveness evidence |

## 25 Decisions and open questions

Committed design directions: B as the product; preserve ordinary Shen; explicit checked subset; shared services plus affine sessions; explicit effects; runtime validation for external traffic; ephemeral restart semantics first; one IR interpreted in simulation and lowered for OTP; LFE evaluated seriously.

Implementation decisions requiring evidence: LFE versus Erlang forms; exact surface grammar; gen_statem versus gen_server mapping; the first proof fragment; immutable domain-value representation; baseline resource limits; packaging as repository subdirectories versus a separate application. Resolve each in an ADR with a runnable example or measurement. None is a reason to replace B with an untyped OTP wrapper.

Future extensions: endpoint delegation, affine aggregates, durable sessions, distributed transport, protocol-compatible upgrades, multiparty composition, richer proofs, and optimized exploration. Each needs its own semantics and acceptance criteria.

## 26 Source references

Repository facts above are grounded in the inspected revision; proposed behavior in the remaining sections is a design requirement.

- [Baseline repository](https://github.com/pyrex41/shen-erl/tree/ea5380a433d4d4281d4ea4dd88c0ade290028a6c)
- [Global stores](https://github.com/pyrex41/shen-erl/blob/ea5380a433d4d4281d4ea4dd88c0ade290028a6c/src/shen_erl_global_stores.erl)
- [KLambda primitives](https://github.com/pyrex41/shen-erl/blob/ea5380a433d4d4281d4ea4dd88c0ade290028a6c/src/shen_erl_kl_primitives.erl)
- [Code generation](https://github.com/pyrex41/shen-erl/blob/ea5380a433d4d4281d4ea4dd88c0ade290028a6c/src/shen_erl_kl_codegen.erl)
- [Interop primitives](https://github.com/pyrex41/shen-erl/blob/ea5380a433d4d4281d4ea4dd88c0ade290028a6c/src/shen_erl_kl_extensions.erl)
- [OTP ETS ownership and access](https://www.erlang.org/docs/27/apps/stdlib/ets.html)
- [OTP state machines](https://www.erlang.org/docs/27/apps/stdlib/gen_statem.html)
- [BEAM process communication](https://www.erlang.org/docs/27/system/ref_man_processes.html)
- [LFE development resources](https://lfe.io/use/)
- [Gleam typed actor interface](https://gleam-otp.hexdocs.pm/gleam/otp/actor.html)

## 27 Implementation handoff

Start by reading repository instructions and reproducing the current build and full suites. Preserve dirty checkouts. Establish a clean baseline and record environmental blockers honestly. Add ownership and cross-process value probes before changing stores. Freeze the protocol grammar with executable examples, then implement the backend spike and protocol interpreter. Do not call a milestone complete based solely on a demonstration script.

Every completed change must include the supported semantic behavior, relevant positive and negative checks, compatibility results, remaining limits, and an updated milestone status. Unimplemented requirements stay planned. Evidence must name the exact artifacts and bounds it supports.
