# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

cmake_minimum_required(VERSION 3.31.6)
project(kontra_real_kernel LANGUAGES C CXX ASM)

# Keep the C++ support in a separate OBJECT target so the fixture covers transitive usage requirements and a module with
# C, C++, and assembly together. The UTF-8 path, duplicate template instantiations, and virtual dispatch are deliberate.
add_library(real_support OBJECT
    support.cpp
    support.hpp
    "café/comdat_a.cpp"
    "café/comdat_b.cpp"
    virtual.cpp
    virtual_use.cpp
)
target_sources(real_support PRIVATE
    FILE_SET HEADERS
    BASE_DIRS "${CMAKE_CURRENT_SOURCE_DIR}/include"
    FILES
        "${CMAKE_CURRENT_SOURCE_DIR}/include/kontra_real/comdat.hpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/include/kontra_real/config.hpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/include/kontra_real/virtual.hpp"
)
target_include_directories(real_support PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_compile_definitions(real_support PRIVATE KONTRA_REAL_VALUE=37)
target_compile_features(real_support PRIVATE cxx_std_20)

# Test only: test_real_kernel.cmake uses -Werror in its focused W=123 build so any Kbuild warning meant only for C fails
# if it leaks into the C++ rule. This is not a recommendation to use -Werror for all client kernel code.
target_compile_options(real_support PRIVATE "$<$<COMPILE_LANGUAGE:CXX>:-Werror>")

add_library(kontra_real OBJECT entry.c asm.S)
target_link_libraries(kontra_real PRIVATE real_support)
target_compile_definitions(kontra_real PRIVATE
    "$<$<COMPILE_LANGUAGE:ASM>:KONTRA_REAL_ASM=1>"
)
