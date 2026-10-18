# ADR 0002: Surface grammar, failure taxonomy and the inventory invariant

Status: proposed · 17 October 2026

## Context

PRD section 8 gives illustrative protocol syntax and says the first frontend
milestone must freeze a grammar with runnable examples before the syntax is
normative. Plan M0 step 6 asks for that grammar (protocol form, checked
module form, handler and command syntax), the failure taxonomy as the closed
set of rejection reasons from PRD sections 10, 11 and 16, and the inventory
invariant M6 will prove. M2's parser and validators, M3's checker and M4's
codecs all key off these names, so they are fixed before any of that code
exists.

The forms must be read by the pinned kernel reader. One fact found while
writing the examples decides how: `read-file` macroexpands what it reads,
turning an unknown head into a curried application, so `(protocol p ...)`
arrives as `[[fn protocol] p ...]`. `read-from-string-unprocessed` over
`read-file-as-string` returns the forms unchanged, except that `[...]`
still reads as `cons` forms and `{...}` as the symbols `{` and `}`.
`language/read.shen` is that reader.

## Decision

### Reading

Actor-language files are Shen source read unprocessed by
`actor.read-file`. Keywords are plain symbols matched by position. Ordinary
Shen (`define`, `let`, `if`, type signatures in `{...}`) appears inside
handler bodies and `checked` modules unchanged. Comments use `\\`.

### Payload types

The transferable types of PRD section 12. A session endpoint is not a
payload type (PRD section 9).

```text
Type ::= number | boolean | string | operation-id
       | (nat-range Lo Hi)                 bounded integer, inclusive
       | (symbol-of Sym ...)               controlled symbol vocabulary
       | (list-of Type) | (map-of Type Type)
       | (service ProtocolName)            shareable service reference
       | RecordName

(record RecordName (Field Type) ...)
```

### Protocols

```text
(protocol Name
  (version N)
  (roles Role Role)
  (initial Phase)
  (phase Phase Event ...) ...
  (terminal Phase ...)?           phases with no further obligation
  (repeatable Phase ...)?)        phases a service protocol stays in

Event ::= (message Tag (from Role) (to Role) (payload Type)?
            (outcome OutcomeTag (payload Type)? (opens Protocol Role)? (then Phase)) ...)
        | (timeout Name (owner Role) (then Phase))
```

- A message's sender owns the choice among a phase's messages; the receiver
  owns the choice among its outcomes. A timeout's owner is explicit. This is
  the "identified owner" of PRD section 8.
- `(opens P R)` on an outcome returns a fresh endpoint for role `R` of
  protocol `P` in its initial phase. Service admission is therefore an
  ordinary protocol whose outcome opens a session (PRD section 8).
- Every message not listed in a phase is rejected in that phase with
  `UnexpectedMessage`. That is the reject policy of PRD section 8; `defer`
  is reserved and not part of this grammar.
- Duplicate tags in one phase must agree on payload type, or the
  elaborator rejects them.

### Actors

```text
(actor Name
  (implements Protocol Role) ...
  (state (Field Type) ...)
  (session-state Protocol Type)?   per-session data held in the session ledger
  (init Result)
  (handle Protocol Phase Tag (Bindings ...) Body) ...
  (on-timeout Protocol Phase TimerName (Bindings ...) Body) ...
  (invariant Name Predicate) ...)

Result  ::= (accept NewState [Command ...]) | (reject Reason)
Command ::= (reply OutcomeTag Payload?)
          | (send ServiceRef Tag OperationId Payload)
          | (open-session Protocol SessionState)
          | (start-timer Name Milliseconds) | (cancel-timer Name)
          | (invoke-effect Adapter Request)
```

Handler bindings are the session state (absent for service protocols),
the payload where one is declared, and the domain state, in that order.
A body is checked Shen returning a `Result`. `reject` leaves domain state
and session untouched (PRD section 7). The outcome a `reply` names decides
the session's next phase. Timer events carry the generation of the session
that started them, so a cancelled timer firing late is rejected as
`StaleGeneration` before any handler runs (acceptance row 9).

### Checked modules and clients

```text
(checked Name
  (uses Protocol Role) ...
  (define ...) ...)                ordinary Shen define with a type signature

(send Endpoint Tag OperationId Payload)   consumes Endpoint, returns a pending handle
(await Pending
  (succeeded OutcomeTag Continuation Body) ...
  (rejected Reason Continuation Body)
  (unavailable Body)
  (outcome-unknown OperationId Body))
(reconcile ServiceOrEndpoint OperationId)
```

Session types are `(session Protocol Role Phase)`; `_` discards a
continuation. `await` must list all four outcome kinds (PRD section 10).
`outcome-unknown` binds no endpoint. Recovery goes through `reconcile` with
the same operation identifier. A checked module may not use `eval-kl`,
`erl.apply`, mutable globals or redefinition (PRD section 13); M3 enforces
this.

### Failure taxonomy

The closed set of reasons the runtime returns, in the validation order of
PRD section 11. The first failing check decides the reason. Nothing
earlier than `PreconditionFailed` reaches domain code.

| Reason | Check | Mutation |
| --- | --- | --- |
| `MalformedEnvelope` | envelope shape, field types | none |
| `LimitExceeded` | envelope or payload size bounds | none |
| `ProtocolMismatch` | protocol identifier or version unknown to this service | none |
| `StaleIncarnation` | token names an earlier incarnation (PRD section 16) | none |
| `UnknownSession` | session not in the ledger, or tombstoned | none |
| `WrongRole` | sender role differs from the endpoint's role | none |
| `StaleGeneration` | expected generation differs from the ledger's | none |
| `OperationConflict` | known operation identifier, different request digest | none |
| `ReconciliationUnavailable` | operation record expired from bounded retention (PRD section 16) | none |
| `UnexpectedMessage` | tag not accepted in the session's current phase | none |
| `InvalidPayload` | payload does not match the message's declared type | none |
| `PreconditionFailed` | handler returned `(reject Reason)`; carries `Reason` | none |

A duplicate of a known operation with the same digest is not a rejection.
It returns the recorded result or pending status (PRD section 11).

What a client's `await` sees (PRD section 10):

| Outcome | When |
| --- | --- |
| `succeeded` | an outcome the protocol declares, with its continuation |
| `rejected` | one of the reasons above, from the service; carries the continuation the protocol specifies, if any |
| `unavailable` | non-execution is known (admission or transport refused before execution) |
| `outcome-unknown` | anything else, including timeout; no endpoint |

The elaborator's diagnostics (PRD section 8) are a separate,
compile-time set: `UndefinedPhase`, `UndefinedRole`, `MissingDestination`,
`UnreachablePhase`, `AmbiguousBranchOwner`, `IncompatibleDuplicateTag`.
M3's checker diagnostics are named when M3 fixes them.

### Inventory invariant (M6)

For the actor in `examples/reservation/inventory.shen`, for every item `i`:

```text
stock(i) = available(i) + held(i) + committed(i)
available(i) >= 0, held(i) >= 0, committed(i) >= 0
```

where `held(i)` is the sum of `quantity` over sessions in phase `open` whose
session state names `i`. `init` establishes it: nothing is held or
committed. Each handler must preserve it as a local obligation (PRD section
14). `reserve` moves quantity from `available` into a new open session.
`commit` moves a session's quantity into `committed`. `cancel` and the lease
timeout return it to `available`. `held` is defined over the session ledger,
so the obligation spans domain state and ledger. That is why
`session-state` is part of the actor form rather than hidden inside domain
state.

### Examples

`examples/reservation/` holds the admission and reservation protocols, the
inventory actor, a checked client, and `reuse-rejected.shen` (acceptance row
4, which M3 must reject). `make examples` reads each file with
`actor.read-file` and compares a structural summary against
`tests/grammar/examples.expected`. They are data until M2 interprets them.

## Consequences

- M2's parser consumes exactly these forms; a grammar change updates this
  ADR, the examples and `examples.expected` together.
- The taxonomy is closed: adding a reason amends this ADR. M2's ledger and
  M4's ingress return these names and no others.
- `read-file` is never used for actor-language source.
- Open, to settle in M2: `[...]` reading as `cons` means record and list
  literals in handler bodies are ordinary Shen expressions, not data; the
  elaborator treats them as code. Concrete record literal syntax waits on
  ADR 0006 (immutable domain-value representation).
