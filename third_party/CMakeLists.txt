# Copyright 2025 The Silkworm Authors
# SPDX-License-Identifier: Apache-2.0

# please keep the list sorted
# add_subdirectory(blst)
include(evmone/evmone/cmake/blst.cmake)
set(INTX_INSTALL TRUE)
add_subdirectory(intx/intx)

add_subdirectory(evmone) # depends on intx
