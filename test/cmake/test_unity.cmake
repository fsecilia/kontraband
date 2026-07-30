# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

include("${CMAKE_CURRENT_LIST_DIR}/test_common.cmake")

# This target must fail because CMake generated the compilation unit for it.
function(kontra_expect_unity_failure name languages target_body)
    set(root "${KONTRA_TEST_CASE_ROOT}/${name}")
    set(source "${root}/source")
    set(build "${root}/build")
    file(REMOVE_RECURSE "${root}")
    file(MAKE_DIRECTORY "${source}/kernel")

    file(WRITE "${source}/CMakeLists.txt" [=[
cmake_minimum_required(VERSION 3.31.6)
project(unity_outer LANGUAGES NONE)
find_package(kontraband CONFIG REQUIRED)
kontra_add_kernel_project(kernel KERNEL_BUILD_DIRECTORY "@KERNEL@")
kontra_add_kernel_module(module PROJECT kernel)
]=])
    file(READ "${source}/CMakeLists.txt" outer)
    string(REPLACE "@KERNEL@" "${KONTRA_TEST_FIXTURE_ROOT}/fake_kernel" outer "${outer}")
    file(WRITE "${source}/CMakeLists.txt" "${outer}")

    foreach(file IN ITEMS a.c b.c a.cpp b.cpp)
        file(WRITE "${source}/kernel/${file}" "// SPDX-License-Identifier: MIT\n")
    endforeach()
    string(CONCAT nested_cmake
        "cmake_minimum_required(VERSION 3.31.6)\n"
        "project(unity_kernel LANGUAGES ${languages})\n"
        "${target_body}\n"
    )
    file(WRITE "${source}/kernel/CMakeLists.txt" "${nested_cmake}")

    execute_process(
        COMMAND "${CMAKE_COMMAND}" -S "${source}" -B "${build}" -G Ninja
            "-DCMAKE_PREFIX_PATH=${KONTRA_TEST_PREFIX}"
        RESULT_VARIABLE result
        OUTPUT_VARIABLE output
        ERROR_VARIABLE error
    )
    set(log "${output}${error}")
    if(result EQUAL 0 OR NOT log MATCHES "Kontraband\\[unsupported-generated-source\\]:")
        message(FATAL_ERROR "${name} did not reject its CMake-synthesized unity source:\n${log}")
    endif()
    if(NOT log MATCHES "synthesized by CMake")
        message(FATAL_ERROR "${name} did not identify the synthesized compilation unit:\n${log}")
    endif()
endfunction()

kontra_expect_unity_failure(
    c
    "C"
    "add_library(module OBJECT a.c b.c)\nset_target_properties(module PROPERTIES UNITY_BUILD ON)"
)
kontra_expect_unity_failure(
    cxx
    "CXX"
    "add_library(module OBJECT a.cpp b.cpp)\nset_target_properties(module PROPERTIES UNITY_BUILD ON)"
)
kontra_expect_unity_failure(
    mixed
    "C CXX"
    "add_library(module OBJECT a.c b.c a.cpp b.cpp)\nset_target_properties(module PROPERTIES UNITY_BUILD ON)"
)
