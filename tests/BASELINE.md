# Baseline

The compatibility gate's recorded results and the observed behaviour of the
pinned shen-erl. Update this file in the same change as any pin bump.

## Environment

| Item | Value |
| --- | --- |
| shen-erl | `ea5380a433d4d4281d4ea4dd88c0ade290028a6c` (`shen-erl.rev`, `flake.lock`) |
| Kernel | ShenOSKernel 42.2, archive SHA-256 `1d02273003654d34ec020ae67cb214ecec410dee3350419ff807d82b652678d8` |
| Erlang/OTP | OTP 28, erts 16.4.0.5 (pinned nixpkgs `ac6b216`) |
| Toolchain | `nix develop` from this repository's flake, Nix 2.34.6 |

CI prints the OTP version it ran on in the "Toolchain" step.

## Gate results

Recorded 17 October 2026 from a clean `make` in a cloud container.

| Check | Result |
| --- | --- |
| `make baseline`: kernel suite (`runme.shen`) | passed 143, failed 0, 65 s |
| `make baseline`: shen-erl Common Test (codegen, overrides, interop, json) | 46 ok, 0 failed |
| `make ct`: this repository (`ownership_SUITE`) | 13 ok, 0 failed |
| `make corpus`: semantic regression corpus | 10 passed, 0 failed |
| `scripts/check-pins.sh` | pins agree |

The kernel suite's runner exits 0 even when tests fail, so `make baseline`
checks its printed counts (`scripts/check-kernel-suite.sh`, expecting
exactly 143 passed and 0 failed).

The kernel suite took 188 s in the bootstrap session and 65 s here; run time
depends on the machine and is not a regression signal.

## Ownership probes

`tests/ownership_SUITE.erl`. The test case process owns the stores and boots
the kernel; each operation runs in a second process. Outcomes are asserted
as today's behaviour.

| Operation from a second process | Outcome |
| --- | --- |
| Read a global (`value`, primitive or via `eval`) | works |
| Set a global (`set`, primitive or via `eval`) | `badarg`, owner's value unchanged |
| Create a vector (`absvector`) | `badarg` (bumps the shared variable counter) |
| Read an element of the owner's vector | works |
| Write an element of the owner's vector | `badarg`, element unchanged |
| `eval-kl` of a non-defun expression | **works** |
| `eval-kl` of a defun | `badarg` (registers its MFA first) |
| `define` through `eval` | `badarg` |
| Call an already-defined function | works |
| Bump the variable counter | `badarg` |
| Owner process exits | all stores are gone |

Finding against plan section 1: not every compile fails. A non-defun
`eval-kl` compiles and loads a fresh random module without writing to any
store, so any process can evaluate expressions; only forms that register a
definition or allocate need the owner. This narrows U2 (the environment owner
must serialize definitions and allocation, not every evaluation) and makes U4
(unpurged anonymous modules) reachable from every process, not just the
owner.

## Resource probes

`tests/probes/resource_probes.erl`, run with `make resource-probes N=...`.
One process owns the stores and boots the kernel, then performs each
operation N times; the row is the growth across the N operations, measured
after a garbage collection. Launcher flags (`+P 524288 +t 4194304`).
Recorded 17 October 2026, same environment as above, N = 1000 (N = 100
gives the same per-operation figures).

| Probe | Modules | Atoms | ETS tables | Memory (KB) | Code (KB) | µs/op |
| --- | --- | --- | --- | --- | --- | --- |
| `eval-kl` of an expression | 1000 | 1313 | 0 | 3118 | 2173 | 1374 |
| Shen `eval` of an expression | 1000 | 1000 | 0 | 2678 | 2080 | 1641 |
| Redefine one function | 2 | 5799 | 4000 | 11651 | 6 | 3032 |
| Define distinct functions | 2000 | 10800 | 4000 | 19648 | 5105 | 4223 |
| `absvector` | 0 | 1000 | 1000 | 2537 | 0 | 3 |
| `shen.dict` (through `eval`) | 1000 | 2000 | 1000 | 5560 | 2025 | 2284 |

Per operation, and never reclaimed while the owner lives:

- Every evaluation of a non-defun form loads one new module (about 2 KB of
  code) and creates at least one atom (its random name). Nothing purges
  them. A service that evaluates per request grows without bound (U4).
- Every vector and dictionary creates one atom and one named ETS table.
  The table is not freed when the value becomes garbage, and the atom never
  is. At the launcher's atom limit of 4,194,304, roughly four million
  allocations end the node (U1).
- A function definition creates four ETS tables and about six atoms, even
  when it replaces an existing definition (code is replaced, so code memory
  stays flat). Repeated redefinition still leaks tables and atoms.

These are the numbers U1 and U4 are reviewed against: after either lands,
re-run the probes on the bumped pin and replace the affected rows.
