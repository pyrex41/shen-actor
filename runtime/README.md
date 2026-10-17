# runtime/

Session enforcement and OTP integration, in Erlang (PRD sections 11, 12, 15,
16).

- Envelope validation in the specified order: shape and limits, protocol and
  version, incarnation, session and role, generation, operation dedup, phase
  and tag, payload, domain precondition.
- Session ledger and operation ledger: generation advancement committed with
  the result or pending record in one serialized local step; duplicates return
  the known result; same id with a different digest is `OperationConflict`.
- Ingress: a loop that consumes and classifies envelopes so malformed traffic
  never waits in a mailbox; bounded, configurable abuse handling.
- Typed codecs for transferable values; generic shen-erl interop conversion is
  lossy and is not the wire specification.
- OTP application and supervision tree: environment ownership, ingress,
  service instances; gen_statem or gen_server per the M4 ADR.
- Incarnation semantics: restart gives a fresh incarnation; old sessions fail
  with `StaleIncarnation`.

Everything here is behavior shen-erl does not own. Changes shen-erl itself
needs (ETS ownership, embedding API, environment owner) are upstream items;
see docs/plan.md.
