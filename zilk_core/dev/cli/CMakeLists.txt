
# Copyright 2025 The Silkworm Authors
# SPDX-License-Identifier: Apache-2.0


add_executable(state_transition "runner.cpp")
target_link_libraries(state_transition PRIVATE silkworm_dev)
# file(GLOB STATE_TRANSITION_TESTS CONFIGURE_DEPENDS "state_transition_sample*.json")
# add_custom_command(
#   TARGET state_transition
#   POST_BUILD
#   COMMAND ${CMAKE_COMMAND} ARGS -E copy_if_different ${STATE_TRANSITION_TESTS} "${CMAKE_CURRENT_BINARY_DIR}"
# )

set(TESTS_DIR "" CACHE PATH "Directory containing external Execution Spec tests (JSON)")
if(TESTS_DIR)
    if(NOT BUILD_TESTING)
        message(FATAL_ERROR "To enable state transition tests, please enable testing (e.g., -DBUILD_TESTING=ON)")
    endif()

    file(GLOB_RECURSE STATE_TRANSITION_TESTS CONFIGURE_DEPENDS "${TESTS_DIR}/*.json")

    foreach(TEST_JSON ${STATE_TRANSITION_TESTS})
        file(RELATIVE_PATH TEST_REL_PATH ${TESTS_DIR} ${TEST_JSON})
        set(TEST_NAME "state_transition/${TEST_REL_PATH}")
        add_test(
            NAME ${TEST_NAME}
            COMMAND state_transition ${TEST_JSON}
        )
        set_tests_properties(${TEST_NAME} PROPERTIES SKIP_RETURN_CODE 2)
    endforeach()
endif()
