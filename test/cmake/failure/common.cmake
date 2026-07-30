# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

include_guard(GLOBAL)
include("${CMAKE_CURRENT_LIST_DIR}/../test_common.cmake")

# Keep failure fixtures tiny. Each case should contain only what is needed to reach one diagnostic, so an earlier
# CMake or Kontraband error cannot accidentally make the test pass.
function(kontra_expect_configure_failure name expected outer nested)
    set(options SPACE_BUILD EQUAL_BUILD UNPREPARED_KERNEL MULTI_CONFIG_EMPTY)
    set(one_value_args FORBID_DIAGNOSTIC)
    cmake_parse_arguments(PARSE_ARGV 4 args "${options}" "${one_value_args}" "")

    set(root "${KONTRA_TEST_CASE_ROOT}/${name}")
    file(REMOVE_RECURSE "${root}")
    file(MAKE_DIRECTORY "${root}/source/kernel")

    if(args_UNPREPARED_KERNEL)
        set(kernel "${root}/unprepared-kernel")
        file(MAKE_DIRECTORY "${kernel}")
        file(WRITE "${kernel}/Makefile" "")
    else()
        set(kernel "${KONTRA_TEST_FIXTURE_ROOT}/fake_kernel")
    endif()

    string(REPLACE "@KERNEL@" "${kernel}" outer "${outer}")
    string(REPLACE "@PREFIX@" "${KONTRA_TEST_PREFIX}" outer "${outer}")
    file(WRITE "${root}/source/CMakeLists.txt" "${outer}")
    file(WRITE "${root}/source/kernel/CMakeLists.txt" "${nested}")
    file(WRITE "${root}/source/kernel/other.c" "")

    if(args_SPACE_BUILD)
        set(build "${root}/build space")
    elseif(args_EQUAL_BUILD)
        set(build "${root}/build=equal")
    else()
        set(build "${root}/build")
    endif()

    if(args_MULTI_CONFIG_EMPTY)
        set(generator_arguments -G "Ninja Multi-Config" "-DCMAKE_CONFIGURATION_TYPES=")
    else()
        set(generator_arguments -G Ninja)
    endif()

    execute_process(
        COMMAND "${CMAKE_COMMAND}" -S "${root}/source" -B "${build}"
            ${generator_arguments} "-DCMAKE_PREFIX_PATH=${KONTRA_TEST_PREFIX}"
        RESULT_VARIABLE result
        OUTPUT_VARIABLE output
        ERROR_VARIABLE error
    )
    set(log "${output}${error}")

    if(result EQUAL 0 OR NOT log MATCHES "Kontraband\\[${expected}\\]:")
        message(FATAL_ERROR "${name} did not fail with Kontraband[${expected}]:\n${log}")
    endif()
    if(NOT "${args_FORBID_DIAGNOSTIC}" STREQUAL "" AND log MATCHES "Kontraband\\[${args_FORBID_DIAGNOSTIC}\\]:")
        message(FATAL_ERROR
            "${name} fell through to forbidden diagnostic Kontraband[${args_FORBID_DIAGNOSTIC}]:\n${log}"
        )
    endif()
endfunction()

# Private checks do not need a fake public project around them. Run the smallest script that reaches the check and
# require its exact diagnostic, so these fixtures cannot be mistaken for supported client code.
function(kontra_expect_script_failure name expected body)
    set(root "${KONTRA_TEST_CASE_ROOT}/${name}")
    file(REMOVE_RECURSE "${root}")
    file(MAKE_DIRECTORY "${root}")

    string(REPLACE "@PREFIX@" "${KONTRA_TEST_PREFIX}" body "${body}")
    file(WRITE "${root}/failure.cmake" "${body}")
    execute_process(
        COMMAND "${CMAKE_COMMAND}" -P "${root}/failure.cmake"
        RESULT_VARIABLE result
        OUTPUT_VARIABLE output
        ERROR_VARIABLE error
    )
    set(log "${output}${error}")

    if(result EQUAL 0 OR NOT log MATCHES "Kontraband\\[${expected}\\]:")
        message(FATAL_ERROR "${name} did not fail with Kontraband[${expected}]:\n${log}")
    endif()
endfunction()

# Wrap one failure case in the common outer and nested project boilerplate.
function(kontra_failure_outer out_source body)
    string(CONCAT source
        "cmake_minimum_required(VERSION 3.31.6)\n"
        "project(failure LANGUAGES NONE)\n"
        "find_package(kontraband CONFIG REQUIRED)\n"
        "${body}"
    )
    set("${out_source}" "${source}" PARENT_SCOPE)
endfunction()

function(kontra_failure_nested out_source languages body)
    string(CONCAT source
        "cmake_minimum_required(VERSION 3.31.6)\n"
        "project(failure_kernel LANGUAGES ${languages})\n"
        "${body}"
    )
    set("${out_source}" "${source}" PARENT_SCOPE)
endfunction()

# Most failures only need an ordinary C OBJECT target in the nested graph.
kontra_failure_nested(valid_nested "C" [=[
add_library(other OBJECT other.c)
]=])

# Graph failure tests usually register this otherwise valid nested target as their module.
kontra_failure_outer(module_outer [=[
kontra_add_kernel_project(kernel KERNEL_BUILD_DIRECTORY "@KERNEL@")
kontra_add_kernel_module(other PROJECT kernel)
]=])
