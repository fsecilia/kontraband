# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

cmake_minimum_required(VERSION 3.31.6)
project(kontra_cross_fixture_kernel LANGUAGES C CXX)

file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/cross-state.txt"
    "system_name=${CMAKE_SYSTEM_NAME}\n"
    "system_processor=${CMAKE_SYSTEM_PROCESSOR}\n"
    "crosscompiling=${CMAKE_CROSSCOMPILING}\n"
    "try_compile_target_type=${CMAKE_TRY_COMPILE_TARGET_TYPE}\n"
    "c_compiler_arg1=${CMAKE_C_COMPILER_ARG1}\n"
    "cxx_compiler_arg1=${CMAKE_CXX_COMPILER_ARG1}\n"
)
