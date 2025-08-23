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
		-G "Unix Makefiles" \
		-Wno-dev
	cmake --build $(BUILD_DIR) -j --verbose


CONAN_PROFILE  = $(CURDIR)/conan/profiles/riscv32im.conan.profile
CMAKE_TOOLCHAIN = $(CURDIR)/cmake/riscv32im.cmake

.PHONY: xpack-elf
xpack-elf: 
	@[ -d $(BUILD_DIR) ] || mkdir $(BUILD_DIR)
	cmake -B$(BUILD_DIR) -S. -DCMAKE_BUILD_TYPE=Debug \
		-DCMAKE_TOOLCHAIN_FILE=$(CMAKE_TOOLCHAIN) \
		-DCMAKE_BUILD_TYPE=Debug \
		-DCONAN_PROFILE_HOST=$(CONAN_PROFILE) \
		-DCONAN_OUTPUT_FOLDER=$(BUILD_DIR)/conan \
		-DCMAKE_MESSAGE_LOG_LEVEL=VERBOSE \
		-DCMAKE_VERBOSE_MAKEFILE=ON \
		-G "Unix Makefiles" \
		-Wno-dev
	cmake --build $(BUILD_DIR) -j --verbose


.PHONY: run
run:
	qemu-system-riscv32 -M virt -bios $(ELF) -nographic \
	    -semihosting -semihosting-config enable=on,target=native


gdb:
	riscv-none-elf-gdb -q -x .gdbinit build/z6m_debug


qemu:
	@echo "QEMU waiting for GDB on :1234..."
	@echo "In another terminal: riscv-none-elf-gdb $(ELF)"
	@echo "(gdb) target remote :1234 ; break main ; continue"
	qemu-system-riscv32 -M virt -nographic -m 2G \
	  -bios $(ELF) -S -gdb tcp::1234
# -semihosting-config enable=on,target=native \


# Clean build artifacts
.PHONY: clean
clean:
	rm -rf $(BUILD_DIR)