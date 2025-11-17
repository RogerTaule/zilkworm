TESTS_DIR := ../fixtures/fixtures_develop/fixtures/blockchain_tests/prague

SHELL = /bin/bash
.SHELLFLAGS = -o pipefail -c
.PHONY: z6m_guest z6m_prover selftest tests

z6m_guest:
	rm -rf target/elf-compilation/riscv32im-succinct-zkvm-elf/release/build/z6m_guest-* || true
	(cd guest_program && cargo prove build)

z6m_prover: z6m_guest
	cargo build --release --manifest-path prover/Cargo.toml

selftest: z6m_prover
	target/release/z6m_prover execute --file-name $(TESTS_DIR)/GeneralStateTests/stExample/add11_yml.json --is-test

execute_block: z6m_prover
	target/release/z6m_prover execute --file-name prover/temp/23442030/unifiedBlockAndStateRlp23442030.json

TESTFILES := $(shell find $(TESTS_DIR) -type f -name '*.json')
RELTESTS := $(patsubst $(TESTS_DIR)/%,%,$(TESTFILES))
LOGFILES := $(addprefix target/logs/,$(RELTESTS:.json=.log))

tests: $(LOGFILES)

.DELETE_ON_ERROR:

target/logs/%.log: $(TESTS_DIR)/%.json
	@mkdir -p $(dir $@)
	target/release/z6m_prover execute --is-test --file-name $< 2>&1 | tee $@ || (echo "CRASHED! $@" && rm $@)
