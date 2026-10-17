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
| `scripts/check-pins.sh` | pins agree |

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
