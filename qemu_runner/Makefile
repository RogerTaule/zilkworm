BUILD_DIR :=  $(CURDIR)/build
ELF := $(BUILD_DIR)/z6m_debug

CONAN_PROFILE  = $(CURDIR)/conan/profiles/riscv32im.conan.profile
CMAKE_TOOLCHAIN = $(CURDIR)/cmake/riscv32im.cmake

.PHONY: xpack-elf
xpack-elf: xpack-zilkworm
	@[ -d $(BUILD_DIR) ] || mkdir $(BUILD_DIR)
	cmake -B$(BUILD_DIR) -S. -DCMAKE_BUILD_TYPE=Debug \
		-DCMAKE_TOOLCHAIN_FILE=$(CMAKE_TOOLCHAIN) \
		-DCMAKE_BUILD_TYPE=Debug \
		-DCONAN_PROFILE_HOST=$(CONAN_PROFILE) \
		-DCONAN_OUTPUT_FOLDER=$(BUILD_DIR)/conan \
		-DCMAKE_MESSAGE_LOG_LEVEL=VERBOSE \
		-DCMAKE_VERBOSE_MAKEFILE=ON \
		-G "Unix Makefiles" \
		-DCMAKE_EXE_LINKER_FLAGS="-T$(CURDIR)/qemu-xpack.ld -z norelro" \
		-Wno-dev
	cmake --build $(BUILD_DIR) -j --verbose

xpack-zilkworm:
	@[ -d $(BUILD_DIR) ] || mkdir $(BUILD_DIR)
	@[ -d $(BUILD_DIR)/zilkworm ] || mkdir $(BUILD_DIR)/zilkworm
	cmake -B$(BUILD_DIR)/zilkworm -S.. -DCMAKE_BUILD_TYPE=Debug \
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
	riscv-none-elf-gdb -q -ex "target remote :1234" -x .gdbinit build/z6m_debug

## make rlp-qemu file-name=../prover/temp/blocks/2347866/uni...bin
rlp-qemu: xpack-elf
	@if [ -z "$(file-name)" ]; then echo "Usage: make rlp-qemu file-name=path/to.json"; exit 1; fi
	@echo "QEMU waiting for GDB on :1234..."
	@N=$$(wc -c <"$(file-name)"); \
	{ printf "123456789_123456789_123456789_123"; printf "%u\n" $$N; cat "$(file-name)"; } | \
	qemu-system-riscv32 -M virt -m 2G -nographic \
		-bios $(ELF) -S -gdb tcp::1234 \
		-chardev stdio,mux=on,id=stdio0 \
		-serial chardev:stdio0 \
		-semihosting-config enable=on,chardev=stdio0 \
		-mon chardev=stdio0,mode=readline


xpack-zilkworm-eest:
	@[ -d $(BUILD_DIR) ] || mkdir $(BUILD_DIR)
	@[ -d $(BUILD_DIR)/zilkworm ] || mkdir $(BUILD_DIR)/zilkworm
	cmake -B$(BUILD_DIR)/zilkworm -S..	\
		-DCMAKE_TOOLCHAIN_FILE=$(CMAKE_TOOLCHAIN) \
		-DCMAKE_BUILD_TYPE=Debug \
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

.PHONY: xpack-elf-eest
xpack-elf-eest: xpack-zilkworm-eest
	cmake -B$(BUILD_DIR) -S. \
		-DCMAKE_TOOLCHAIN_FILE=$(CMAKE_TOOLCHAIN) \
		-DCMAKE_BUILD_TYPE=Debug \
		-DCONAN_PROFILE_HOST=$(CONAN_PROFILE) \
		-DCONAN_OUTPUT_FOLDER=$(BUILD_DIR)/conan \
		-DCMAKE_MESSAGE_LOG_LEVEL=VERBOSE \
		-DCMAKE_VERBOSE_MAKEFILE=ON \
		-G "Unix Makefiles" \
		-DCMAKE_EXE_LINKER_FLAGS="-T$(CURDIR)/qemu-xpack.ld -z norelro" \
		-DBUILD_TESTING=ON \
		-DTESTS_DIR=$(CURDIR)/../third_party/eest-fixtures/blockchain_tests \
		-Wno-dev
	cmake --build $(BUILD_DIR) -j --verbose


.PHONY: qemu-eest
qemu-eest: xpack-elf-eest
	@if [ -z "$(file-name)" ]; then echo "Usage: make qemu-eest file-name=path/to.json"; exit 1; fi
	@N=$$(wc -c <"$(file-name)"); \
	{ printf "123456789_123456789_123456789_123"; printf "1 %u\n" $$N; cat "$(file-name)"; } | \
	qemu-system-riscv32 -M virt -m 2G -nographic \
		-bios $(BUILD_DIR)/z6m_debug \
		-chardev stdio,mux=on,id=stdio0 \
		-serial chardev:stdio0 \
		-semihosting-config enable=on,chardev=stdio0 \
		-mon chardev=stdio0,mode=readline

rv32im_eest_blockchain_tests: xpack-elf-eest
	ctest --test-dir build --parallel --output-on-failure

rerun_ctest:
	ctest --test-dir build --parallel --output-on-failure -V --timeout 7200

# rerun-qemu-eest:
# 	@if [ -z "$(file-name)" ]; then echo "Usage: make qemu-eest file-name=path/to.json"; exit 1; fi
# 	@N=$$(wc -c <"$(file-name)"); \
# 	{ printf "123456789_123456789_123456789_123"; printf "1 %u\n" $$N; cat "$(file-name)"; } | \
# 	qemu-system-riscv32 -M virt -m 2G -nographic \
# 		-bios $(BUILD_DIR)/z6m_debug \
# 		-chardev stdio,mux=on,id=stdio0 \
# 		-serial chardev:stdio0 \
# 		-semihosting-config enable=on,target=native,chardev=stdio0 \
# 		-monitor none \
#   		-qmp unix:/tmp/qmp.sock,server=on,wait=off

# rerun-qemu-eest:
# 	which script;
# 	@if [ -z "$(file-name)" ]; then echo "Usage: make rerun-qemu-eest file-name=path/to.json"; exit 1; fi
# 	@N=$$(wc -c <"$(file-name)"); \
# 	rm -f semihost.log; \
# 	script -qefc "{ printf '123456789_123456789_123456789_123'; printf '1 %u\n' $$N; cat '$(file-name)'; } | \
# 		qemu-system-riscv32 -M virt -m 2G -nographic \
# 			-bios $(BUILD_DIR)/z6m_debug \
# 			-chardev stdio,mux=on,id=stdio0,signal=off \
# 			-serial chardev:stdio0 \
# 			-semihosting-config enable=on,chardev=stdio0,target=native \
# 			-monitor none" semihost.log

# rerun-qemu-eest:
# 	@if [ -z "$(file-name)" ]; then echo "Usage: make rerun-qemu-eest file-name=path/to.json"; exit 1; fi
# 	@N=$$(wc -c <"$(file-name)"); \
# 	rm -f semihost.log serial.log; \
# 	{ printf "123456789_123456789_123456789_123"; printf "1 %u\n" $$N; cat "$(file-name)"; } | \
# 	qemu-system-riscv32 -M virt -m 2G -display none \
# 		-bios $(BUILD_DIR)/z6m_debug \
# 		-chardev stdio,id=sh0,signal=off \
# 		-semihosting-config enable=on,target=native,chardev=sh0 \
# 		-serial none \
# 		-monitor none 


rerun-qemu-eest:
	@if [ -z "$(file-name)" ]; then echo "Usage: make rerun-qemu-eest file-name=path/to.json"; exit 1; fi
	@N=$$(wc -c <"$(file-name)"); \
	rm -f semihost.log serial.log; \
	{ printf "1 %u\n" $$N; cat "$(file-name)"; } > stdin_payload.bin; \
	qemu-system-riscv32 -M virt -m 2G -display none \
		-bios $(BUILD_DIR)/z6m_debug \
		-chardev stdio,id=sh0,signal=off \
		-semihosting-config enable=on,target=native,chardev=sh0 \
		-serial none \
		-monitor none

# # Clean build artifacts
.PHONY: clean
clean:
	rm -rf $(BUILD_DIR)