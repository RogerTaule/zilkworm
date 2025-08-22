BUILD_DIR := build
CMAKE_TOOLCHAIN := riscv32im.cmake
CONAN_PROFILE  := riscv32im.conan.profile
ELF := $(BUILD_DIR)/z6m_debug

.PHONY: all
all: 
	@[ -d $(BUILD_DIR) ] || mkdir $(BUILD_DIR)
	cmake -B$(BUILD_DIR) -S. -DCMAKE_BUILD_TYPE=Debug \
		-DCMAKE_TOOLCHAIN_FILE=riscv32im.cmake \
		-DCMAKE_BUILD_TYPE=Debug \
		-DCONAN_PROFILE_HOST=$(CONAN_PROFILE) \
		-DCONAN_OUTPUT_FOLDER=$(BUILD_DIR)/conan \
		-DCMAKE_PROJECT_TOP_LEVEL_INCLUDES=../silkworm/cmake/conan.cmake \
		-DCMAKE_MESSAGE_LOG_LEVEL=VERBOSE \
		-G "Unix Makefiles" \
		-Wno-dev
	cmake --build $(BUILD_DIR) -j


.PHONY: run
run:
	qemu-system-riscv32 -M virt -bios $(ELF) -nographic \
	    -semihosting -semihosting-config enable=on,target=native


gdb:
	@echo "QEMU waiting for GDB on :1234..."
	@echo "In another terminal: riscv-none-elf-gdb $(ELF)"
	@echo "(gdb) target remote :1234 ; break main ; continue"
	qemu-system-riscv32 -M virt -nographic -bios none \
	  -kernel $(ELF) -semihosting \
	  -semihosting-config enable=on,target=native \
	  -S -gdb tcp::1234


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