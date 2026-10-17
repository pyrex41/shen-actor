# language/

Protocol frontend and checker, written in Shen and loaded through the pinned
shen-erl.

- Protocol forms: parse `(protocol ...)` declarations alongside ordinary Shen
  computations (PRD section 8).
- Elaborator: roles, phases, schemas, branches, and obligations into the
  canonical protocol graph in `ir/`; rejects missing destinations, unreachable
  mandatory phases, ambiguous branch ownership, conflicting tags, and undefined
  phases.
- Actor checker: types, affine endpoint use (Gamma/Delta contexts), closed
  effect checking, total event handling, proof obligations (PRD sections 9,
  13, 14).
- Diagnostics: source span, protocol, role, phase, operation, failed rule, and
  a repair where available (PRD section 20).

Milestones: grammar freeze in M0, elaborator in M2, checker in M3.
