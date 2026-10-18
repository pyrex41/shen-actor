# Shen Protocol Actors
#
# shen-erl is a pinned dependency (shen-erl.rev), fetched into deps/ and built
# with its own Makefile.  Nothing here edits that tree.  `make baseline` is the
# compatibility gate from the PRD: the unmodified pinned kernel must boot and
# the complete kernel suite and shen-erl's Common Test suites must pass before
# and after every change in this repository.

BASE_DIR := $(shell pwd)
SHEN_ERL_REV := $(shell cat shen-erl.rev)
SHEN_ERL_DIR := deps/shen-erl
SHEN_ERL_BIN := $(SHEN_ERL_DIR)/bin/shen-erl

EBINDIR := ebin
SRC_ERL := $(wildcard runtime/*.erl backends/*.erl simulator/*.erl)
EBINS := $(patsubst %.erl,$(EBINDIR)/%.beam,$(notdir $(SRC_ERL)))
ERLC ?= erlc
ERLCFLAGS ?= -W1 +debug_info

.PHONY: all
all: shen-erl erlc-compile

## Dependency ------------------------------------------------------------

$(SHEN_ERL_DIR)/Makefile: shen-erl.rev scripts/fetch-shen-erl.sh
	SHEN_ERL_REV='$(SHEN_ERL_REV)' DESTDIR='$(SHEN_ERL_DIR)' sh scripts/fetch-shen-erl.sh
	@touch $@

.PHONY: fetch-shen-erl
fetch-shen-erl: $(SHEN_ERL_DIR)/Makefile

.PHONY: shen-erl
shen-erl: $(SHEN_ERL_DIR)/Makefile
	$(MAKE) -C $(SHEN_ERL_DIR)

## The compatibility gate (PRD section 5 and success criterion 7).
## The kernel suite exits 0 even when tests fail; its printed counts are
## checked instead.  KERNEL_TESTS changes only with a kernel bump.
KERNEL_TESTS := 143
KERNEL_LOG := tests/logs/kernel-suite.log

.PHONY: baseline
baseline: shen-erl
	@mkdir -p tests/logs
	$(MAKE) -C $(SHEN_ERL_DIR) shen-tests 2>&1 | tee $(KERNEL_LOG)
	sh scripts/check-kernel-suite.sh $(KERNEL_LOG) $(KERNEL_TESTS)
	$(MAKE) -C $(SHEN_ERL_DIR) ct

## Semantic regression corpus (plan M0 step 4).  SHEN=... selects a backend.
.PHONY: corpus
corpus: shen-erl
	sh scripts/run-corpus.sh

## Resource probes (plan M0 step 5): growth after N evaluations and
## allocations.  Prints CSV for tests/BASELINE.md.  Flags match shen-erl's
## launcher so the atom and process limits are the ones programs run with.
N ?= 1000
PROBE_DIR := tests/logs/probes

.PHONY: resource-probes
resource-probes: shen-erl
	@mkdir -p $(PROBE_DIR)
	$(ERLC) -o $(PROBE_DIR) tests/probes/resource_probes.erl
	erl -noshell +P 524288 +t 4194304 -pa $(abspath $(SHEN_ERL_DIR)/ebin) -pa $(abspath $(PROBE_DIR)) \
	  -s resource_probes main $(N)

## The ADR 0002 examples, read as the frontend reads them.
.PHONY: examples
examples: shen-erl
	CORPUS=$(BASE_DIR)/tests/grammar sh scripts/run-corpus.sh

## M1 backend spike: build the LFE candidate (a copy of the pinned tree,
## kernel recompiled through backends/lfe), then run the corpus on it and
## the actor skeleton on both candidates.  `make spike-kernel` adds the full
## kernel suite on the candidate.  Needs LFE (the Nix shell provides it).
LFE_TREE := deps/shen-erl-lfe
SPIKE_EBIN := tests/logs/spike-ebin

.PHONY: spike-build
spike-build: shen-erl
	DEST=$(BASE_DIR)/$(LFE_TREE) sh backends/lfe/build.sh

.PHONY: spike
spike: spike-build
	SHEN=$(BASE_DIR)/$(LFE_TREE)/bin/shen-erl sh scripts/run-corpus.sh
	@mkdir -p $(SPIKE_EBIN) tests/logs/spike
	$(ERLC) -o $(SPIKE_EBIN) backends/skeleton/actor_skeleton.erl
	@# The candidate tree's shen_erl_kl_codegen is the LFE shim; the original
	@# is compiled unmodified under another module name to compare against.
	sed 's/^-module(shen_erl_kl_codegen)\./-module(shen_kl_erlforms)./' \
	  $(SHEN_ERL_DIR)/src/shen_erl_kl_codegen.erl > $(SPIKE_EBIN)/shen_kl_erlforms.erl
	$(ERLC) -o $(SPIKE_EBIN) $(SPIKE_EBIN)/shen_kl_erlforms.erl
	erl -noshell -pa $(abspath $(LFE_TREE)/ebin) -pa $(abspath $(SPIKE_EBIN)) -eval \
	  'Result = ct:run_test([{dir,"$(abspath tests/spike)"},{logdir,"$(abspath tests/logs/spike)"}]), io:format("CT_RESULT=~p~n", [Result]), case Result of {_Ok,0,_Skipped} -> halt(0); _ -> halt(1) end.'

.PHONY: spike-kernel
spike-kernel: spike-build
	@mkdir -p tests/logs
	cd $(LFE_TREE) && SHEN_ERL_ROOTDIR=$(BASE_DIR)/$(LFE_TREE) bin/shen-erl --script scripts/run-shen-tests.shen 2>&1 | tee $(BASE_DIR)/tests/logs/lfe-kernel-suite.log
	sh scripts/check-kernel-suite.sh tests/logs/lfe-kernel-suite.log $(KERNEL_TESTS)

.PHONY: check-pins
check-pins:
	sh scripts/check-pins.sh

## This repository -------------------------------------------------------

vpath %.erl runtime backends simulator

$(EBINDIR)/%.beam: %.erl
	@mkdir -p $(EBINDIR)
	$(ERLC) -o $(EBINDIR) $(ERLCFLAGS) $<

.PHONY: erlc-compile
erlc-compile: $(EBINS)

## Run a Shen script with this repository's BEAM modules on the code path.
## shen-erl's launcher only adds its own ebin; ERL_FLAGS is read by erl itself.
##   make run SCRIPT=examples/reservation/run.shen ARGS="check reservation"
.PHONY: run
run: all
	ERL_FLAGS="-pa $(BASE_DIR)/$(EBINDIR)" SHEN_ERL_ROOTDIR=$(BASE_DIR)/$(SHEN_ERL_DIR) \
	  $(SHEN_ERL_BIN) script $(SCRIPT) $(ARGS)

.PHONY: ct
ct: all
	@mkdir -p tests/logs
	erl -noshell -pa $(abspath $(EBINDIR)) -pa $(abspath $(SHEN_ERL_DIR)/ebin) -eval \
	  'Result = ct:run_test([{dir,"$(abspath tests)"},{logdir,"$(abspath tests/logs)"}]), io:format("CT_RESULT=~p~n", [Result]), case Result of {_Ok,0,_Skipped} -> halt(0); _ -> halt(1) end.'

.PHONY: clean
clean:
	rm -rf $(EBINDIR) tests/logs erl_crash.dump
	-$(MAKE) -C $(SHEN_ERL_DIR) clean

.PHONY: distclean
distclean: clean
	rm -rf deps
