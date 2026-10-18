# ADR 0003: Backend: keep the Erlang forms emitter

Status: proposed · 18 October 2026

## Context

PRD section 17 requires the existing Erlang forms backend and a
KLambda-to-LFE backend to be evaluated as real alternatives. The rule:
choose LFE if it preserves compatibility and materially simplifies the
compiler and actor generation without an unacceptable measured regression;
otherwise keep Erlang forms. Plan M1 fixes the evidence: both candidates'
full kernel results, the M0 corpus side by side, dynamic evaluation and
redefinition, one protocol actor through both, and measurements of compile
latency, execution overhead, module and atom growth, source locations and
implementation size.

## The LFE candidate

`backends/lfe/shen_kl_lfe.erl` emits LFE forms from the KL AST that
`shen_erl_kl_parse` produces, mirroring `shen_erl_kl_codegen` clause for
clause: static binding through the function store, runtime dispatch through
`shen_erl_kl_compiler:invoke/2`, the dynamic eta rule for redefinition,
`assert-boolean` forcing, `trap-error` as `try` with `{Class, Reason}`
handed to the handler, `%%let-label`/`%%goto-label` as bound lambdas.
`backends/lfe/shim/shen_erl_kl_codegen.erl` gives it the original module's
exact API and is installed only into a copy of the pinned tree
(`backends/lfe/build.sh`, `deps/shen-erl-lfe`). Primitives, overrides,
stores, the launcher and the kernel `.kl` files are the pinned shen-erl,
unmodified, so differences are the emitter's.

Two things the emitter had to do that the Erlang path does not:

- Ten kernel function names are LFE core forms or core functions
  (`function`, `call`, `receive`, `when`, `==`, `get`, `put`, `length`,
  `map`, `not`), which LFE refuses to define. Every defun is emitted under a
  prefixed name, compiled only to Core Erlang, renamed back there, and
  finished with `compile:forms(from_core)`. LFE's own extra exports
  (`__info__/1`, `LFE-EXPAND-EXPORTED-MACRO/3`) are dropped, because the
  boot registers every exported function as a Shen function.
- Variable names come from a counter local to each compile instead of the
  shared counter in ETS. This was a simplification, not a requirement; it
  is why the LFE column below creates fewer atoms per definition, and it is
  available to the Erlang path too (see Consequences).

## Results

Same container, same pinned toolchain: OTP 28 (erts 16.4.0.5), LFE 2.2.2,
both from nixpkgs `ac6b216` through the flake. Single runs; timings are
indicative.

**Compatibility**

| Check | Erlang forms | LFE |
| --- | --- | --- |
| Kernel suite (ShenOSKernel 42.2, 143 tests) | 143 passed, 0 failed | 143 passed, 0 failed |
| Semantic corpus (10 cases, `make corpus`) | 10 passed | 10 passed |
| Actor skeleton (`tests/spike/skeleton_SUITE`) | expected trace | expected trace, identical to Erlang forms |

The corpus covers currying, computed calls, closures, freeze/thaw, error
propagation, equality, mutable values, redefinition with arity change in
both directions, and nested load. No divergence was found, so the corpus
was not changed.

**Measurements** (`backends/lfe/measure.sh`, N = 1000)

| Measure | Erlang forms | LFE |
| --- | --- | --- |
| Kernel compile, 22 files (ms) | 5777 | 6166 |
| Kernel suite run time (s) | 65 | 61 |
| Corpus run, 10 cases (ms) | 14311 | 14623 |
| Kernel BEAM size (KB) | 500 | 516 |
| Emitter source lines | 466 (`codegen` + `env`) | 348 (emitter + shim) |
| Stack trace location | none | form index in the generated module, no file |

```text
backend,probe,n,modules,atoms,ets_tables,memory_total_kb,memory_code_kb,us_per_op
erlang,eval_kl_expression,1000,1000,1313,0,3118,2173,1510.5
erlang,shen_eval_expression,1000,1000,1000,0,2456,2080,1620.4
erlang,redefine_same_function,1000,2,5799,4000,12474,6,3069.0
erlang,define_distinct_functions,1000,2000,10800,4000,23322,5105,4058.3
erlang,absvector,1000,0,1000,1000,2251,0,3.1
erlang,shen_dict,1000,1000,2000,1000,5922,2025,2178.2
lfe,eval_kl_expression,1000,1000,1313,0,3155,2205,1826.1
lfe,shen_eval_expression,1000,1000,1000,0,2730,2112,2060.8
lfe,redefine_same_function,1000,2,5005,4000,11653,6,3546.0
lfe,define_distinct_functions,1000,2000,10000,4000,19543,5144,5256.3
lfe,absvector,1000,0,1000,1000,2588,0,3.0
lfe,shen_dict,1000,1000,2000,1000,5614,2080,2755.9
```

Module lifecycle and code-version retention are the same on both: one
unpurged module per evaluation, and redefinition reloads one module per
name. Runtime evaluation is 20 to 30 percent slower through LFE
(`lfe_comp` runs its own passes in a separate process before the Erlang
compiler). Execution of compiled code is indistinguishable at this
resolution: the kernel suite and corpus times differ by less than run-to-run
noise.

Neither backend carries KL or Shen source positions:
`shen_erl_kl_parse` drops them before either emitter sees the AST.
Native pattern matching was not a differentiator: the kernel compiles
Shen pattern matching to KL conditionals before either emitter runs.

## Decision

**Keep the Erlang forms emitter as the only production backend.** LFE
preserves compatibility, which is the first condition, but it does not
materially simplify the compiler or actor generation:

- The emitter is shorter mainly because s-expressions are terser than
  `erl_syntax` calls. Against that it needs the Core Erlang rename for core
  form collisions, and it adds LFE as a toolchain and runtime dependency.
- Actor generation is not simplified. The skeleton shows the actor
  machinery (gen_server, session ledger, validation) is the OTP adapter and
  is the same for either emitter; handler bodies are KL in both.
- It costs 20 to 30 percent on every runtime evaluation, and a little on
  kernel compile, with no offsetting gain.

Two production emitters are not justified: no maintenance or verification
benefit was demonstrated. Because LFE did not win, the upstreaming question
in ADR 0001 does not arise.

## Consequences

- M4's generator (ADR 0004) targets Erlang forms through the pinned
  shen-erl, behind the compiler interface of upstream item U3.
- The spike stays in `backends/lfe` and `backends/skeleton` as the evidence
  for this ADR, built and run by `make spike` and `make spike-kernel`. It is
  not a production path; it may be removed once nothing references it.
- Candidate upstream change found by the spike: take variable names in
  `shen_erl_kl_env` from a per-compile counter instead of the shared ETS
  counter. Compiling would then write no store, which narrows U2 further.
  Per 1000 redefinitions it saves about 800 of the 5799 atoms measured
  here; nearly all of the rest are the four `DICT<n>` table names each
  definition allocates, which U1 removes (1005 atoms with U1 alone).
- Source positions need a parser change in shen-erl before any backend
  can report them; that is a prerequisite for the PRD section 20
  diagnostics on generated code, not a backend choice.
