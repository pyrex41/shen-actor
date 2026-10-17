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
.PHONY: baseline
baseline: shen-erl
	$(MAKE) -C $(SHEN_ERL_DIR) shen-tests
	$(MAKE) -C $(SHEN_ERL_DIR) ct

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
