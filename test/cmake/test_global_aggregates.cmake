# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

include("${CMAKE_CURRENT_LIST_DIR}/test_common.cmake")

# Global aggregate targets cover independent nested kernel projects in the same outer build.
set(source "${KONTRA_TEST_CASE_ROOT}/source")
set(build "${KONTRA_TEST_CASE_ROOT}/build")
set(kernel "${KONTRA_TEST_CASE_ROOT}/kernel")
file(REMOVE_RECURSE "${KONTRA_TEST_CASE_ROOT}")
file(MAKE_DIRECTORY "${source}/first" "${source}/second")
file(COPY "${KONTRA_TEST_FIXTURE_ROOT}/fake_kernel/" DESTINATION "${kernel}")

file(WRITE "${source}/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.31.6)
project(global_aggregates LANGUAGES NONE)
find_package(kontraband CONFIG REQUIRED)

kontra_add_kernel_project(first DIRECTORY first KERNEL_BUILD_DIRECTORY "${FIXTURE_KERNEL_DIR}")
kontra_add_kernel_module(module PROJECT first)

kontra_add_kernel_project(second DIRECTORY second KERNEL_BUILD_DIRECTORY "${FIXTURE_KERNEL_DIR}")
kontra_add_kernel_module(module PROJECT second)
]=])

foreach(project IN ITEMS first second)
    file(WRITE "${source}/${project}/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.31.6)
project(kernel LANGUAGES C)
add_library(module OBJECT module.c)
]=])
    file(WRITE "${source}/${project}/module.c" "int module_value;\n")
endforeach()

kontra_configure("${source}" "${build}" "${kernel}" Ninja)

set(first_workspace "${build}/kontra/projects/first/modules/module/Release/workspace")
set(second_workspace "${build}/kontra/projects/second/modules/module/Release/workspace")
set(first_stamp "${build}/kontra/projects/first/modules/module/Release/state/unchecked.stamp")
set(second_stamp "${build}/kontra/projects/second/modules/module/Release/state/unchecked.stamp")

# The checked global aggregate reaches every project.
kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kontra_kernel_modules)
kontra_assert_exists("${first_workspace}/module.ko")
kontra_assert_exists("${second_workspace}/module.ko")

# The global clean aggregate reaches every project.
kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kontra_kernel_modules.clean)
kontra_assert_not_exists("${first_workspace}/module.ko")
kontra_assert_not_exists("${second_workspace}/module.ko")

# The unchecked global target reaches every project and creates unchecked stamps. Global clean removes those stamps and
# the Kbuild outputs.
kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kontra_kernel_modules.unchecked)
kontra_assert_exists("${first_workspace}/module.ko")
kontra_assert_exists("${second_workspace}/module.ko")
kontra_assert_exists("${first_stamp}")
kontra_assert_exists("${second_stamp}")
kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kontra_kernel_modules.clean)
kontra_assert_not_exists("${first_workspace}/module.ko")
kontra_assert_not_exists("${second_workspace}/module.ko")
kontra_assert_not_exists("${first_stamp}")
kontra_assert_not_exists("${second_stamp}")
