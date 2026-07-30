# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

include("${CMAKE_CURRENT_LIST_DIR}/test_common.cmake")

# Assembly still uses Kbuild's normal rule. This checks that CMake resolves ASM includes, definitions, and options into
# the projection while the nested CMake project identifies ASM with Kbuild's selected compiler.
file(REMOVE_RECURSE "${KONTRA_TEST_CASE_ROOT}")
set(source "${KONTRA_TEST_CASE_ROOT}/source")
set(build "${KONTRA_TEST_CASE_ROOT}/build")
file(MAKE_DIRECTORY "${source}/kernel/include")

file(WRITE "${source}/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.31.6)
project(assembly LANGUAGES NONE)
find_package(kontraband CONFIG REQUIRED)
kontra_add_kernel_project(kernel KERNEL_BUILD_DIRECTORY "@KERNEL@")
kontra_add_kernel_module(module PROJECT kernel)
]=])
file(READ "${source}/CMakeLists.txt" outer)
string(REPLACE "@KERNEL@" "${KONTRA_TEST_FIXTURE_ROOT}/fake_kernel" outer "${outer}")
file(WRITE "${source}/CMakeLists.txt" "${outer}")

file(WRITE "${source}/kernel/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.31.6)
project(assembly_kernel LANGUAGES C ASM)
add_library(module OBJECT entry.c thunk.S)
target_include_directories(module PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_compile_definitions(module PRIVATE "$<$<COMPILE_LANGUAGE:ASM>:KONTRA_ASM_DEFINE=1>")
target_compile_options(module PRIVATE "$<$<COMPILE_LANGUAGE:ASM>:-Wa,--fatal-warnings>")
]=])

file(WRITE "${source}/kernel/entry.c" "")
file(WRITE "${source}/kernel/thunk.S" "")
file(WRITE "${source}/kernel/include/config.h" "#pragma once\n")

kontra_configure("${source}" "${build}" "${KONTRA_TEST_FIXTURE_ROOT}/fake_kernel" Ninja)
set(nested_cache "${build}/kontra/projects/kernel/subbuild/CMakeCache.txt")
kontra_assert_contains("${nested_cache}" "CMAKE_ASM_COMPILER:FILEPATH=.*/cc")
set(workspace "${build}/kontra/projects/kernel/modules/module/Release/workspace")
set(kbuild "${workspace}/Kbuild")
kontra_assert_contains("${kbuild}" "module-y := .*projection/kernel/entry.o.*projection/kernel/thunk.o")
kontra_assert_contains("${kbuild}" "AFLAGS_projection/kernel/thunk.o")
kontra_assert_contains("${kbuild}" "KONTRA_ASM_DEFINE=1")
kontra_assert_contains("${kbuild}" "-Wa,--fatal-warnings")
kontra_assert_contains("${kbuild}" "-I\\$\\(src\\)/projection/kernel/include")
kontra_run("${CMAKE_COMMAND}" --build "${build}" --target kernel.module.unchecked)
