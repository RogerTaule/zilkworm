# ========== Architecture selection ==========
# Default to riscv32im, can be overridden: make ARCH=rv64
ARCH ?= rv32

ifeq ($(ARCH),rv64)
  BUILD_DIR := $(CURDIR)/build64
  CONAN_PROFILE := $(CURDIR)/conan/profiles/riscv64im.conan.profile
  CMAKE_TOOLCHAIN := $(CURDIR)/cmake/riscv64im.cmake
  LINKER_SCRIPT := $(CURDIR)/qemu-xpack-64.ld
  QEMU_SYSTEM := qemu-system-riscv64
  START_ASM := start64.S
else
  BUILD_DIR := $(CURDIR)/build
  CONAN_PROFILE := $(CURDIR)/conan/profiles/riscv32im.conan.profile
  CMAKE_TOOLCHAIN := $(CURDIR)/cmake/riscv32im.cmake
  LINKER_SCRIPT := $(CURDIR)/qemu-xpack.ld
  QEMU_SYSTEM := qemu-system-riscv32
  START_ASM := start.S
endif

ELF := $(BUILD_DIR)/z6m_debug

.PHONY: xpack-elf xpack-zilkworm xpack-zilkworm-eest gdb rlp-qemu qemu-eest-stdio qemu-eest-fileio rerun-ctest

xpack-elf: xpack-zilkworm
	@mkdir -p $(BUILD_DIR)
	cmake -B$(BUILD_DIR) -S. \
		-DCMAKE_TOOLCHAIN_FILE=$(CMAKE_TOOLCHAIN) \
		-DCMAKE_BUILD_TYPE=Debug \
		-DCONAN_PROFILE_HOST=$(CONAN_PROFILE) \
		-DCONAN_OUTPUT_FOLDER=$(BUILD_DIR)/conan \
		-DCMAKE_MESSAGE_LOG_LEVEL=VERBOSE \
		-DCMAKE_VERBOSE_MAKEFILE=ON \
		-G "Unix Makefiles" \
		-DCMAKE_EXE_LINKER_FLAGS="-T$(LINKER_SCRIPT) -z norelro" \
		-DSTART_ASM=$(START_ASM) \
		-Wno-dev
	cmake --build $(BUILD_DIR) -j --verbose

xpack-zilkworm:
	@mkdir -p $(BUILD_DIR)/zilkworm
	cmake -B$(BUILD_DIR)/zilkworm -S.. \
		-DCMAKE_TOOLCHAIN_FILE=$(CMAKE_TOOLCHAIN) \
		-DCMAKE_BUILD_TYPE=Debug \
		-DCONAN_PROFILE_HOST=$(CONAN_PROFILE) \
		-DCONAN_OUTPUT_FOLDER=$(BUILD_DIR)/conan \
		-DCMAKE_MESSAGE_LOG_LEVEL=VERBOSE \
		-DCMAKE_VERBOSE_MAKEFILE=ON \
		-DCMAKE_INSTALL_PREFIX=$(BUILD_DIR)/zilkworm-install \
	    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
		-DTESTS_DIR=third_party/eest-fixtures/blockchain_tests \
		-G "Unix Makefiles" \
		-DQEMU_DEBUG=ON \
		-Wno-dev
	cmake --build $(BUILD_DIR)/zilkworm -j --target install

gdb:
	riscv-none-elf-gdb -q -ex "target remote :1234" -x .gdbinit $(ELF)

## make rlp-qemu file-name=../prover/temp/blocks/2347866/uni...bin
rlp-qemu: xpack-elf
	@if [ -z "$(file-name)" ]; then echo "Usage: make rlp-qemu file-name=path/to.json (ARCH=$(ARCH))"; exit 1; fi
	@echo "QEMU waiting for GDB on :1234..."
	@N=$$(wc -c <"$(file-name)"); \
	{ printf "123456789_123456789_123456789_123"; printf "%u\n" $$N; cat "$(file-name)"; } | \
	$(QEMU_SYSTEM) -M virt -m 2G -nographic \
		-bios $(ELF) -S -gdb tcp::1234 \
		-chardev stdio,mux=on,id=stdio0 \
		-serial chardev:stdio0 \
		-semihosting-config enable=on,chardev=stdio0 \
		-mon chardev=stdio0,mode=readline


xpack-zilkworm-eest:
	@mkdir -p $(BUILD_DIR)/zilkworm
	cmake -B$(BUILD_DIR)/zilkworm -S.. \
		-DCMAKE_TOOLCHAIN_FILE=$(CMAKE_TOOLCHAIN) \
		-DCMAKE_BUILD_TYPE=Release \
		-DCONAN_PROFILE_HOST=$(CONAN_PROFILE) \
		-DCONAN_OUTPUT_FOLDER=$(BUILD_DIR)/conan \
		-DCMAKE_MESSAGE_LOG_LEVEL=VERBOSE \
		-DCMAKE_VERBOSE_MAKEFILE=ON \
		-DCMAKE_INSTALL_PREFIX=$(BUILD_DIR)/zilkworm-install \
	    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
		-G "Unix Makefiles" \
		-DQEMU_DEBUG=ON \
		-Wno-dev
	cmake --build $(BUILD_DIR)/zilkworm -j --target install

xpack-elf-eest: xpack-zilkworm-eest
	cmake -B$(BUILD_DIR) -S. \
		-DCMAKE_TOOLCHAIN_FILE=$(CMAKE_TOOLCHAIN) \
		-DCMAKE_BUILD_TYPE=Release \
		-DCONAN_PROFILE_HOST=$(CONAN_PROFILE) \
		-DCONAN_OUTPUT_FOLDER=$(BUILD_DIR)/conan \
		-DCMAKE_MESSAGE_LOG_LEVEL=VERBOSE \
		-DCMAKE_VERBOSE_MAKEFILE=ON \
		-G "Unix Makefiles" \
		-DCMAKE_EXE_LINKER_FLAGS="-T$(LINKER_SCRIPT) -z norelro" \
		-DSTART_ASM=$(START_ASM) \
		-DQEMU_SYSTEM=$(QEMU_SYSTEM) \
		-DBUILD_TESTING=ON \
		-DTESTS_DIR=$(CURDIR)/../third_party/eest-fixtures/blockchain_tests \
		-Wno-dev
	cmake --build $(BUILD_DIR) -j --verbose


qemu-eest-stdio: xpack-elf-eest
	@if [ -z "$(file-name)" ]; then echo "Usage: make qemu-eest-stdio file-name=path/to.json (ARCH=$(ARCH))"; exit 1; fi
	@N=$$(wc -c <"$(file-name)"); \
	{ printf "123456789_123456789_123456789_123"; printf "1 %u\n" $$N; cat "$(file-name)"; } | \
	$(QEMU_SYSTEM) -M virt -m 2G -nographic \
		-bios $(ELF) \
		-chardev stdio,mux=on,id=stdio0 \
		-serial chardev:stdio0 \
		-semihosting-config enable=on,chardev=stdio0 \
		-mon chardev=stdio0,mode=readline

eest-blockchain-tests: xpack-elf-eest
	ctest --test-dir $(BUILD_DIR) --parallel --output-on-failure

rerun-ctest: xpack-elf-eest
	ctest --test-dir $(BUILD_DIR) --parallel --output-on-failure -V --timeout 7200

qemu-eest-fileio: xpack-elf-eest
	@if [ -z "$(file-name)" ]; then echo "Usage: make qemu-eest-fileio file-name=path/to.json (ARCH=$(ARCH))"; exit 1; fi
	@mkdir -p $(CURDIR)/temp
	@N=$$(wc -c <"$(file-name)"); \
	rm -f $(CURDIR)/temp/semihost.log $(CURDIR)/temp/serial.log; \
	{ printf "1 %u\n" $$N; cat "$(file-name)"; } > $(CURDIR)/temp/stdin_payload.bin; \
	$(QEMU_SYSTEM) -M virt -m 2G -display none \
		-bios $(ELF) \
		-monitor none \
		-serial none \
		-chardev file,id=shlog,path=$(CURDIR)/temp/semihost.log \
		-semihosting-config enable=on,target=native,chardev=shlog


# ========== Convenience targets for specific architectures ==========
.PHONY: xpack-elf-eest-rv32 xpack-elf-eest-rv64 eest-rv32 eest-rv64

# RV32 specific targets
xpack-elf-eest-rv32:
	$(MAKE) ARCH=rv32 xpack-elf-eest

eest-rv32:
	$(MAKE) ARCH=rv32 eest-blockchain-tests

# RV64 specific targets  
xpack-elf-eest-rv64:
	$(MAKE) ARCH=rv64 xpack-elf-eest

eest-rv64:
	$(MAKE) ARCH=rv64 eest-blockchain-tests

# Clean build artifacts
.PHONY: clean clean-all clean-temp
clean:
	rm -rf $(BUILD_DIR)

clean-all:
	rm -rf $(CURDIR)/build $(CURDIR)/build64

clean-temp:
	rm -f $(CURDIR)/temp/stdin_payload.bin $(CURDIR)/temp/semihost.log $(CURDIR)/temp/serial.log
