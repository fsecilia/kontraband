# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Frank Secilia

cmake_minimum_required(VERSION 3.31.6)
project(kontra_fixture_kernel LANGUAGES C CXX)

if(NOT FIXTURE_PROJECT_ARGUMENT)
    message(FATAL_ERROR "FIXTURE_PROJECT_ARGUMENT was not forwarded")
endif()
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/compiler-arg.txt" "${CMAKE_C_COMPILER_ARG1}")

# Use the global flag variable here to test compiler options that CMake cannot attribute to a target. Normal users
# should prefer target_compile_options() so the File API records where each option came from.
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -DFIXTURE_GLOBAL_CXX_FLAG=1")
include("${CMAKE_CURRENT_LIST_DIR}/../config.cmake")

add_library(fixture_interface INTERFACE)
target_sources(fixture_interface INTERFACE
    "${CMAKE_CURRENT_LIST_DIR}/../include/fixture/interface.hpp"
)
target_compile_definitions(fixture_interface INTERFACE FIXTURE_INTERFACE=1)

add_library(fixture_core OBJECT EXCLUDE_FROM_ALL)
fixture_configure_core(fixture_core)
target_link_libraries(fixture_core PUBLIC fixture_interface)

# The sibling OBJECT targets make dependency traversal and object order visible in the generated Kbuild object list.
add_library(fixture_alpha OBJECT EXCLUDE_FROM_ALL alpha.cpp)
add_library(fixture_beta OBJECT EXCLUDE_FROM_ALL beta.cpp)
add_library(fixture_zeta OBJECT EXCLUDE_FROM_ALL zeta.cpp)

add_library(fixture_module OBJECT EXCLUDE_FROM_ALL)

# These properties make CMake emit compiler options with no target attribution. The test checks that Kontraband warns
# about and drops options it cannot safely separate from flags added by Kbuild.
set_target_properties(fixture_module PROPERTIES
    OUTPUT_NAME nested_name_is_not_the_module_name
    POSITION_INDEPENDENT_CODE ON
    COMPILE_WARNING_AS_ERROR ON
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN ON
)
target_sources(fixture_module PRIVATE
    entry.c
    bridge_impl.cpp
    bridge.hpp
    unused.hpp
)
target_link_libraries(fixture_module PRIVATE
    fixture_zeta
    fixture_core
    fixture_alpha
    fixture_beta
)
# Explicit target options are supported because the File API preserves where they were declared.
target_compile_options(fixture_module PRIVATE
    "$<$<COMPILE_LANGUAGE:C>:-DFIXTURE_C_OPTION=1>"
    "$<$<COMPILE_LANGUAGE:CXX>:-DFIXTURE_CXX_OPTION=1>"
)

add_library(fixture_aux OBJECT EXCLUDE_FROM_ALL)
target_sources(fixture_aux PRIVATE aux.c aux.hpp)
target_link_libraries(fixture_aux PRIVATE fixture_interface)
