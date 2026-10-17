# simulator/

Reference execution and exploration over the checked actor IR (PRD sections 7
and 18).

- Reference step interpreter: `step(Protocol, DomainState, SessionLedger,
  Event) -> Accepted | Rejected`. The semantic authority the runtime is
  compared against.
- Simulator state: actors, logical mailboxes, timers, in-flight commands,
  external-world model, virtual time, choice tape.
- Explorer: seeded random first, bounded exhaustive on tiny cases next;
  partial-order and symmetry reduction only after the baseline is correct.
- Bounds and verdicts: exceeding a bound is Inconclusive, never a proof.
- Shrinking that preserves protocol validity for valid-run campaigns.

Milestones: reference interpreter in M2, choice tape, virtual timers, explorer
and shrinking in M5.
