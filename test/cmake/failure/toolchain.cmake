# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

include("${CMAKE_CURRENT_LIST_DIR}/common.cmake")

# Kernel directories and the generated M= workspace are written directly into Make/Kbuild syntax. Reject unsafe paths
# during configure instead of letting them turn into unrelated Make errors later.
kontra_failure_outer(unprepared_outer [=[
kontra_add_kernel_project(kernel KERNEL_BUILD_DIRECTORY "@KERNEL@")
]=])
kontra_expect_configure_failure(
    unprepared
    unprepared-kernel-build-directory
    "${unprepared_outer}"
    "${valid_nested}"
    UNPREPARED_KERNEL
)

kontra_failure_outer(space_outer [=[
kontra_add_kernel_project(kernel KERNEL_BUILD_DIRECTORY "@KERNEL@")
]=])
kontra_expect_configure_failure(
    space-build
    unsupported-kbuild-path
    "${space_outer}"
    "${valid_nested}"
    SPACE_BUILD
)
kontra_expect_configure_failure(
    equal-build
    unsupported-kbuild-path
    "${space_outer}"
    "${valid_nested}"
    EQUAL_BUILD
)
# Use a tiny fake kernel to check that a missing required Kbuild symbol produces the specific compatibility error. This
# fixture only speaks enough Kbuild for the test; it is not an example of a usable kernel tree.
set(unsupported_root "${KONTRA_TEST_CASE_ROOT}/unsupported-kbuild")
file(REMOVE_RECURSE "${unsupported_root}")
file(MAKE_DIRECTORY
    "${unsupported_root}/source/kernel"
    "${unsupported_root}/kernel/include/config"
)
file(WRITE "${unsupported_root}/kernel/include/config/auto.conf" "CONFIG_CC_IS_CLANG=n\n")
file(WRITE "${unsupported_root}/kernel/Makefile" [=[
.PHONY: modules
modules:
	@echo "Kontraband: unsupported Kbuild; missing symbols: bogus_symbol" >&2
	@false
]=])
kontra_failure_outer(unsupported_outer [=[
kontra_add_kernel_project(
    kernel
    KERNEL_BUILD_DIRECTORY "@KERNEL@"
)
]=])
file(WRITE "${unsupported_root}/source/kernel/CMakeLists.txt" "${valid_nested}")
string(REPLACE "@KERNEL@" "${unsupported_root}/kernel" unsupported_outer "${unsupported_outer}")
file(WRITE "${unsupported_root}/source/CMakeLists.txt" "${unsupported_outer}")
execute_process(
    COMMAND "${CMAKE_COMMAND}" -S "${unsupported_root}/source" -B "${unsupported_root}/build"
        -G Ninja "-DCMAKE_PREFIX_PATH=${KONTRA_TEST_PREFIX}"
    RESULT_VARIABLE unsupported_result
    OUTPUT_VARIABLE unsupported_output
    ERROR_VARIABLE unsupported_error
)
if(unsupported_result EQUAL 0 OR
   NOT "${unsupported_output}${unsupported_error}" MATCHES "Kontraband\\[unsupported-kbuild\\]")
    message(FATAL_ERROR
        "unsupported Kbuild did not fail with its dedicated diagnostic:\n"
        "${unsupported_output}${unsupported_error}"
    )
endif()
# Report a missing linker command separately from a linker that runs but lacks a required feature. Neither error should
# turn into the more general kernel toolchain probe failure.
kontra_failure_outer(unsupported_linker_outer [=[
kontra_add_kernel_project(kernel
    KERNEL_BUILD_DIRECTORY "@KERNEL@"
    KBUILD_ARGUMENTS "LD=false"
)
]=])
kontra_expect_configure_failure(
    unsupported-linker
    unsupported-linker
    "${unsupported_linker_outer}"
    "${valid_nested}"
    FORBID_DIAGNOSTIC kernel-toolchain-probe-failed
)

kontra_failure_outer(missing_linker_outer [=[
kontra_add_kernel_project(kernel
    KERNEL_BUILD_DIRECTORY "@KERNEL@"
    KBUILD_ARGUMENTS "LD=kontra-linker-does-not-exist"
)
]=])
kontra_expect_configure_failure(
    missing-linker
    missing-linker
    "${missing_linker_outer}"
    "${valid_nested}"
    FORBID_DIAGNOSTIC kernel-toolchain-probe-failed
)
# Pass a nested CMake failure through unchanged instead of relabeling an arbitrary project error as a graph error.
kontra_failure_outer(nested_configure_failure_outer [=[
kontra_add_kernel_project(kernel KERNEL_BUILD_DIRECTORY "@KERNEL@")
]=])
kontra_failure_nested(nested_configure_failure_nested "C" [=[
message(FATAL_ERROR "intentional nested configure failure")
]=])
kontra_expect_configure_failure(
    kernel-project-configure-failed
    kernel-project-configure-failed
    "${nested_configure_failure_outer}"
    "${nested_configure_failure_nested}"
)

# These cases cover a missing kernel root, an empty multi-config configuration set, and an empty compiler command from
# Kbuild.
kontra_failure_outer(missing_kernel_directory_outer [=[
kontra_add_kernel_project(
    kernel
    KERNEL_BUILD_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/missing-kernel"
)
]=])
kontra_expect_configure_failure(
    missing-kernel-build-directory
    missing-kernel-build-directory
    "${missing_kernel_directory_outer}"
    "${valid_nested}"
)

kontra_failure_outer(missing_configuration_outer [=[
kontra_add_kernel_project(kernel KERNEL_BUILD_DIRECTORY "@KERNEL@")
]=])
kontra_expect_configure_failure(
    missing-configuration
    missing-configuration
    "${missing_configuration_outer}"
    "${valid_nested}"
    MULTI_CONFIG_EMPTY
)

kontra_failure_outer(invalid_toolchain_outer [=[
kontra_add_kernel_project(
    kernel
    KERNEL_BUILD_DIRECTORY "@KERNEL@"
    KBUILD_ARGUMENTS "CC="
)
]=])
kontra_expect_configure_failure(
    invalid-kernel-toolchain
    invalid-kernel-toolchain
    "${invalid_toolchain_outer}"
    "${valid_nested}"
)

kontra_failure_outer(invalid_processor_outer [=[
kontra_add_kernel_project(
    kernel
    KERNEL_BUILD_DIRECTORY "@KERNEL@"
    KBUILD_ARGUMENTS "UTS_MACHINE="
)
]=])
kontra_expect_configure_failure(
    invalid-kernel-processor
    invalid-kernel-toolchain
    "${invalid_processor_outer}"
    "${valid_nested}"
)

# A program named make is insufficient: generated Kbuild wrappers require GNU Make syntax.
kontra_expect_script_failure(missing-gnu-make missing-gnu-make [=[
include("@PREFIX@/share/cmake/kontraband/detail/toolchain.cmake")
set(fake_dir "${CMAKE_CURRENT_LIST_DIR}/fake_make")
file(MAKE_DIRECTORY "${fake_dir}")
foreach(name IN ITEMS make gmake)
    file(WRITE "${fake_dir}/${name}" "#!/bin/sh\necho 'Not GNU Make'\n")
    file(CHMOD "${fake_dir}/${name}"
        PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE
    )
endforeach()
set(CMAKE_PROGRAM_PATH "${fake_dir}")
_kontra_resolve_make(ignored)
]=])
