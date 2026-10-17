# backends/

Lowering checked actor IR into executable OTP modules, and the backend
investigation (PRD section 17).

- `erlang/`: the existing shen-erl Erlang-forms path, used as-is through the
  pinned dependency; the actor generator targets it first.
- `lfe/`: the KLambda-to-LFE spike. Reuses shen-erl's runtime primitives,
  must compile the unmodified pinned kernel, support dynamic evaluation and
  redefinition, and emit one protocol actor. LFE and OTP versions are pinned
  in the flake.

Decision rule: choose LFE if it preserves compatibility and materially
simplifies the compiler and actor generation without an unacceptable measured
regression; otherwise keep Erlang forms. Recorded in a backend ADR with the
full kernel results and the semantic regression corpus for both candidates.
Two production emitters stay only if a demonstrated benefit pays their cost.
