cmake_minimum_required(VERSION 3.16)
project(SilkwormRV32Demo C CXX ASM)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_EXTENSIONS OFF)


set(SW_INSTALL_DIR ${CMAKE_BINARY_DIR}/zilkworm-install CACHE PATH "")
set(SW_INCLUDE_DIR ${SW_INSTALL_DIR}/include)
set(SW_BIN         "${CMAKE_BINARY_DIR}/zilkworm")
set(SW_CONAN_DIR   "${SW_BIN}/conan2")
set(SW_INC_FALLBACK "${CMAKE_SOURCE_DIR}/..")
set(SW_INC_INSTALL  "${CMAKE_BINARY_DIR}/zilkworm-install/include")



# Make Conan package configs from the external build visible here
if (EXISTS "${SW_CONAN_DIR}/conandeps_legacy.cmake")
  list(APPEND CMAKE_MODULE_PATH "${SW_CONAN_DIR}")
  list(APPEND CMAKE_PREFIX_PATH "${SW_CONAN_DIR}")
  include("${SW_CONAN_DIR}/conandeps_legacy.cmake")
endif()

add_executable(z6m_debug src/sys_getentropy.c src/cppextern.cpp src/main.cpp src/start.S src/sys_sbrk_wrap.c)


add_library(silkworm_core STATIC IMPORTED GLOBAL)
set_target_properties(silkworm_core PROPERTIES
  IMPORTED_LOCATION "${SW_BIN}/zilk_core/core/libsilkworm_core.a"
)
add_dependencies(z6m_debug silkworm_core )

add_library(silkworm_dev STATIC IMPORTED GLOBAL)
set_target_properties(silkworm_dev PROPERTIES
  IMPORTED_LOCATION "${SW_BIN}/zilk_core/dev/libsilkworm_dev.a"
)
add_dependencies(z6m_debug silkworm_dev )



# Include paths:
target_include_directories(z6m_debug PRIVATE "${SW_INC_FALLBACK}")
if (EXISTS "${SW_INC_INSTALL}")
  target_include_directories(z6m_debug PRIVATE "${SW_INC_INSTALL}")
endif()


# Link libs (group to avoid static ordering issues)
# add_dependencies(z6m_debug silkworm_ep)
target_link_options(z6m_debug PRIVATE -Wl,--start-group)
target_link_libraries(z6m_debug PRIVATE 
 c gcc nosys stdc++  
 silkworm_dev silkworm_core)
target_link_options(z6m_debug PRIVATE -Wl,--end-group)

target_link_options(z6m_debug PRIVATE
  # -T ${CMAKE_SOURCE_DIR}/virt.ld
  -Wl,--gc-sections
  -Wl,-Map=${CMAKE_BINARY_DIR}/z6m_debug.map
  # -specs=nosys.specs
)

# make all references to _sbrk/_sbrk_r go to our wrappers
target_link_options(z6m_debug PRIVATE
  -Wl,--wrap=_sbrk
  -Wl,--wrap=_sbrk_r
)
target_compile_options(z6m_debug PRIVATE
  $<$<COMPILE_LANGUAGE:C>:-mstrict-align>
  $<$<COMPILE_LANGUAGE:CXX>:-mstrict-align>
)

## =========== Comment and run and then re-run uncommented ==========
find_package(nlohmann_json REQUIRED)
find_package(magic_enum REQUIRED)
find_package(Microsoft.GSL REQUIRED)
find_package(tl-expected REQUIRED)
target_link_libraries(z6m_debug PRIVATE Microsoft.GSL::GSL)
target_link_libraries(z6m_debug PRIVATE nlohmann_json::nlohmann_json)
target_link_libraries(z6m_debug PRIVATE magic_enum::magic_enum)
target_link_libraries(z6m_debug PRIVATE tl::expected)
## ===================================================================


# If you later see unresolved symbols from 3rd-party .a’s, also add:
target_link_libraries(z6m_debug PRIVATE
  # "${CMAKE_BINARY_DIR}/zilkworm-install/lib/libethash.a"
  # "${CMAKE_BINARY_DIR}/zilkworm-install/lib/libkeccak.a"
  "${CMAKE_BINARY_DIR}/zilkworm-install/lib/libevmc-loader.a"
  "${CMAKE_BINARY_DIR}/zilkworm-install/lib/libevmc-instructions.a"
  "${CMAKE_BINARY_DIR}/zilkworm/third_party/libevmone.a"
  "${CMAKE_BINARY_DIR}/zilkworm/deps/src/blst/libblst.a"
)


set(TESTS_DIR "" CACHE PATH "Directory containing external Execution Spec tests (JSON)")
if(TESTS_DIR)
    if(NOT BUILD_TESTING)
        message(FATAL_ERROR "To enable state transition tests, please enable testing (e.g., -DBUILD_TESTING=ON)")
    endif()

    include(CTest)

    file(GLOB_RECURSE STATE_TRANSITION_TESTS CONFIGURE_DEPENDS "${TESTS_DIR}/*.json")

    foreach(TEST_JSON ${STATE_TRANSITION_TESTS})
        file(RELATIVE_PATH TEST_REL_PATH "${TESTS_DIR}" "${TEST_JSON}")
        set(TEST_NAME "state_transition/${TEST_REL_PATH}")
        add_test(
            NAME ${TEST_NAME}
            COMMAND bash -c "N=`wc -c <'${TEST_JSON}'`; \
                { printf '123456789_123456789_123456789_123'; printf '1 %u\\n' $N; cat '${TEST_JSON}'; } | \
                qemu-system-riscv32 -M virt -m 2G -nographic \
                    -bios '$<TARGET_FILE:z6m_debug>' \
                    -chardev stdio,mux=on,id=stdio0 \
                    -serial chardev:stdio0 \
                    -semihosting-config enable=on,chardev=stdio0 \
                    -mon chardev=stdio0,mode=readline"
        )
        set_tests_properties(${TEST_NAME} PROPERTIES SKIP_RETURN_CODE 2)
    endforeach()
endif()