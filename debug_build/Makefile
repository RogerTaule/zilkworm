BUILD_DIR :=  $(CURDIR)/build
CONAN_PROFILE  := conan/profiles/rv32im.sp1.profile
CMAKE_TOOLCHAIN := cmake/rv32im.sp1.cmake
ELF := $(BUILD_DIR)/z6m_debug

.PHONY: elf
elf: 
	@[ -d $(BUILD_DIR) ] || mkdir $(BUILD_DIR)
	cmake -B$(BUILD_DIR) -S. -DCMAKE_BUILD_TYPE=Debug \
		-DCMAKE_TOOLCHAIN_FILE=$(CMAKE_TOOLCHAIN) \
		-DCMAKE_BUILD_TYPE=Debug \
		-DCONAN_PROFILE_HOST=$(CONAN_PROFILE) \
		-DCONAN_OUTPUT_FOLDER=$(BUILD_DIR)/conan \
		-DCMAKE_MESSAGE_LOG_LEVEL=VERBOSE \
		-DCMAKE_VERBOSE_MAKEFILE=ON \
		-DCMAKE_EXE_LINKER_FLAGS="-T$(CURDIR)/qemu-xpack.ld -z norelro" \
		-G "Unix Makefiles" \
		-Wno-dev
	cmake --build $(BUILD_DIR) -j --verbose


CONAN_PROFILE  = $(CURDIR)/conan/profiles/riscv32im.conan.profile
CMAKE_TOOLCHAIN = $(CURDIR)/cmake/riscv32im.cmake

.PHONY: xpack-elf
xpack-elf: xpack-silkworm
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

xpack-silkworm:
	@[ -d $(BUILD_DIR) ] || mkdir $(BUILD_DIR)
	@[ -d $(BUILD_DIR)/silkworm ] || mkdir $(BUILD_DIR)/silkworm
	cmake -B$(BUILD_DIR)/silkworm -S../silkworm -DCMAKE_BUILD_TYPE=Debug \
		-DCMAKE_TOOLCHAIN_FILE=$(CMAKE_TOOLCHAIN) \
		-DCMAKE_BUILD_TYPE=Debug \
		-DCONAN_PROFILE_HOST=$(CONAN_PROFILE) \
		-DCONAN_OUTPUT_FOLDER=$(BUILD_DIR)/conan \
		-DCMAKE_MESSAGE_LOG_LEVEL=VERBOSE \
		-DCMAKE_VERBOSE_MAKEFILE=ON \
		-DCMAKE_INSTALL_PREFIX=$(BUILD_DIR)/silkworm-install \
	    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
		-G "Unix Makefiles" \
		-DQEMU_DEBUG=ON \
		-Wno-dev
	cmake --build $(BUILD_DIR)/silkworm -j --target install


gdb:
	riscv-none-elf-gdb -q -ex "target remote :1234" -x .gdbinit build/z6m_debug

qemu-test: xpack-elf
	@echo "QEMU waiting for GDB on :1234..."
	@if [ -z "$(file-name)" ]; then echo "Usage: make qemu file-name=path/to.json"; exit 1; fi
	@N=$$(wc -c <"$(file-name)"); \
	{ printf "123456789_123456789_123456789_123"; printf "1 %u\n" $$N; cat "$(file-name)"; } | \
	qemu-system-riscv32 -M virt -m 2G -nographic \
		-bios $(ELF) -S -gdb tcp::1234 \
		-chardev stdio,mux=on,id=stdio0 \
		-serial chardev:stdio0 \
		-semihosting-config enable=on,chardev=stdio0 \
		-mon chardev=stdio0,mode=readline

rlp-qemu: xpack-elf
	@echo "QEMU waiting for GDB on :1234..."
	@if [ -z "$(file-name)" ]; then echo "Usage: make qemu file-name=path/to.json"; exit 1; fi
	@N=$$(wc -c <"$(file-name)"); \
	{ printf "123456789_123456789_123456789_123"; printf "%u\n" $$N; cat "$(file-name)"; } | \
	qemu-system-riscv32 -M virt -m 2G -nographic \
		-bios $(ELF) -S -gdb tcp::1234 \
		-chardev stdio,mux=on,id=stdio0 \
		-serial chardev:stdio0 \
		-semihosting-config enable=on,chardev=stdio0 \
		-mon chardev=stdio0,mode=readline

# qemu: xpack-elf
# 	@echo "QEMU waiting for GDB on :1234..."
# 	@if [ -z "$(file-name)" ]; then echo "Usage: make qemu file-name=path/to.json"; exit 1; fi
# 	@N=$$(wc -c <"$(file-name)"); \
# 	{ printf "%u\n" $$N; cat "$(file-name)"; } | \
# 	qemu-system-riscv32 -M virt -m 2G -nographic \
# 	  -bios $(ELF) -S -gdb tcp::1234 \
# 	  -serial none -monitor none \
# 	  -chardev stdio,id=sh0,signal=off \
# 	  -semihosting-config enable=on,target=native,chardev=sh0 

# qemu:
# 	@echo "QEMU waiting for GDB on :1234..."
# 	@qemu-system-riscv32 -M virt -nographic -m 2G \
# 	  -bios $(ELF) -S -gdb tcp::1234 -semihosting
# -semihosting-config enable=on,target=native \


# Clean build artifacts
.PHONY: clean
clean:
	rm -rf $(BUILD_DIR)