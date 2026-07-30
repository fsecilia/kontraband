# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

include("${CMAKE_CURRENT_LIST_DIR}/test_common.cmake")

# KBUILD_ARGUMENTS are saved in the generated Makefile. Test common toolchain assignments and one argument containing
# spaces, then check that a detached build cannot override those saved values from the command line.
kontra_copy_fixture(project source build)
set(kernel "${KONTRA_TEST_FIXTURE_ROOT}/fake_kernel")
kontra_configure("${source}" "${build}" "${kernel}" Ninja
    "-DFIXTURE_ARCH=arm64"
    "-DFIXTURE_CROSS_COMPILE=aarch64-linux-gnu-"
    "-DFIXTURE_LLVM=-21"
    "-DFIXTURE_LD=/usr/bin/true"
    "-DFIXTURE_EXTRA_KBUILD_ARGUMENT=KONTRA_TEST_ARGUMENT=hello world"
)
kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kernel_project.fixture_module)
set(record "${build}/kontra/projects/kernel_project/modules/fixture_module/Release/workspace/kbuild-arguments.txt")
kontra_assert_contains("${record}" "ARCH=arm64")
kontra_assert_contains("${record}" "CROSS_COMPILE=aarch64-linux-gnu-")
kontra_assert_contains("${record}" "LLVM=-21")
kontra_assert_contains("${record}" "KONTRA_TEST_ARGUMENT=hello world")

file(STRINGS "${record}" records)
foreach(required IN ITEMS
    "LDFLAGS_MODULE=--force-group-allocation"
    "LDFLAGS_MODULE_ORIGIN=command line"
    "CONFIG_DEBUG_INFO_BTF_MODULES="
    "CONFIG_DEBUG_INFO_BTF_MODULES_ORIGIN=command line"
)
    list(FIND records "${required}" required_index)
    if(required_index EQUAL -1)
        message(FATAL_ERROR "Kbuild invocation is missing required assignment '${required}': ${records}")
    endif()
endforeach()

# Detached builds use the same Kbuild arguments and override rules as the development workspace.
set(prefix "${KONTRA_TEST_CASE_ROOT}/install")
kontra_run("${CMAKE_COMMAND}" --install "${build}" --prefix "${prefix}" --component dkms-module)
set(detached "${prefix}/src/fixture-1.2.3")
string(CONCAT expected_detached_arguments
    "KONTRA_KBUILD_ARGUMENTS := 'ARCH=arm64' 'LLVM=-21' 'CROSS_COMPILE=aarch64-linux-gnu-' "
    "'LD=/usr/bin/true' 'KONTRA_TEST_ARGUMENT=hello world'"
)
kontra_assert_contains("${detached}/Makefile" "${expected_detached_arguments}")
file(REMOVE "${detached}/kbuild-arguments.txt")
kontra_run("${CMAKE_COMMAND}" -E chdir "${detached}" make
    "KERNEL_DIR=${kernel}" "ARCH=x86" "LLVM=1" "CROSS_COMPILE=wrong-" modules)
kontra_assert_contains("${detached}/kbuild-arguments.txt" "ARCH=arm64")
kontra_assert_contains("${detached}/kbuild-arguments.txt" "CROSS_COMPILE=aarch64-linux-gnu-")
kontra_assert_contains("${detached}/kbuild-arguments.txt" "LLVM=-21")
kontra_assert_contains("${detached}/kbuild-arguments.txt" "KONTRA_TEST_ARGUMENT=hello world")
kontra_assert_not_contains("${detached}/kbuild-arguments.txt" "ARCH=x86")
kontra_assert_not_contains("${detached}/kbuild-arguments.txt" "LLVM=1")
kontra_assert_not_contains("${detached}/kbuild-arguments.txt" "CROSS_COMPILE=wrong-")
