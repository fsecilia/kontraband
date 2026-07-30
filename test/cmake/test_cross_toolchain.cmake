# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

include("${CMAKE_CURRENT_LIST_DIR}/test_common.cmake")
include("${KONTRA_TEST_PREFIX}/share/cmake/kontraband/detail/toolchain.cmake")

# Test the narrow filter that converts Kbuild's compiler command for nested CMake, separately from project setup.
_kontra_resolve_make(make_executable)
set(probe_kernel "${KONTRA_TEST_FIXTURE_ROOT}/fake_kernel_probe")
set(probe_directory "${KONTRA_TEST_CASE_ROOT}/probe-only")
_kontra_probe_kernel_toolchain(
    "${probe_kernel}"
    "${probe_directory}"
    ""
    "${make_executable}"
    probed_compiler
    probed_processor
)
if(NOT probed_compiler STREQUAL "/usr/bin/env cc --target=x86_64-linux-gnu -m64")
    message(FATAL_ERROR "unexpected filtered compiler command '${probed_compiler}'")
endif()
if(NOT probed_processor STREQUAL "x86_64")
    message(FATAL_ERROR "unexpected probed processor '${probed_processor}'")
endif()

# Choose a target different from the current Linux host so this still tests cross-compilation when the host is arm64.
if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Linux" AND CMAKE_HOST_SYSTEM_PROCESSOR STREQUAL "aarch64")
    set(target_processor x86_64)
    set(target_triple x86_64-linux-gnu)
else()
    set(target_processor aarch64)
    set(target_triple aarch64-linux-gnu)
endif()

kontra_copy_fixture(cross source build)
set(kernel "${KONTRA_TEST_FIXTURE_ROOT}/fake_kernel_cross")
kontra_configure(
    "${source}"
    "${build}"
    "${kernel}"
    Ninja
    "-DFIXTURE_TARGET_PROCESSOR=${target_processor}"
    "-DFIXTURE_TARGET_TRIPLE=${target_triple}"
)
set(private_root "${build}/kontra/projects/kernel_project")
set(compiler_probe "${private_root}/compiler-probe/compiler.txt")
set(processor_probe "${private_root}/compiler-probe/processor.txt")
set(cross_state "${private_root}/subbuild/cross-state.txt")

kontra_assert_contains_literal("${compiler_probe}" "compiler-wrapper --target=${target_triple}")
kontra_assert_not_contains("${compiler_probe}" "KONTRA_FAKE_CPPFLAG")
kontra_assert_not_contains("${compiler_probe}" "KONTRA_FAKE_CFLAG")
kontra_assert_not_contains("${compiler_probe}" "-Werror")
kontra_assert_contains_literal("${processor_probe}" "${target_processor}")

kontra_assert_contains_literal("${cross_state}" "system_name=Linux")
kontra_assert_contains_literal("${cross_state}" "system_processor=${target_processor}")
kontra_assert_contains_literal("${cross_state}" "crosscompiling=TRUE")
kontra_assert_contains_literal("${cross_state}" "try_compile_target_type=STATIC_LIBRARY")
kontra_assert_contains_literal("${cross_state}" "c_compiler_arg1= --target=${target_triple}")
kontra_assert_contains_literal("${cross_state}" "cxx_compiler_arg1= --target=${target_triple}")
