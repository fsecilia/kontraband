# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

cmake_minimum_required(VERSION 3.31.6)
project(kontra_arguments_kernel LANGUAGES CXX)

if(NOT FIXTURE_LIST_VALUE STREQUAL "alpha;beta" OR NOT FIXTURE_SECOND_VALUE STREQUAL "gamma")
    message(FATAL_ERROR
        "CMAKE_ARGUMENTS were not preserved: '${FIXTURE_LIST_VALUE}', '${FIXTURE_SECOND_VALUE}'"
    )
endif()
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/cmake-argument.txt" "${FIXTURE_LIST_VALUE}\n${FIXTURE_SECOND_VALUE}\n")
file(WRITE
    "${CMAKE_CURRENT_BINARY_DIR}/optimize-dependencies.txt"
    "${CMAKE_OPTIMIZE_DEPENDENCIES}\n"
)

# Use target_compile_options() here because CMake removes '#' from target_compile_definitions() before Kontraband can
# see it. Compiler options, however, must pass through generated Kbuild unchanged.
add_library(argument_module OBJECT EXCLUDE_FROM_ALL argument.cpp)
target_compile_options(argument_module PRIVATE
    [=[-DKONTRA_HASH_OPTION_0=a#b]=]
    [=[-DKONTRA_HASH_OPTION_1=a\#b]=]
    [=[-DKONTRA_HASH_OPTION_2=a\\#b]=]
    [=[-DKONTRA_HASH_OPTION_3=a\\\#b]=]
)
