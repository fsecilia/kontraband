# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

include("${CMAKE_CURRENT_LIST_DIR}/test_common.cmake")
file(REMOVE_RECURSE "${KONTRA_TEST_WORK_ROOT}" "${KONTRA_TEST_PREFIX}")
file(MAKE_DIRECTORY "${KONTRA_TEST_WORK_ROOT}")
kontra_run(
    "${CMAKE_COMMAND}" -S "${KONTRA_TEST_SOURCE_ROOT}" -B "${KONTRA_TEST_WORK_ROOT}/package"
    -G Ninja
    "-DCMAKE_INSTALL_PREFIX=${KONTRA_TEST_PREFIX}"
    -DKONTRABAND_BUILD_TESTS=OFF
)
kontra_run("${CMAKE_COMMAND}" --build "${KONTRA_TEST_WORK_ROOT}/package" --target install)
