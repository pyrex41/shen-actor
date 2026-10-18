# backends/

Lowering checked actor IR into executable OTP modules, and the backend
investigation (PRD section 17).

Decision: [ADR 0003](../docs/decisions/0003-backend.md) keeps the
existing shen-erl Erlang-forms emitter, used as-is through the pinned
dependency. The rest of this directory is the evidence for it:

- `lfe/`: the KLambda-to-LFE spike. `shen_kl_lfe.erl` is the emitter,
  `shim/` gives it shen-erl's `shen_erl_kl_codegen` API, `build.sh` builds
  a candidate copy of the pinned tree (`deps/shen-erl-lfe`) with the kernel
  recompiled through it, `measure.sh` produces the ADR's measurements.
- `skeleton/`: a hand-written reservation IR lowered through either
  emitter to a running gen_server (`tests/spike/skeleton_SUITE.erl`).

`make spike` builds the candidate, runs the corpus on it and the skeleton
on both emitters; `make spike-kernel` runs the full kernel suite on it.

Decision rule: choose LFE if it preserves compatibility and materially
simplifies the compiler and actor generation without an unacceptable measured
regression; otherwise keep Erlang forms. Recorded in a backend ADR with the
full kernel results and the semantic regression corpus for both candidates.
Two production emitters stay only if a demonstrated benefit pays their cost.
