# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

include("${CMAKE_CURRENT_LIST_DIR}/test_common.cmake")

# KONTRA_KBUILD_VERBOSE controls CMake-driven development builds. It stays visible in the cache and toggles V=1 when
# CMake calls the generated wrapper, but it must not be saved into the projection itself.
kontra_copy_fixture(project source build)
set(kernel "${KONTRA_TEST_FIXTURE_ROOT}/fake_kernel")

kontra_configure("${source}" "${build}" "${kernel}" Ninja)
kontra_assert_contains("${build}/CMakeCache.txt" "KONTRA_KBUILD_VERBOSE:BOOL=OFF")
set(workspace "${build}/kontra/projects/kernel_project/modules/fixture_module/Release/workspace")
file(REMOVE "${workspace}/kbuild-arguments.txt")
kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kernel_project.fixture_module)
kontra_assert_not_contains("${workspace}/kbuild-arguments.txt" "(^|\n)V=1(\n|$)")

kontra_configure("${source}" "${build}" "${kernel}" Ninja "-DKONTRA_KBUILD_VERBOSE=ON")
kontra_assert_contains("${build}/CMakeCache.txt" "KONTRA_KBUILD_VERBOSE:BOOL=ON")
kontra_assert_not_contains("${workspace}/Makefile" "V=1")
file(REMOVE "${workspace}/kbuild-arguments.txt")
kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kernel_project.fixture_module)
kontra_assert_contains("${workspace}/kbuild-arguments.txt" "(^|\n)V=1(\n|$)")
