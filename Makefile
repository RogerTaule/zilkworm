TESTS_DIR := ../fixtures/fixtures_develop/fixtures/blockchain_tests/prague

SHELL = /bin/bash
.SHELLFLAGS = -o pipefail -c
.PHONY: z6m_guest z6m_prover selftest tests

z6m_guest:
# 	rm -r target/elf-compilation/riscv64im-succinct-zkvm-elf/* || true
	rm -r prover/target/elf-compilation/riscv64im-succinct-zkvm-elf/release/build/z6m_guest-* || true
	(cd prover/guest_hypercube && cargo prove build)
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
	prover/target/release/z6m_prover execute --file-name $(TESTS_DIR)/GeneralStateTests/stExample/add11_yml.json --is-test

execute_block: z6m_prover
	prover/target/release/z6m_prover execute --file-name prover/temp/23442030/unifiedBlockAndStateRlp23442030.json

TESTFILES := $(shell find $(TESTS_DIR)/${TESTS_SUBDIR} -type f -name '*.json')
RELTESTS := $(patsubst $(TESTS_DIR)/%,%,$(TESTFILES))
LOGFILES := $(addprefix target/logs/,$(RELTESTS:.json=.log))

tests: $(LOGFILES)

.DELETE_ON_ERROR:

target/logs/%.log: $(TESTS_DIR)/%.json
	@mkdir -p $(dir $@)
	prover/target/release/z6m_prover execute --is-test --file-name $< 2>&1 | tee $@ || (echo "CRASHED! $@" && rm $@)

eest_blockchain_tests: 
	cmake -B build/eest -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON -DTESTS_DIR=third_party/eest-fixtures/blockchain_tests
	cmake --build build/eest
	ctest --test-dir build/eest --parallel

rv32im_eest_blockchain_tests: 
	cd debug_build
	cmake -B build/eest -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON -DTESTS_DIR=third_party/eest-fixtures/blockchain_tests
	cmake --build build/eest
	ctest --test-dir build/eest --parallel
