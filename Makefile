# Copyright 2026 The Zilkworm Authors
# SPDX-License-Identifier: Apache-2.0

TESTS_DIR := third_party/eest-fixtures/blockchain_tests/prague

SHELL = /bin/bash
.SHELLFLAGS = -o pipefail -c
.PHONY: z6m_guest z6m_prover selftest tests z6m_guest_zisk z6m_prover_zisk selftest_zisk eest-zisk-blockchain-tests

clean: 
	rm -rf prover/guest_hypercube/build/
	rm -rf prover/target
	
z6m_guest:
	cmake -S prover/guest_hypercube -B prover/guest_hypercube/build \
		-DCMAKE_TOOLCHAIN_FILE=$(CURDIR)/prover/guest_hypercube/cmake/riscv64im-sp1.cmake \
		-DCMAKE_BUILD_TYPE=Release \
		-DSP1=ON
	cmake --build prover/guest_hypercube/build -j$$(nproc)
z6m_prover: z6m_guest
	cargo build --release --manifest-path prover/prover_hypercube/Cargo.toml

test_hc: z6m_prover
	prover/target/release/z6m_prover execute --block-number 23540896 --data-dir prover/prover_turbo/temp

z6m_guest_turbo:
	rm -r prover/target/elf-compilation/riscv32im-succinct-zkvm-elf/release/build/z6m_guest-* || true
	(cd prover/guest_turbo && cargo prove build)

z6m_prover_turbo: z6m_guest_turbo
	cargo build --release --manifest-path prover/prover_turbo/Cargo.toml

selftest: z6m_prover
	prover/target/release/z6m_prover execute --is-test --file-name third_party/eest-fixtures/blockchain_tests/static/state_tests/stExample/add11.json

execute-block: z6m_prover
	prover/target/release/z6m_prover execute --file-name prover/temp/blocks/23519000/unifiedBlockAndStateRlp23519000.bin

TESTFILES := $(shell find $(TESTS_DIR)/${TESTS_SUBDIR} -type f -name '*.json')
RELTESTS := $(patsubst $(TESTS_DIR)/%,%,$(TESTFILES))
LOGFILES := $(addprefix target/logs/,$(RELTESTS:.json=.log))

tests: $(LOGFILES)

.DELETE_ON_ERROR:

target/logs/%.log: $(TESTS_DIR)/%.json
	@mkdir -p $(dir $@)
	prover/target/release/z6m_prover execute --is-test --file-name $< 2>&1 | tee $@ || (echo "CRASHED! $@" && rm $@)

eest-blockchain-tests: 
	cmake -B build/eest -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON -DTESTS_DIR=third_party/eest-fixtures/blockchain_tests
	cmake --build build/eest
	ctest --test-dir build/eest --parallel

rv32im-eest-blockchain-tests:
	cd qemu_runner && make rv32im-eest-blockchain-tests

# ─── Zisk backend (rv64ima, milestone 1: execute-only) ───────────────────────

# Cross-build the C++ guest ELF for the Zisk zkVM. Requires the xpack
# riscv-none-elf-gcc toolchain at $$ZISK_TOOLCHAIN_PREFIX (path to the
# bin/ directory containing riscv-none-elf-gcc / g++).
z6m_guest_zisk:
	cmake -S prover/guest_zisk -B prover/guest_zisk/build \
		-DCMAKE_TOOLCHAIN_FILE=$(CURDIR)/cmake/zisk-toolchain.cmake \
		-DCMAKE_BUILD_TYPE=Release \
		-G Ninja
	cmake --build prover/guest_zisk/build --target z6m_guest.elf

# Build the Zisk host prover binary. Depends on z6m_guest_zisk because
# prover_zisk's build.rs embeds the guest ELF at compile time.
z6m_prover_zisk: z6m_guest_zisk
	cd prover/prover_zisk && cargo build --release

# One-shot sanity that the Zisk backend can execute an EEST JSON test
# end-to-end (mirrors the SP1 `selftest` target).
selftest_zisk: z6m_prover_zisk
	prover/prover_zisk/target/release/z6m_prover execute --is-test \
		--file-name third_party/eest-fixtures/blockchain_tests/static/state_tests/stExample/add11.json

# Run the full EEST blockchain_tests suite through the Zisk guest. Uses
# ziskemu directly (not ProverClient::execute) so each test only pays
# emulation cost, no per-test setup. Override defaults on the command line:
#   make eest-zisk-blockchain-tests TESTS=third_party/eest-fixtures/blockchain_tests/prague JOBS=8 TIMEOUT=120
EEST_TESTS_DIR ?= third_party/eest-fixtures/blockchain_tests
EEST_JOBS      ?= 4
EEST_TIMEOUT   ?= 60
eest-zisk-blockchain-tests: z6m_guest_zisk
	python3 prover/scripts/run_eest_zisk.py \
		--elf prover/guest_zisk/build/z6m_guest.elf \
		--tests-dir $(EEST_TESTS_DIR) \
		--jobs $(EEST_JOBS) \
		--timeout $(EEST_TIMEOUT) \
		--summary-only
