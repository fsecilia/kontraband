# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

include("${CMAKE_CURRENT_LIST_DIR}/test_common.cmake")
kontra_copy_fixture(project source build)
set(kernel "${KONTRA_TEST_FIXTURE_ROOT}/fake_kernel")

# The fake Kbuild fails if two commands enter the same module workspace at once, making this race deterministic.
# Request checked and unchecked together because both write to that workspace.
kontra_configure(
    "${source}" "${build}" "${kernel}" Ninja
    "-DFIXTURE_EXTRA_KBUILD_ARGUMENT=KONTRA_TEST_SERIALIZE=1"
)
kontra_run(
    "${CMAKE_COMMAND}" --build "${build}" --parallel 8
    --target kernel_project.fixture_module kernel_project.fixture_module.unchecked
)
