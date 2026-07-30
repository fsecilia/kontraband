# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

include("${CMAKE_CURRENT_LIST_DIR}/test_common.cmake")

# Pass the outer multi-config configuration list to the nested project unchanged. Each configuration gets its own Kbuild
# workspace, but all configurations must agree on one source order for installation.
kontra_copy_fixture(project source build)
set(kernel "${KONTRA_TEST_FIXTURE_ROOT}/fake_kernel")
set(configuration_types_argument "-DCMAKE_CONFIGURATION_TYPES=Debug;Custom")
execute_process(
    COMMAND "${CMAKE_COMMAND}" -S "${source}" -B "${build}" -G "Ninja Multi-Config"
        "-DCMAKE_PREFIX_PATH=${KONTRA_TEST_PREFIX}"
        "-DFIXTURE_KERNEL_DIR=${kernel}"
        "${configuration_types_argument}"
    RESULT_VARIABLE configure_result OUTPUT_VARIABLE configure_output ERROR_VARIABLE configure_error
)
if(NOT configure_result EQUAL 0)
    message(FATAL_ERROR "multi-config configure failed:\n${configure_output}${configure_error}")
endif()
set(configure_log "${configure_output}${configure_error}")
if(configure_log MATCHES "\n  '-g'(\n| \\([0-9]+ occurrences\\))")
    message(FATAL_ERROR "ordinary multi-config Debug compiler baseline produced a discard diagnostic:\n${configure_log}")
endif()
set(nested_cache "${build}/kontra/projects/kernel_project/subbuild/CMakeCache.txt")
file(READ "${nested_cache}" nested_cache_text)
if(NOT nested_cache_text MATCHES "CMAKE_CONFIGURATION_TYPES:[^=]+=Debug;Custom")
    message(FATAL_ERROR "nested configuration set was not preserved")
endif()

kontra_run("${CMAKE_COMMAND}" --build "${build}" --config Debug --target kernel_project.fixture_module.unchecked)
set(debug_workspace "${build}/kontra/projects/kernel_project/modules/fixture_module/Debug/workspace")
set(custom_workspace "${build}/kontra/projects/kernel_project/modules/fixture_module/Custom/workspace")
kontra_assert_exists("${debug_workspace}/fixture_output.ko")
kontra_assert_not_exists("${custom_workspace}/fixture_output.ko")

# The checked target still runs Kbuild; the unchecked target is already up to date.
file(REMOVE "${debug_workspace}/kbuild-invocations.txt")
kontra_run("${CMAKE_COMMAND}" --build "${build}" --config Debug --target kernel_project.fixture_module)
file(STRINGS "${debug_workspace}/kbuild-invocations.txt" invocations)
list(LENGTH invocations count)
if(NOT count EQUAL 1)
    message(FATAL_ERROR "checked Debug build did not enter Kbuild")
endif()
kontra_run("${CMAKE_COMMAND}" --build "${build}" --config Debug --target kernel_project.fixture_module.unchecked)
if(NOT KONTRA_LAST_OUTPUT MATCHES "no work to do")
    message(FATAL_ERROR "second Debug unchecked build was not inert")
endif()

# Building one configuration must not touch another configuration's module workspace.
kontra_run("${CMAKE_COMMAND}" --build "${build}" --config Custom --target kernel_project.fixture_module)
kontra_assert_exists("${custom_workspace}/fixture_output.ko")
file(TIMESTAMP "${custom_workspace}/fixture_output.ko" custom_before "%s.%f")
kontra_run("${CMAKE_COMMAND}" -E sleep 1)
file(APPEND "${source}/src/core.cpp" "\n// selected multi-config dependency refresh\n")
kontra_run("${CMAKE_COMMAND}" --build "${build}" --config Debug --target kernel_project.fixture_module.unchecked)
file(TIMESTAMP "${custom_workspace}/fixture_output.ko" custom_after "%s.%f")
if(NOT custom_after STREQUAL custom_before)
    message(FATAL_ERROR "Debug unchecked build changed the Custom module")
endif()

# Installation chooses one configuration but uses the source mapping shared by all configurations.
set(prefix "${KONTRA_TEST_CASE_ROOT}/install")
kontra_run("${CMAKE_COMMAND}" --install "${build}" --config Debug --prefix "${prefix}" --component dkms-module)
kontra_assert_exists("${prefix}/src/fixture-1.2.3/Kbuild")
kontra_assert_contains("${prefix}/src/fixture-1.2.3/projection/src/core.cpp" "selected multi-config dependency refresh")

# Kbuild consumes objects in order. Two configurations with the same sources in a different order therefore cannot share
# one installed projection.
set(mismatch_root "${KONTRA_TEST_CASE_ROOT}/sequence-mismatch")
set(mismatch_source "${mismatch_root}/source")
set(mismatch_build "${mismatch_root}/build")
file(MAKE_DIRECTORY "${mismatch_source}/kernel")
file(WRITE "${mismatch_source}/kernel/a.c" "")
file(WRITE "${mismatch_source}/kernel/b.c" "")

file(WRITE "${mismatch_source}/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.31.6)
project(sequence_mismatch LANGUAGES NONE)
find_package(kontraband CONFIG REQUIRED)
kontra_add_kernel_project(kernel KERNEL_BUILD_DIRECTORY "@KERNEL@")
kontra_add_kernel_module(module PROJECT kernel)
]=])
file(READ "${mismatch_source}/CMakeLists.txt" mismatch_outer)
string(REPLACE "@KERNEL@" "${kernel}" mismatch_outer "${mismatch_outer}")
file(WRITE "${mismatch_source}/CMakeLists.txt" "${mismatch_outer}")

file(WRITE "${mismatch_source}/kernel/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.31.6)
project(sequence_mismatch_kernel LANGUAGES C)
add_library(module OBJECT)
target_sources(module PRIVATE
    "$<$<CONFIG:Debug>:${CMAKE_CURRENT_SOURCE_DIR}/a.c>"
    "$<$<CONFIG:Debug>:${CMAKE_CURRENT_SOURCE_DIR}/b.c>"
    "$<$<NOT:$<CONFIG:Debug>>:${CMAKE_CURRENT_SOURCE_DIR}/b.c>"
    "$<$<NOT:$<CONFIG:Debug>>:${CMAKE_CURRENT_SOURCE_DIR}/a.c>"
)
]=])

execute_process(
    COMMAND "${CMAKE_COMMAND}" -S "${mismatch_source}" -B "${mismatch_build}" -G "Ninja Multi-Config"
        "-DCMAKE_PREFIX_PATH=${KONTRA_TEST_PREFIX}"
        "-DCMAKE_CONFIGURATION_TYPES=Debug;Custom"
    RESULT_VARIABLE mismatch_result
    OUTPUT_VARIABLE mismatch_output
    ERROR_VARIABLE mismatch_error
)
set(mismatch_log "${mismatch_output}${mismatch_error}")
if(mismatch_result EQUAL 0 OR
   NOT mismatch_log MATCHES "Kontraband\\[multi-config-file-sequence-mismatch\\]:")
    message(FATAL_ERROR
        "multi-config sequence mismatch did not fail with the expected diagnostic:\n${mismatch_log}"
    )
endif()
