# ir/

Language-neutral representations shared by the checker, simulator, and
backends.

- Canonical protocol graph: the elaborator's output; roles, phases, messages,
  outcomes, terminals, branch owners.
- Checked actor IR: protocol identity, handlers, state, commands, and source
  locations. Actor semantics survive until actor checking completes; protocols
  are never erased into opaque function calls first (PRD section 6).
- Artifact format: schema version, graph, IR, source map, effect contracts,
  kernel/compiler/backend versions, dependency digests, evidence claims,
  runtime profile, content digest (PRD section 20).

KLambda remains the computation representation for ordinary Shen; this
directory does not replace it.
