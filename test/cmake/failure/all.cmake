# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

# Run all diagnostic failure cases in one CTest process instead of registering every tiny fixture as its own test.
# Group the files by the part of Kontraband they exercise.
include("${CMAKE_CURRENT_LIST_DIR}/api.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/graph.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/install.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/toolchain.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/internal.cmake")
