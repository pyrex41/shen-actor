# examples/

The reference application and checked clients (PRD section 21).

`reservation/`: an inventory reservation service with at least two items,
competing clients, bounded stock, expiry, commit/cancel, operation
reconciliation, and supervised restart. A session is a ledger entry. The
acceptance matrix in the PRD is the test list for this example; every row
maps to a test under `tests/`.

The forms follow [ADR 0002](../docs/decisions/0002-surface-grammar.md).
Until M2 they are data: `make examples` reads them with `actor.read-file`
and checks their structure.

Examples are executable in three ways: through the reference interpreter, the
simulator, and the live OTP adapter, and the three must agree on normalized
traces within the modeled boundary.
