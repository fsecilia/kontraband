# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

include("${CMAKE_CURRENT_LIST_DIR}/common.cmake")

# Project installation puts each module under its output name. Two modules with the same output name would overwrite
# each other in the detached tree, so reject that before adding install rules.
kontra_failure_outer(duplicate_install_outer [=[
kontra_add_kernel_project(kernel KERNEL_BUILD_DIRECTORY "@KERNEL@")
kontra_add_kernel_module(first PROJECT kernel OUTPUT_NAME duplicate)
kontra_add_kernel_module(second PROJECT kernel OUTPUT_NAME duplicate)
kontra_install_kernel_project(kernel DESTINATION share/modules)
]=])
kontra_failure_nested(duplicate_install_nested "C" [=[
add_library(first OBJECT first.c)
add_library(second OBJECT second.c)
]=])
# This case needs two different module sources, so build it here instead of complicating the common one-source helper.
set(duplicate_root "${KONTRA_TEST_CASE_ROOT}/duplicate-project-install-output")
file(REMOVE_RECURSE "${duplicate_root}")
file(MAKE_DIRECTORY "${duplicate_root}/source/kernel")
string(REPLACE "@KERNEL@" "${KONTRA_TEST_FIXTURE_ROOT}/fake_kernel" duplicate_outer "${duplicate_install_outer}")
file(WRITE "${duplicate_root}/source/CMakeLists.txt" "${duplicate_outer}")
file(WRITE "${duplicate_root}/source/kernel/CMakeLists.txt" "${duplicate_install_nested}")
file(WRITE "${duplicate_root}/source/kernel/first.c" "")
file(WRITE "${duplicate_root}/source/kernel/second.c" "")
execute_process(
    COMMAND "${CMAKE_COMMAND}" -S "${duplicate_root}/source" -B "${duplicate_root}/build"
        -G Ninja "-DCMAKE_PREFIX_PATH=${KONTRA_TEST_PREFIX}"
    RESULT_VARIABLE duplicate_result
    OUTPUT_VARIABLE duplicate_output
    ERROR_VARIABLE duplicate_error
)
if(duplicate_result EQUAL 0 OR
   NOT "${duplicate_output}${duplicate_error}" MATCHES "Kontraband\\[duplicate-project-install-output-name\\]:")
    message(FATAL_ERROR
        "duplicate project install output did not fail loudly:\n${duplicate_output}${duplicate_error}"
    )
endif()
# Installing a project with no modules would create an empty tree that looks successful but has nothing DKMS or a
# detached Kbuild build can use.
kontra_failure_outer(no_modules_outer [=[
kontra_add_kernel_project(kernel KERNEL_BUILD_DIRECTORY "@KERNEL@")
kontra_install_kernel_project(kernel DESTINATION share/modules)
]=])
kontra_expect_configure_failure(
    kernel-project-has-no-modules
    kernel-project-has-no-modules
    "${no_modules_outer}"
    "${valid_nested}"
)
